#!/usr/bin/env bash
# Agent prompt benchmark. The scoring is deterministic; the generation is not.
#
#   run.sh --dry-run                    validate the set, zero agents, zero API
#   run.sh --prompt <fixture>           print the prompt to run the agent with
#   run.sh --score  <fixture> <report>  score a produced report against ground truth
#   run.sh --save-baseline              fold the last scores into baselines/tester.json
#
# Why it is split. A prompt diff currently ships on one operator's judgement:
# the 154 checks verify prompt STRUCTURE — frontmatter, forbidden block, leaf
# clause — and never prompt BEHAVIOUR. So the self-evaluation loop can drift
# indefinitely while every check stays green. Fixtures + ground truth + a
# committed baseline is the smallest thing that makes "this diff helped" a
# number instead of an opinion.
#
# Only --score touches an agent's output, and even then the agent is run by
# Irfan or the orchestrator, never by this script. A benchmark harness that
# spawns agents cannot live in a zero-agent check suite.

set -uo pipefail

B="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT="${TG_BENCH_AGENT:-tester}"
SET="$B/$AGENT"

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

validate() {
  local rc=0
  [ -d "$SET/fixtures" ] && [ -d "$SET/ground-truth" ] || {
    echo "benchmark: $SET is missing fixtures/ or ground-truth/" >&2; return 1; }

  node -e '
    const fs = require("fs"), path = require("path");
    const set = process.argv[1];
    const fx = fs.readdirSync(path.join(set, "fixtures")).map(f => f.replace(/\..*$/, "")).sort();
    const gt = fs.readdirSync(path.join(set, "ground-truth"))
                 .filter(f => f.endsWith(".json")).map(f => f.replace(/\.json$/, "")).sort();
    if (JSON.stringify(fx) !== JSON.stringify(gt)) {
      console.error("fixture/ground-truth mismatch\n  fixtures: " + fx + "\n  truth: " + gt);
      process.exit(1);
    }
    // the clean case must expect zero findings, or the benchmark rewards noise
    const clean = gt.find(n => /clean|correct/.test(n));
    if (!clean) { console.error("no clean fixture — false positives go unmeasured"); process.exit(1); }
    const exp = JSON.parse(fs.readFileSync(path.join(set, "ground-truth", clean + ".json"), "utf8"));
    if ((exp.required_findings || []).length !== 0) { console.error("clean fixture expects findings"); process.exit(1); }
    for (const id of gt) {
      const g = JSON.parse(fs.readFileSync(path.join(set, "ground-truth", id + ".json"), "utf8"));
      for (const f of g.required_findings || [])
        if (!Array.isArray(f.must_mention) || !f.must_mention.length)
          { console.error(id + ": finding " + f.id + " has nothing to match on"); process.exit(1); }
      if (!["PASS","FAIL"].includes(g.expect_verdict))
        { console.error(id + ": expect_verdict must be PASS or FAIL"); process.exit(1); }
    }
    console.log("benchmark: " + gt.length + " case(s) — " + gt.join(", "));
  ' "$SET" || rc=1

  [ -f "$B/baselines/$AGENT.json" ] || { echo "benchmark: no baseline at baselines/$AGENT.json" >&2; rc=1; }
  return $rc
}

case "${1:-}" in
  --dry-run)
    validate || exit 1
    echo "benchmark: dry run ok — set is well-formed, no agent was run"
    exit 0
    ;;

  --prompt)
    FIX="${2:-}"; [ -n "$FIX" ] || usage 2
    [ -d "$SET/fixtures/$FIX" ] || { echo "no fixture $FIX" >&2; exit 2; }
    cat <<EOF
Follow ~/.claude/team-graph/agents/$AGENT.md as your system prompt.

Fixture: $SET/fixtures/$FIX
Spec:    $SET/fixtures/$FIX/task-1.md

Test the change in that folder against the spec. Output the test report and
nothing else. Do not fix anything.
EOF
    exit 0
    ;;

  --score)
    FIX="${2:-}"; REPORT="${3:-}"
    [ -n "$FIX" ] && [ -f "$REPORT" ] || usage 2
    TG_FIX="$FIX" node -e '
      const fs = require("fs"), path = require("path");
      const [set, report] = process.argv.slice(1);
      const id = process.env.TG_FIX;
      const g = JSON.parse(fs.readFileSync(path.join(set, "ground-truth", id + ".json"), "utf8"));
      const text = fs.readFileSync(report, "utf8").toLowerCase();
      const hit = f => f.must_mention.every(s => text.includes(String(s).toLowerCase()));

      const req = g.required_findings || [];
      const found = req.filter(hit);
      const missed = req.filter(f => !hit(f));
      const fp = (g.forbidden_findings || []).filter(hit);
      const verdict = /verdict:\s*(pass|fail)/.exec(text);
      const gotVerdict = verdict ? verdict[1].toUpperCase() : null;

      const score = {
        fixture: id,
        required: req.length,
        found: found.length,
        missed: missed.map(f => f.id),
        false_positives: fp.map(f => f.id),
        verdict_expected: g.expect_verdict,
        verdict_got: gotVerdict,
        verdict_ok: gotVerdict === g.expect_verdict,
      };
      score.pass = score.found === score.required && !score.false_positives.length && score.verdict_ok;
      console.log(JSON.stringify(score, null, 2));
      const out = path.join(set, "..", "baselines", ".last-" + id + ".json");
      fs.writeFileSync(out, JSON.stringify(score, null, 2) + "\n");
      process.exit(score.pass ? 0 : 1);
    ' "$SET" "$REPORT"
    exit $?
    ;;

  --save-baseline)
    node -e '
      const fs = require("fs"), path = require("path");
      const dir = process.argv[1], agent = process.argv[2];
      const file = path.join(dir, agent + ".json");
      const base = JSON.parse(fs.readFileSync(file, "utf8"));
      let n = 0;
      for (const f of fs.readdirSync(dir).filter(f => f.startsWith(".last-"))) {
        const s = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
        base.scores[s.fixture] = s; n++;
        fs.unlinkSync(path.join(dir, f));
      }
      if (!n) { console.error("nothing scored since the last save"); process.exit(1); }
      base.measured = true;
      fs.writeFileSync(file, JSON.stringify(base, null, 2) + "\n");
      console.log("baseline updated with " + n + " fixture(s) — commit it");
    ' "$B/baselines" "$AGENT"
    exit $?
    ;;

  ""|--help|-h)
    validate
    echo
    usage 0
    ;;

  *) usage 2 ;;
esac
