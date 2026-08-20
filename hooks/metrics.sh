#!/usr/bin/env bash
# Write runs/<id>/metrics.json from command-sourced facts. Zero self-assessment.
#
#   usage: metrics.sh <run-dir> <route> <tool_calls> <budget> [key=value ...]
#
#   keys: folders, context_maps_used, maps_refreshed, human_overrides  (comma-separated lists)
#         gate_fails  (semicolon-separated "stage:reason" pairs)
#         retries, escalated, shipped
#         route_outcome  (correct | should-have-run | should-have-handed-back | wrong-tier)
#         human_minutes  (HAND-BACK only — the real cost of doing it by hand)
#         review_rounds, post_ship_fix  (the R-id a later run had to re-fix)
#
# Cost fields alone cannot see quality falling: an optimiser fed only budget
# numbers tunes toward cheapness forever while the table keeps improving.
# gate_caught, review_rounds and post_ship_fix are the counterweight, and
# route_outcome is the only thing that makes the routing rubric falsifiable —
# a HAND-BACK that should have run looks identical to a correct one otherwise.
#
# over_budget is derived, never passed. retries comes from retries.json when it
# exists, tool_calls from ledger.log when it exists — a number typed by an agent
# is a number an agent can flatter.

set -uo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RUN_DIR="${1:-}"; ROUTE="${2:-}"; CALLS="${3:-0}"; BUDGET="${4:-0}"; shift 4 2>/dev/null || true

[ -z "$RUN_DIR" ] || [ -z "$ROUTE" ] && { echo "usage: metrics.sh <run-dir> <route> <tool_calls> <budget> [k=v ...]" >&2; exit 2; }

mkdir -p "$RUN_DIR"

# tool_calls: authoritative source is the ledger journal. The passed value is a
# fallback for runs recorded before the hook existed, and loses to the ledger
# whenever the two disagree.
if [ -f "$RUN_DIR/ledger.log" ]; then
  LEDGER=$(bash "$HOOKS/ledger.sh" read "$RUN_DIR" 2>/dev/null)
  if [ -n "$LEDGER" ]; then
    [ "$LEDGER" != "$CALLS" ] && \
      echo "metrics: ledger counted $LEDGER tool calls — passed value $CALLS ignored" >&2
    CALLS="$LEDGER"
  fi
fi

# retries: authoritative source is retry-guard's own state file
RETRIES=0
if [ -f "$RUN_DIR/retries.json" ]; then
  RETRIES=$(node -e '
    try { const s = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
          console.log(Object.values(s).reduce((a,b)=>a+b,0)); }
    catch { console.log(0); }' "$RUN_DIR/retries.json" 2>/dev/null || echo 0)
fi

# key=value pairs go through as separate argv entries, never as one
# whitespace-joined string — a reason like "unit tests:boundary case" has
# spaces in it and splitting on whitespace silently truncates the record.
# review_rounds: the resume point already records every node that finished, so
# count the lead entries there rather than taking the orchestrator's word.
ROUNDS=""
if [ -f "$RUN_DIR/run-state.json" ]; then
  ROUNDS=$(node -e '
    try { const s = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
          const n = (s.completed||[]).filter(x => /^lead/.test(x)).length;
          if (n) console.log(n); }
    catch {}' "$RUN_DIR/run-state.json" 2>/dev/null)
fi

TG_ROUNDS="$ROUNDS" TG_RUN_ID="$(basename "$RUN_DIR")" TG_ROUTE="$ROUTE" \
TG_CALLS="$CALLS" TG_BUDGET="$BUDGET" TG_RETRIES="$RETRIES" \
node -e '
  const fs = require("fs");
  const kv = {};
  for (const pair of process.argv.slice(2)) {
    const i = pair.indexOf("=");
    if (i > 0) kv[pair.slice(0, i)] = pair.slice(i + 1);
  }
  const list = k => (kv[k] || "").split(",").map(s => s.trim()).filter(Boolean);
  const bool = k => kv[k] === "true" || kv[k] === "1";
  const calls = Number(process.env.TG_CALLS) || 0;
  const budget = Number(process.env.TG_BUDGET) || 0;

  const gateFails = (kv.gate_fails || "").split(";").filter(Boolean).map(p => {
    const i = p.indexOf(":");
    return i > 0 ? { stage: p.slice(0, i), reason: p.slice(i + 1) }
                 : { stage: p, reason: "" };
  });

  // A gate failure is a caught DEFECT only when the stage is one gate.sh emits
  // about the code. Everything else — a missing coverage provider, a wrong
  // command in config.md — is environment noise, and counting it as a catch
  // would let a broken setup read as a working quality signal.
  const DEFECT = /^(typecheck|unit tests|stub tests|coverage dropped)/;
  const gateCaught = gateFails.filter(g => DEFECT.test(g.stage)).length;

  // route_outcome is the one field Irfan types, and a typo in it is worse than
  // a blank: it would count as evidence. Unknown value → null, loudly.
  const OUTCOMES = ["correct", "should-have-run", "should-have-handed-back", "wrong-tier"];
  let outcome = kv.route_outcome || null;
  if (outcome && !OUTCOMES.includes(outcome)) {
    console.error(`metrics: route_outcome "${outcome}" is not one of ${OUTCOMES.join("|")} — recorded as null`);
    outcome = null;
  }

  const num = k => (kv[k] === undefined || kv[k] === "" || isNaN(Number(kv[k]))) ? null : Number(kv[k]);

  const out = {
    id: process.env.TG_RUN_ID,
    date: kv.date || new Date().toISOString().slice(0, 10),
    route: process.env.TG_ROUTE,
    folders: list("folders"),
    tool_calls: calls,
    budget,
    over_budget: budget > 0 && calls > budget,
    gate_fails: gateFails,
    gate_caught: gateCaught,
    retries: Number(process.env.TG_RETRIES) || 0,
    escalated: bool("escalated"),
    context_maps_used: list("context_maps_used"),
    maps_refreshed: list("maps_refreshed"),
    human_overrides: list("human_overrides"),
    shipped: bool("shipped"),
    route_outcome: outcome,
    human_minutes: num("human_minutes"),
    review_rounds: Number(process.env.TG_ROUNDS) || num("review_rounds"),
    post_ship_fix: kv.post_ship_fix || null,
  };
  // TG_BENCH_MODEL is set only by the benchmark harness. Stamping it means a
  // benchmark metrics.json can never be mistaken for a production run — the
  // production model matrix (haiku: never) is untouched.
  if (process.env.TG_BENCH_MODEL) out.bench_model = process.env.TG_BENCH_MODEL;
  const file = process.argv[1];
  fs.writeFileSync(file + ".tmp", JSON.stringify(out, null, 2) + "\n");
  fs.renameSync(file + ".tmp", file);
  console.log(`metrics → ${file} · route=${out.route} calls=${out.tool_calls}/${out.budget}` +
              (out.over_budget ? " OVER" : "") + ` retries=${out.retries}` +
              ` gate_fails=${out.gate_fails.length} caught=${out.gate_caught}` +
              ` outcome=${out.route_outcome ?? "unrecorded"}`);
' "$RUN_DIR/metrics.json" "$@"
