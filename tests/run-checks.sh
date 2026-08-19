#!/usr/bin/env bash
# team-graph verification harness. Deterministic, zero agents.
# Every check must pass. Any failure exits non-zero.
#
#   bash ~/.claude/team-graph/tests/run-checks.sh

set -uo pipefail

TG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$TG/tests/fixture"
GATE="$TG/hooks/gate.sh"
GUARD="$TG/hooks/retry-guard.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/tg-checks.XXXXXX")

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
head2() { echo; echo "── $1"; }

# The harness must leave the fixture exactly as it found it. A check run that
# mutates the repo it lives in makes the next run test something different.
cleanup() {
  rm -f "$FIXTURE/src/stub.test.ts" "$FIXTURE/src/typeerror.ts" "$FIXTURE/.tg-active"
  rm -f "$FIXTURE/src/vacuous.ts" "$FIXTURE/src/vacuous.test.ts" "$FIXTURE/src/cart.ts.mutbak"
  find "$FIXTURE/src" -name '*.tg-mutant-bak' -delete 2>/dev/null
  git -C "$FIXTURE" checkout -- src 2>/dev/null
  [ -f "$FIXTURE/src/cart.test.ts.bak" ] && mv "$FIXTURE/src/cart.test.ts.bak" "$FIXTURE/src/cart.test.ts"
  rm -rf "$FIXTURE/.team-irfan" "$FIXTURE/docs" "$FIXTURE/.gitignore"
  rm -rf "$TG/runs/99999999-live"
  rm -rf "$TMP"
}
trap cleanup EXIT

[ -d "$FIXTURE/node_modules" ] || {
  echo "fixture deps missing — run: (cd $FIXTURE && npm install)"; exit 2; }

cd "$FIXTURE" || exit 2
rm -f src/stub.test.ts src/typeerror.ts

# ── 1. gate rejects stub tests, naming file:line ─────────────────────────────
head2 "1. gate.sh with a stub test → exit 1, file:line named"
cp stub.test.ts.disabled src/stub.test.ts
OUT=$(TG_SCAN=all bash "$GATE" 2>&1); RC=$?
rm -f src/stub.test.ts

[ "$RC" -eq 1 ] && ok "exit 1" || bad "expected exit 1, got $RC"
grep -q 'GATE FAIL: stub tests detected' <<< "$OUT" \
  && ok "verdict is GATE FAIL: stub tests detected" \
  || bad "verdict line missing"

for pat in 'expect(true)' 'assert.ok(true)' 'it.skip' 'it.todo' 'empty test body'; do
  if grep -qF "$pat" <<< "$OUT"; then ok "caught $pat"; else bad "missed $pat"; fi
done
# every reported hit must carry file:line
if grep -qE 'src/stub\.test\.ts:[0-9]+' <<< "$OUT"; then
  ok "hits carry file:line ($(grep -coE 'src/stub\.test\.ts:[0-9]+' <<< "$OUT") reported)"
else
  bad "no file:line in output"
fi

# ── 2. gate passes on the clean fixture ──────────────────────────────────────
head2 "2. gate.sh on the clean fixture → exit 0, GATE PASS"
OUT=$(TG_SCAN=all bash "$GATE" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "exit 0" || { bad "expected exit 0, got $RC"; echo "$OUT" | tail -20; }
grep -q '^GATE PASS$' <<< "$OUT" && ok "verdict is GATE PASS" || bad "GATE PASS missing"
grep -q 'typecheck ok'   <<< "$OUT" && ok "typecheck ran"   || bad "typecheck did not run"
grep -q 'unit tests ok'  <<< "$OUT" && ok "unit tests ran"  || bad "unit tests did not run"
grep -q 'runner=vitest'  <<< "$OUT" && ok "detected vitest" || bad "runner not detected"

# ── 2b. gate catches a type error ────────────────────────────────────────────
head2 "2b. gate.sh with a type error → exit 1 at typecheck"
printf 'export const broken: number = "not a number"\n' > src/typeerror.ts
OUT=$(TG_SCAN=all bash "$GATE" 2>&1); RC=$?
rm -f src/typeerror.ts
[ "$RC" -eq 1 ] && ok "exit 1" || bad "expected exit 1, got $RC"
grep -q 'GATE FAIL: typecheck' <<< "$OUT" && ok "failed at typecheck" || bad "wrong failure stage"

# ── 2c. gate catches a failing unit test ─────────────────────────────────────
head2 "2c. gate.sh with a failing unit test → exit 1 at unit tests"
cp src/cart.test.ts src/cart.test.ts.bak
printf "\nimport { it as it_, expect as expect_ } from 'vitest'\nit_('deliberately failing check', () => { expect_(1).toBe(2) })\n" >> src/cart.test.ts
OUT=$(TG_SCAN=all bash "$GATE" 2>&1); RC=$?
mv src/cart.test.ts.bak src/cart.test.ts
[ "$RC" -eq 1 ] && ok "exit 1" || bad "expected exit 1, got $RC"
grep -q 'GATE FAIL: unit tests' <<< "$OUT" && ok "failed at unit tests" || bad "wrong failure stage"

# ── 3. retry-guard escalates on the 3rd call ─────────────────────────────────
head2 "3. retry-guard.sh ×3 → ESCALATE on the 3rd"
RUN="$TMP/run"
O1=$(bash "$GUARD" "$RUN" T1); R1=$?
O2=$(bash "$GUARD" "$RUN" T1); R2=$?
O3=$(bash "$GUARD" "$RUN" T1); R3=$?
[ "$R1" -eq 0 ] && grep -q 'RETRY 1/2' <<< "$O1" && ok "1st → RETRY 1/2, exit 0" || bad "1st: rc=$R1 $O1"
[ "$R2" -eq 0 ] && grep -q 'RETRY 2/2' <<< "$O2" && ok "2nd → RETRY 2/2, exit 0" || bad "2nd: rc=$R2 $O2"
[ "$R3" -eq 1 ] && grep -q 'ESCALATE'  <<< "$O3" && ok "3rd → ESCALATE, exit 1"  || bad "3rd: rc=$R3 $O3"
# a different task id must have its own counter
O4=$(bash "$GUARD" "$RUN" T2); R4=$?
[ "$R4" -eq 0 ] && grep -q 'RETRY 1/2' <<< "$O4" && ok "counters are per task id" || bad "T2 leaked T1's count"

# ── 4. templates carry their required field headings ─────────────────────────
head2 "4. templates exist and carry their required fields"
check_fields() {
  local file="$TG/templates/$1"; shift
  if [ ! -f "$file" ]; then bad "$1 missing"; return; fi
  local missing=""
  for f in "$@"; do grep -qF "$f" "$file" || missing="$missing '$f'"; done
  [ -z "$missing" ] && ok "$1" || bad "$1 missing:$missing"
}
check_fields change-summary.md '## What changed' '## Files' '## How to verify' '## Gate output'
check_fields test-report.md    'verdict:' '## Cases' '## Evidence' '## Bugs found' '## Not covered'
check_fields report.md         'verdict:' '## Backward compatibility' '## Gate' '## Scope' '## Findings' '**Verdict:**'
# plan.md is the merged Product artifact: it absorbed scope.md (business rules
# with sources, scope in/out, open questions) and task-spec.md (per-task spec
# blocks: files in scope, acceptance criteria, independent lanes).
check_fields plan.md           '## Open questions for Irfan' '## Goal' '## Work list' '## Business rules' '## Scope' '## SCOPE' '## PHASES' '## Tasks' '**Files in scope:**' '**Acceptance criteria:**' 'independent:' '## Test contract' '## Run cap'
check_fields test-cases.md     'source: plan.json ONLY' 'expect_status' 'expect_body' 'expect_effect' 'chrome-devtools-axi'
check_fields summary.md        '## What the team did' '## Changes' '## Test cases' '## How to test' '## Breaking changes' '## Lessons' '## What ran' '**Verdict:**'

# ── 4b. every agent contract declares its budget and forbidden list ──────────
head2 "4b. agent contracts declare budget + forbidden actions"
for a in router solo-executor product lead executor qa; do
  f="$TG/agents/$a.md"
  if [ ! -f "$f" ]; then bad "$a.md missing"; continue; fi
  grep -q '^budget:' "$f" && grep -q '^## Forbidden' "$f" \
    && ok "$a.md" || bad "$a.md missing budget: or ## Forbidden"
done

# ── 5. router rubric cases, for Irfan to eyeball ─────────────────────────────
head2 "5. router rubric cases — human judgement, not scored"
if [ -f "$TG/tests/cases.md" ]; then
  sed -n '/^| # |/,/^$/p' "$TG/tests/cases.md"
  ok "cases.md printed above"
else
  bad "cases.md missing"
fi

# ── 6. init scaffold: config.md with real detected commands ──────────────────
head2 "6. init-scaffold config → real commands from package.json"
cd "$FIXTURE" || exit 2
rm -rf .team-irfan
OUT=$(TG_SHA=testsha bash "$TG/hooks/init-scaffold.sh" config 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "exit 0" || { bad "exit $RC"; echo "$OUT"; }
CFG="$FIXTURE/.team-irfan/config.md"
if [ -f "$CFG" ]; then
  ok "config.md written"
  # keys are column-padded, so match "<key><spaces>: <value>"
  grep -qE '^typecheck *: npm typecheck$' "$CFG" && ok "typecheck command detected verbatim" || bad "typecheck line wrong: $(grep -m1 '^typecheck' "$CFG")"
  grep -qE '^test *: npm test$'           "$CFG" && ok "test command detected verbatim"      || bad "test line wrong: $(grep -m1 '^test ' "$CFG")"
  grep -qE '^coverage *: none$'           "$CFG" && ok "absent script written as none, not guessed" || bad "coverage should be none: $(grep -m1 '^coverage' "$CFG")"
  grep -q 'test runner | vitest'        "$CFG" && ok "runner detected"    || bad "runner not detected"
  for h in '## Stack' '## Commands' '## Conventions' '## Registry' '## Model matrix' '## Overrides'; do
    grep -qF "$h" "$CFG" && ok "config heading $h" || bad "config missing $h"
  done
else
  bad "config.md not written"
fi

# ── 6b. init scaffold: context map, headings + 80-line cap ───────────────────
head2 "6b. init-scaffold map → headings present, ≤80 lines, real last_commit"
OUT=$(bash "$TG/hooks/init-scaffold.sh" map src 2>&1); RC=$?
MAP="$FIXTURE/.team-irfan/context/src.md"
[ "$RC" -eq 0 ] && [ -f "$MAP" ] && ok "map written" || { bad "map not written (rc=$RC)"; echo "$OUT"; }
if [ -f "$MAP" ]; then
  for h in '## Purpose' '## Key files' '## Entry points' '## Conventions' '## Depends on / used by' '## Registry tags'; do
    grep -qF "$h" "$MAP" && ok "map heading $h" || bad "map missing $h"
  done
  grep -qE '^last_commit: [0-9a-f]{7,40}$' "$MAP" && ok "last_commit is a real sha" || bad "last_commit missing/!sha: $(grep -m1 last_commit "$MAP")"
  grep -qE '^folder: src$'                 "$MAP" && ok "folder recorded"           || bad "folder line wrong"
  L=$(wc -l < "$MAP" | tr -d ' ')
  [ "$L" -le 80 ] && ok "map is $L lines (cap 80)" || bad "map is $L lines, over the 80 cap"
fi
grep -q '^\.team-irfan/' "$FIXTURE/.gitignore" 2>/dev/null && ok ".team-irfan gitignored by init" || bad ".team-irfan not gitignored"
rm -rf "$FIXTURE/.team-irfan"

# ── 7. staleness detection, both directions ──────────────────────────────────
head2 "7. freshness check: changed folder stale, untouched folder fresh"
G="$TMP/staleness"
mkdir -p "$G/touched" "$G/untouched"
git -C "$G" init -q 2>/dev/null
echo 'a' > "$G/touched/a.ts"; echo 'b' > "$G/untouched/b.ts"
git -C "$G" add -A >/dev/null 2>&1
git -C "$G" -c user.name=t -c user.email=t@t commit -qm base >/dev/null 2>&1
BASE=$(git -C "$G" rev-parse HEAD)
echo 'a2' >> "$G/touched/a.ts"
git -C "$G" add -A >/dev/null 2>&1
git -C "$G" -c user.name=t -c user.email=t@t commit -qm change >/dev/null 2>&1

STALE=$(git -C "$G" diff --name-only "$BASE" -- touched)
FRESH=$(git -C "$G" diff --name-only "$BASE" -- untouched)
[ -n "$STALE" ] && ok "changed folder reports stale ($STALE)" || bad "changed folder reported fresh — refresh would never fire"
[ -z "$FRESH" ] && ok "untouched folder reports fresh"        || bad "untouched folder reported stale ($FRESH) — every run would re-read it"

# ── 8. metrics.json validates against the schema keys ────────────────────────
head2 "8. metrics.sh output matches the schema"
MRUN="$TMP/metrics-run"
bash "$TG/hooks/retry-guard.sh" "$MRUN" T1 >/dev/null 2>&1
OUT=$(bash "$TG/hooks/metrics.sh" "$MRUN" FAST 18 15 \
        folders=src context_maps_used=src gate_fails="unit tests:boundary case" shipped=true 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "exit 0" || { bad "exit $RC"; echo "$OUT"; }
if node -e '
  const m = require(process.argv[1]);
  const need = ["id","date","route","folders","tool_calls","budget","over_budget",
                "gate_fails","retries","escalated","context_maps_used","maps_refreshed",
                "human_overrides","shipped"];
  const missing = need.filter(k => !(k in m));
  if (missing.length) { console.error("missing: " + missing.join(",")); process.exit(1); }
  if (m.over_budget !== true) { console.error("over_budget not derived (18 > 15)"); process.exit(1); }
  if (m.retries !== 1) { console.error("retries not read from retries.json, got " + m.retries); process.exit(1); }
  if (m.gate_fails[0].reason !== "boundary case") { console.error("gate_fails reason truncated"); process.exit(1); }
' "$MRUN/metrics.json" 2>"$TMP/merr"; then
  ok "all 14 keys, over_budget derived, retries sourced, reason with spaces intact"
else
  bad "schema: $(cat "$TMP/merr")"
fi

# ── 9. every agent declares model + carries the forbidden block ──────────────
head2 "9. agents: model frontmatter + universal forbidden block + leaf clause"
for f in "$TG"/agents/*.md; do
  a=$(basename "$f" .md); miss=""
  grep -q '^model: \(opus\|sonnet\|haiku\)$'      "$f" || miss="$miss model:"
  grep -q '^## Forbidden actions (identical'      "$f" || miss="$miss forbidden-block"
  [ "$a" = router ] || grep -q '^## You are a leaf' "$f" || miss="$miss leaf-clause"
  [ -z "$miss" ] && ok "$a.md" || bad "$a.md missing:$miss"
done

# ── 9b. only the orchestrator may spawn ──────────────────────────────────────
head2 "9b. spawn instructions confined to the orchestrator"
SPAWNERS=$(grep -l 'Agent(' "$TG"/agents/*.md | xargs -n1 basename | grep -v '^router\.md$')
[ -z "$SPAWNERS" ] && ok "only router.md contains an Agent( call" \
                   || bad "leaf nodes instructing a spawn: $SPAWNERS"

# ── 10. ledger.sh counts deterministically and metrics.sh prefers it ─────────
head2 "10. ledger.sh counts deterministically and metrics.sh prefers it"
RUN="$TMP/ledger-run"; mkdir -p "$RUN"
bash "$TG/hooks/ledger.sh" bump "$RUN" exec-1
bash "$TG/hooks/ledger.sh" bump "$RUN" exec-1
bash "$TG/hooks/ledger.sh" bump "$RUN" tester
N=$(bash "$TG/hooks/ledger.sh" read "$RUN")
[ "$N" = "3" ] && ok "ledger totals 3 across two nodes" || bad "expected 3, got $N"
node -e '
  const l = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
  if (l["exec-1"] !== 2 || l["tester"] !== 1) { console.error(JSON.stringify(l)); process.exit(1); }
' "$RUN/ledger.json" && ok "per-node attribution kept" || bad "ledger.json lost per-node counts"

# metrics must ignore a passed total that disagrees with the ledger
bash "$TG/hooks/metrics.sh" "$RUN" FULL 999 60 shipped=true >/dev/null 2>&1
CALLS=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).tool_calls)' "$RUN/metrics.json")
[ "$CALLS" = "3" ] && ok "metrics.json used the ledger, not the passed 999" \
                   || bad "metrics.json trusted the agent-passed number ($CALLS)"

# no ledger → the passed number is still the fallback, not zero
RUNF="$TMP/ledger-fallback"; mkdir -p "$RUNF"
bash "$TG/hooks/metrics.sh" "$RUNF" FAST 11 15 shipped=true >/dev/null 2>&1
CF=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).tool_calls)' "$RUNF/metrics.json")
[ "$CF" = "11" ] && ok "no ledger → passed value still recorded" || bad "fallback broke, got $CF"

# concurrent bumps must not lose a write
RUN2="$TMP/ledger-race"; mkdir -p "$RUN2"
for i in $(seq 1 20); do bash "$TG/hooks/ledger.sh" bump "$RUN2" exec-1 & done; wait
N2=$(bash "$TG/hooks/ledger.sh" read "$RUN2")
[ "$N2" = "20" ] && ok "20 concurrent bumps all recorded" || bad "lost writes: $N2/20"

# hook mode is inert without the marker, and counts with it
HRUN="$TMP/ledger-hook"; mkdir -p "$HRUN" "$TMP/hookcwd"
( cd "$TMP/hookcwd" && echo '{}' | bash "$TG/hooks/ledger.sh" hook ) ; HRC=$?
[ "$HRC" -eq 0 ] && [ ! -f "$HRUN/ledger.log" ] \
  && ok "hook is inert with no .tg-active" || bad "hook fired outside a run (rc=$HRC)"
( cd "$TMP/hookcwd" && printf '%s\n' "$HRUN" > .tg-active \
  && echo '{"tool_name":"Bash"}' | bash "$TG/hooks/ledger.sh" hook )
[ "$(bash "$TG/hooks/ledger.sh" read "$HRUN")" = "1" ] \
  && ok "hook counts when .tg-active names the run" || bad "hook did not count"

# ── 11. reap.sh clears crash residue and never eats unmerged work ────────────
head2 "11. reap.sh clears crash residue and never eats unmerged work"
REPO="$TMP/reap"; mkdir -p "$REPO"
git -C "$REPO" init -q .
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
touch "$REPO/.tg-active"
git -C "$REPO" worktree add -q "$TMP/tg-orphan-1" -b feat/orphan-1 >/dev/null 2>&1
( cd "$REPO" && TG_REAP_AGE=0 bash "$TG/hooks/reap.sh" ) >/dev/null 2>&1
[ ! -f "$REPO/.tg-active" ] && ok "stale .tg-active removed" || bad ".tg-active survived"
git -C "$REPO" worktree list | grep -q 'tg-orphan-1' && bad "orphan worktree survived" \
                                                     || ok "orphan worktree removed"
git -C "$REPO" branch --list 'feat/orphan-1' | grep -q . \
  && ok "branch preserved, not deleted" || bad "reap deleted a branch"

# --dry-run must change nothing
touch "$REPO/.tg-active"
( cd "$REPO" && TG_REAP_AGE=0 bash "$TG/hooks/reap.sh" --dry-run ) >/dev/null 2>&1
[ -f "$REPO/.tg-active" ] && ok "--dry-run changed nothing" || bad "--dry-run deleted state"

# an ACTIVE run must survive a reap
mkdir -p "$TG/runs/99999999-live"
( cd "$REPO" && bash "$TG/hooks/reap.sh" ) >/dev/null 2>&1
[ -f "$REPO/.tg-active" ] && ok "live run untouched" || bad "reap killed a live run"
rm -rf "$TG/runs/99999999-live" "$REPO/.tg-active"
cd "$FIXTURE" || exit 2

# ── 12. a killed run is resumable from disk alone ────────────────────────────
head2 "12. a killed run is resumable from disk alone"
RUN="$TMP/resume"; mkdir -p "$RUN"
printf '# plan\n' > "$RUN/plan.md"
printf '{"run_cap":39}\n' > "$RUN/plan.json"
bash "$TG/hooks/run-state.sh" "$RUN" product exec-1 >/dev/null
bash "$TG/hooks/retry-guard.sh" "$RUN" T1 >/dev/null
# simulate the kill: nothing else exists

if node -e '
  const fs=require("fs"), d=process.argv[1];
  const st=JSON.parse(fs.readFileSync(d+"/run-state.json","utf8"));
  const fail=m=>{console.error(m);process.exit(1)};
  if (!st.completed.includes("product")) fail("cannot tell product finished");
  if (st.current !== "exec-1") fail("cannot tell where to resume");
  for (const f of st.completed.map(n=>({product:"plan.md"}[n])).filter(Boolean))
    if (!fs.existsSync(d+"/"+f)) fail("completed node has no artifact: "+f);
  const r=JSON.parse(fs.readFileSync(d+"/retries.json","utf8"));
  if (r.T1 !== 1) fail("retry count did not survive the kill");
' "$RUN" 2>"$TMP/rerr"; then
  ok "resume point, artifacts and retry count all survive"
else
  bad "run is not resumable from disk: $(cat "$TMP/rerr")"
fi
# re-recording a finished node must not duplicate it
bash "$TG/hooks/run-state.sh" "$RUN" product exec-1 >/dev/null
node -e '
  const st=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
  process.exit(st.completed.filter(n=>n==="product").length === 1 ? 0 : 1);
' "$RUN/run-state.json" && ok "completed list is idempotent" || bad "resume point duplicates nodes"

grep -q 'run-state.sh' "$TG/agents/router.md" \
  && ok "orchestrator writes run-state.json" || bad "nothing writes the resume point"
grep -q 'reap.sh' "$TG/agents/router.md" \
  && ok "orchestrator reaps before it starts" || bad "reap.sh never runs"
grep -q 'ledger.sh read' "$TG/agents/router.md" \
  && ok "orchestrator reads the ledger instead of counting" || bad "budget is still hand-counted"

# ── 13. evaluation refuses metric-derived tuning below n=5 ───────────────────
head2 "13. evaluation refuses metric-derived tuning below n=5"
grep -qE 'n *[<>=]+ *5|five runs|INSUFFICIENT DATA' "$TG/agents/evaluation.md" \
  && ok "threshold is stated" || bad "no n=5 threshold in evaluation.md"
grep -qi 'direct run review\|operator review' "$TG/agents/evaluation.md" \
  && ok "direct-review path stays open at any n" \
  || bad "no carve-out for direct review — evaluation is now useless at low n"
grep -q '^- Proposing a rubric change from aggregated' "$TG/agents/evaluation.md" \
  && ok "the floor is a forbidden action, not a disclaimer" \
  || bad "n=5 floor is advisory only"
COUNT=$(ls "$TG"/runs/*/metrics.json 2>/dev/null | wc -l | tr -d ' ')
echo "  INFO  current run count: $COUNT (rubric tuning unlocks at 5)"

# ── 14. every agent declares a node contract ─────────────────────────────────
head2 "14. every agent declares a node contract"
for f in "$TG"/agents/*.md; do
  n=$(basename "$f")
  MISS=""
  for k in timeout_ms max_attempts effect_policy; do
    grep -qE "^${k}:" "$f" || MISS="$MISS $k"
  done
  [ -z "$MISS" ] && ok "$n declares full contract" || bad "$n missing:$MISS"
  POL=$(grep -E '^effect_policy:' "$f" | awk '{print $2}')
  case "$POL" in
    side_effect_free|idempotent|reconcile) ok "$n policy=$POL" ;;
    *) bad "$n has invalid effect_policy '$POL'" ;;
  esac
  TMO=$(grep -E '^timeout_ms:' "$f" | awk '{print $2}')
  { [ "$TMO" -ge 100 ] && [ "$TMO" -le 86400000 ]; } 2>/dev/null \
    && ok "$n timeout_ms=$TMO in range" || bad "$n timeout_ms out of 100ms–24h: '$TMO'"
done
grep -q 'reconcile' "$TG/agents/router.md" \
  && ok "orchestrator documents the reconcile check" \
  || bad "no reconcile guard documented for merge/commit"
grep -q 'git log -1 --format=%s' "$TG/agents/router.md" \
  && ok "reconcile check is a command, not an intention" \
  || bad "reconcile guard names no way to detect a landed merge"

# retry policy lives in two places; they must not drift
LIMIT=$(grep -E '^LIMIT=' "$TG/hooks/retry-guard.sh" | head -1 | sed 's/^LIMIT=\([0-9]*\).*/\1/')
for a in executor qa; do
  MA=$(grep -E '^max_attempts:' "$TG/agents/$a.md" | awk '{print $2}')
  [ "$MA" = "$((LIMIT+1))" ] \
    && ok "$a max_attempts=$MA matches retry-guard LIMIT=$LIMIT" \
    || bad "$a max_attempts=$MA but retry-guard allows $((LIMIT+1)) attempts"
done

# ── 15. graph.json is valid, acyclic, and matches the agent files ────────────
head2 "15. graph.json is valid, acyclic, and matches the agent files"
if node -e '
  const fs = require("fs"), path = require("path");
  const TG = process.argv[1];
  const g = JSON.parse(fs.readFileSync(path.join(TG, "graph.json"), "utf8"));
  const ids = new Set(g.nodes.map(n => n.id));
  const fail = m => { console.error(m); process.exit(1); };

  // every edge endpoint exists
  for (const [a,b] of g.edges) {
    if (!ids.has(a)) fail("edge from unknown node: " + a);
    if (!ids.has(b)) fail("edge to unknown node: " + b);
  }
  // acyclic
  const adj = {}; for (const [a,b] of g.edges) (adj[a] ||= []).push(b);
  const seen = {}, walk = n => {
    if (seen[n] === 1) fail("cycle at " + n);
    if (seen[n] === 2) return; seen[n] = 1;
    for (const m of adj[n] || []) walk(m); seen[n] = 2;
  };
  for (const n of ids) walk(n);

  // INVARIANT: every node except the orchestrator is a leaf. leaf === true means
  // the orchestrator owns every edge, which is what makes F4 (a leaf told to
  // spawn a node) a structural impossibility rather than a prompt slip.
  for (const n of g.nodes)
    if (n.kind === "agent" && n.leaf !== true) fail("non-leaf agent node: " + n.id);

  // INVARIANT: exactly ONE human gate — the plan approval. A second gate is
  // drift back toward v2; zero means the plan ships itself.
  const gates = g.nodes.filter(n => n.kind === "human-approval");
  if (gates.length !== 1) fail("expected exactly 1 human gate, found " + gates.length);
  for (const gate of gates)
    if (!gate.prompt) fail("human gate with no prompt: " + gate.id);

  // every agent node has a real prompt file (node.prompt names a shared one)
  const promptOf = n => n.prompt || n.id;
  for (const n of g.nodes)
    if (n.kind === "agent" && !fs.existsSync(path.join(TG, "agents", promptOf(n) + ".md")))
      fail("no prompt file for node " + n.id);

  // and every prompt file is accounted for — a new agent cannot hide from the graph
  const declared = new Set([...g.nodes.map(promptOf), ...g.nodes.map(n=>n.id), ...(g.standalone||[]).map(n=>n.id)]);
  for (const f of fs.readdirSync(path.join(TG, "agents")).filter(f => f.endsWith(".md"))) {
    const id = f.replace(/\.md$/, "");
    if (!declared.has(id)) fail("agents/" + f + " appears in no graph node and no standalone entry");
  }

  // the graph and the frontmatter must agree on effect_policy
  for (const n of g.nodes) {
    if (n.kind !== "agent") continue;
    const fm = fs.readFileSync(path.join(TG, "agents", promptOf(n) + ".md"), "utf8");
    const m = fm.match(/^effect_policy:\s*(\S+)/m);
    if (!m) fail(promptOf(n) + ".md declares no effect_policy");
    if (m[1] !== n.effect_policy)
      fail(n.id + ": graph says " + n.effect_policy + ", frontmatter says " + m[1]);
  }
' "$TG" 2>"$TMP/gerr"; then
  ok "graph.json valid: acyclic, all-leaf, exactly 1 human gate, files exist, policies agree"
else
  bad "graph.json failed validation: $(cat "$TMP/gerr")"
fi

# ── 16. metrics carries quality fields, derived not asserted ─────────────────
head2 "16. metrics carries quality fields, derived not asserted"
RUN="$TMP/quality"; mkdir -p "$RUN"
bash "$TG/hooks/metrics.sh" "$RUN" FULL 40 60 \
  gate_fails="typecheck:missing return type;env:no coverage provider" \
  review_rounds=2 shipped=true >/dev/null 2>&1
if node -e '
  const m = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
  const need = ["gate_caught","review_rounds","post_ship_fix"];
  const missing = need.filter(k => !(k in m));
  if (missing.length) { console.error("missing: " + missing); process.exit(1); }
  if (m.gate_caught !== 1) { console.error("gate_caught should be 1 (env noise excluded), got " + m.gate_caught); process.exit(1); }
  if (m.review_rounds !== 2) { console.error("review_rounds not recorded"); process.exit(1); }
' "$RUN/metrics.json" 2>"$TMP/qerr"; then
  ok "quality fields present and derived correctly"
else
  bad "quality fields wrong: $(cat "$TMP/qerr")"
fi
# every real gate stage must count as a catch, or the signal is dead on arrival
RUN="$TMP/quality2"; mkdir -p "$RUN"
bash "$TG/hooks/metrics.sh" "$RUN" FULL 40 60 \
  gate_fails="unit tests:boundary;stub tests detected:expect(true);coverage dropped on changed files:cart.ts;setup:npm install failed" \
  >/dev/null 2>&1
GC=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).gate_caught)' "$RUN/metrics.json")
[ "$GC" = "3" ] && ok "all three code stages count, setup noise does not" \
                || bad "gate_caught=$GC, expected 3"
grep -q 'gate_caught' "$TG/agents/evaluation.md" \
  && ok "evaluation aggregates quality" || bad "evaluation ignores quality fields"

# review_rounds comes from the resume point when there is one, not from the agent
RUN="$TMP/rounds"; mkdir -p "$RUN"
bash "$TG/hooks/run-state.sh" "$RUN" lead gate-ship   >/dev/null
bash "$TG/hooks/run-state.sh" "$RUN" lead-2 gate-ship >/dev/null
bash "$TG/hooks/metrics.sh" "$RUN" FULL 40 60 review_rounds=1 >/dev/null 2>&1
RR=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).review_rounds)' "$RUN/metrics.json")
[ "$RR" = "2" ] && ok "review_rounds counted from run-state, not the passed 1" \
                || bad "review_rounds=$RR, expected 2 from the resume point"

# ── 17. route outcome recorded for every route, runs and non-runs alike ──────
head2 "17. route outcome recorded for every route, runs and non-runs alike"
for route in HAND-BACK QUESTION FAST FULL; do
  RUN="$TMP/route-$route"; mkdir -p "$RUN"
  bash "$TG/hooks/metrics.sh" "$RUN" "$route" 3 4 route_outcome=correct human_minutes=4 >/dev/null 2>&1
  node -e '
    const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    if (!("route_outcome" in m)) { console.error("route_outcome missing"); process.exit(1); }
    if (m.route_outcome !== "correct") { console.error("valid outcome not stored"); process.exit(1); }
    if (m.route==="HAND-BACK" && !("human_minutes" in m)) { console.error("human_minutes missing on HAND-BACK"); process.exit(1); }
  ' "$RUN/metrics.json" && ok "$route records outcome" || bad "$route missing outcome fields"
done
# an invalid value must be rejected, not silently stored
RUN="$TMP/route-bad"; mkdir -p "$RUN"
bash "$TG/hooks/metrics.sh" "$RUN" FAST 3 15 route_outcome=lgtm >/dev/null 2>&1
node -e '
  const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
  process.exit(m.route_outcome === "lgtm" ? 1 : 0);
' "$RUN/metrics.json" && ok "invalid outcome rejected" || bad "metrics stored a junk outcome"
# an unrecorded outcome is null, never a default of "correct"
RUN="$TMP/route-none"; mkdir -p "$RUN"
bash "$TG/hooks/metrics.sh" "$RUN" FULL 3 60 >/dev/null 2>&1
node -e '
  const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
  process.exit(m.route_outcome === null ? 0 : 1);
' "$RUN/metrics.json" && ok "no answer stays null, not correct" || bad "unrecorded outcome defaulted"
grep -q 'route_outcome' "$TG/agents/router.md" \
  && ok "router asks for the outcome" || bad "nothing ever records route_outcome"

# ── 18. run artifacts survive concurrent writers ─────────────────────────────
head2 "18. run artifacts survive concurrent writers"
RUN="$TMP/concurrent"; mkdir -p "$RUN"
for i in $(seq 1 10); do
  ( bash "$TG/hooks/retry-guard.sh" "$RUN" "T$i" >/dev/null 2>&1 ) &
done; wait
node -e '
  const s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
  const n=Object.keys(s).length;
  if (n!==10) { console.error("expected 10 task keys, got "+n); process.exit(1); }
' "$RUN/retries.json" && ok "10 concurrent retry-guard writers, no lost keys" \
                      || bad "retries.json lost a concurrent write"
[ -z "$(find "$RUN" -name '*.lock' -o -name '*.tmp' 2>/dev/null)" ] \
  && ok "no lock or tmp residue left behind" || bad "lock/tmp files survived the run"

grep -q 'coverage-base' "$TG/hooks/gate.sh" && \
grep -qE 'coverage-base[^"]*\$' "$TG/hooks/gate.sh" \
  && ok "coverage baseline path is parameterised per worktree" \
  || bad "coverage baseline is a single shared file across concurrent executors"
grep -q 'atomic_cp "$SUMMARY"' "$TG/hooks/gate.sh" \
  && ok "baseline is replaced atomically, never half-written" \
  || bad "baseline still written with a plain cp — readers can tear"

# a worktree with no baseline of its own must still read the run's
RUN="$TMP/covfall"; mkdir -p "$RUN"
printf '{"total":{"lines":{"pct":100}}}\n' > "$RUN/coverage-base.txt"
mkdir -p "$TMP/tg-fallback-1" && cd "$TMP/tg-fallback-1"
OUT=$(TG_RUN="$RUN" bash "$GATE" 2>&1)
grep -q 'no package.json' <<< "$OUT" && ok "gate still refuses a non-project dir" \
                                     || bad "gate ran outside a project"
cd "$FIXTURE" || exit 2
OUT=$(TG_RUN="$RUN" TG_SCAN=all bash "$GATE" 2>&1); RC=$?
grep -q 'coverage' <<< "$OUT" && ok "shared baseline is found from the main tree" \
                              || bad "baseline never consulted: $(tail -3 <<< "$OUT")"

# ── 19. mutation smoke catches a test that asserts nothing real ──────────────
head2 "19. mutation smoke catches a test that asserts nothing real"
cd "$FIXTURE" || exit 2
cp src/cart.ts src/cart.ts.mutbak
cat > src/vacuous.ts <<'EOF'
export function addTax(n: number): number { return n * 1.11 }
EOF
cat > src/vacuous.test.ts <<'EOF'
import { it, expect } from 'vitest'
import { addTax } from './vacuous.js'
it('does something', () => { expect(typeof addTax).toBe('function') })
EOF
OUT=$(TG_MUTATE=1 TG_SCAN=all bash "$GATE" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok "exit 1 on a vacuous test" || bad "expected exit 1, got $RC"
grep -q 'survive mutation' <<< "$OUT" && ok "named the mutation failure" || bad "wrong reason"
grep -q 'vacuous' <<< "$OUT" && ok "named the offending file" || bad "no file named"

rm -f src/vacuous.ts src/vacuous.test.ts
# and it must NOT fire on the real tests
OUT=$(TG_MUTATE=1 TG_SCAN=all bash "$GATE" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "no false positive on the honest fixture" || bad "mutation false-positived"
grep -q 'mutation smoke ok' <<< "$OUT" && ok "mutation actually ran" || bad "mutation silently skipped"
# the fixture must be byte-identical afterwards
diff -q src/cart.ts src/cart.ts.mutbak >/dev/null \
  && ok "mutation restored every file" || bad "mutation corrupted the fixture"
[ -z "$(find "$FIXTURE/src" -name '*.tg-mutant-bak' 2>/dev/null)" ] \
  && ok "no mutant backups left behind" || bad "mutation left .tg-mutant-bak residue"
rm -f src/cart.ts.mutbak
# off by default — nobody pays for it who did not ask
OUT=$(TG_SCAN=all bash "$GATE" 2>&1)
grep -q 'mutation' <<< "$OUT" && bad "mutation ran without TG_MUTATE=1" \
                              || ok "opt-in only, silent by default"
grep -q 'TG_MUTATE' "$TG/agents/qa.md" \
  && ok "qa is the node that runs it" || bad "nothing ever sets TG_MUTATE"

# ── 20. tester benchmark harness is wired and regression-guarded ─────────────
head2 "20. tester benchmark harness is wired and regression-guarded"
[ -f "$TG/benchmarks/run.sh" ] && ok "runner exists" || bad "no benchmark runner"
COUNT=$(ls "$TG"/benchmarks/tester/ground-truth/*.json 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -ge 3 ] && ok "$COUNT ground-truth cases" || bad "need >=3 cases, have $COUNT"

# every fixture has ground truth and vice versa — no orphans
if node -e '
  const fs=require("fs"), b=process.argv[1]+"/benchmarks/tester";
  const fx=fs.readdirSync(b+"/fixtures").map(f=>f.replace(/\..*$/,"")).sort();
  const gt=fs.readdirSync(b+"/ground-truth").map(f=>f.replace(/\.json$/,"")).sort();
  if (JSON.stringify(fx)!==JSON.stringify(gt)) {
    console.error("fixture/ground-truth mismatch\n  fixtures: "+fx+"\n  truth: "+gt);
    process.exit(1);
  }
  // the clean case must expect zero findings, or the benchmark rewards noise
  const clean=gt.find(n=>/clean|correct/.test(n));
  if (!clean) { console.error("no clean fixture — false positives go unmeasured"); process.exit(1); }
  const exp=JSON.parse(fs.readFileSync(b+"/ground-truth/"+clean+".json","utf8"));
  if ((exp.required_findings||[]).length!==0) { console.error("clean fixture expects findings"); process.exit(1); }
' "$TG" 2>"$TMP/berr"; then
  ok "fixtures paired, clean case guards false positives"
else
  bad "benchmark set is malformed: $(cat "$TMP/berr")"
fi

bash "$TG/benchmarks/run.sh" --dry-run >/dev/null 2>&1 \
  && ok "dry-run pipeline validates without API calls" || bad "dry-run failed"
[ -f "$TG/benchmarks/baselines/tester.json" ] \
  && ok "baseline committed" || bad "no baseline to regress against"

# the scorer must actually discriminate, or the harness is decoration
SC="$TMP/score"; mkdir -p "$SC"
printf 'verdict: FAIL\n\nBUG-1: at 10 units the discount is skipped\n' > "$SC/good.md"
printf 'verdict: PASS\n\nlooks fine\n' > "$SC/blind.md"
printf 'verdict: FAIL\n\nBUG-1: slugify is broken\n' > "$SC/noisy.md"
bash "$TG/benchmarks/run.sh" --score off-by-one "$SC/good.md"  >/dev/null 2>&1 \
  && ok "scorer passes a report that found the seeded bug" || bad "scorer failed a correct report"
bash "$TG/benchmarks/run.sh" --score off-by-one "$SC/blind.md" >/dev/null 2>&1 \
  && bad "scorer passed a report that missed the bug" || ok "scorer fails a report that missed it"
bash "$TG/benchmarks/run.sh" --score clean "$SC/noisy.md" >/dev/null 2>&1 \
  && bad "scorer passed a false positive on the clean fixture" || ok "scorer fails invented findings"
rm -f "$TG"/benchmarks/baselines/.last-*.json

# an unmeasured baseline must say so — null is not zero
node -e '
  const b=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
  const scored=Object.values(b.scores||{}).filter(Boolean).length;
  if (b.measured === false && scored === 0) process.exit(0);
  if (b.measured === true && scored > 0) process.exit(0);
  console.error("baseline claims measured=" + b.measured + " with " + scored + " scores");
  process.exit(1);
' "$TG/benchmarks/baselines/tester.json" \
  && ok "baseline does not pass off unmeasured nulls as results" \
  || bad "baseline's measured flag disagrees with its scores"

# ── 21. prompt files may not grow without something being deleted ────────────
# The ratchet, not the split. router.md IS the largest file and every evaluation
# appends to it, but splitting it costs a second file read on the FULL path — a
# tool call, in a system whose budget is denominated in tool calls — to save
# context, which nothing here measures. A ceiling makes the growth a failing
# check instead of invisible drift, and costs nothing. Raise it deliberately, in
# a commit that says why; do not raise it to make a red check green.
head2 "21. prompt files may not grow without something being deleted"
CAP_ORCH=560
CAP_LEAF=230
for f in "$TG"/agents/*.md; do
  a=$(basename "$f" .md); L=$(wc -l < "$f" | tr -d ' ')
  if [ "$a" = router ]; then CAP=$CAP_ORCH; else CAP=$CAP_LEAF; fi
  [ "$L" -le "$CAP" ] && ok "$a.md $L/$CAP lines" \
    || bad "$a.md is $L lines, over its $CAP cap — delete before you add"
done

# ── 22. subagent-gate.sh: inert, blocking, loop-trapped ──────────────────────
# The hook item D auto-wires on install. Its three invariants were prose-only
# until now: no marker → zero effect on any other workflow; marker + red gate →
# block with the reason; stop_hook_active → never block twice (the loop trap).
head2 "22. subagent-gate.sh: inert without marker, blocks on red gate, loop-trapped"
SGATE="$TG/hooks/subagent-gate.sh"
rm -f .tg-active

# (a) no .tg-active → exit 0, silent
OUT=$(echo '{}' | bash "$SGATE" 2>&1); RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] \
  && ok "inert with no .tg-active (exit 0, no output)" \
  || bad "fired outside a run (rc=$RC, out: $OUT)"

# (b) marker + failing unit test → exit 2, stderr carries the gate reason
touch .tg-active
cp src/cart.test.ts src/cart.test.ts.bak
printf "\nimport { it as it_, expect as expect_ } from 'vitest'\nit_('deliberately failing check', () => { expect_(1).toBe(2) })\n" >> src/cart.test.ts
OUT=$(echo '{}' | bash "$SGATE" 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok "red gate under marker → exit 2" || bad "expected exit 2, got $RC"
grep -q 'GATE FAIL' <<< "$OUT" \
  && ok "block message carries GATE FAIL reason" || bad "no GATE FAIL in block output"

# (c) same red gate + stop_hook_active → exit 0. Blocking again traps the
# subagent in a loop; the trap needs jq to read the payload.
if command -v jq >/dev/null 2>&1; then
  OUT=$(echo '{"stop_hook_active":true}' | bash "$SGATE" 2>&1); RC=$?
  [ "$RC" -eq 0 ] && ok "stop_hook_active honoured (exit 0, no re-block)" \
                  || bad "re-blocked an already-blocked subagent (rc=$RC)"
else
  ok "stop_hook_active check skipped (no jq on this machine)"
fi
mv src/cart.test.ts.bak src/cart.test.ts
rm -f .tg-active

# ── 23. plugin manifest wires exactly the two documented hooks ───────────────
# The plugin exists to replace the manual settings.json edit, not to widen it:
# exactly two events, each pointing at a script that exists and that the README
# install section names. A third event or a relocated script is drift.
head2 "23. plugin manifest: two events, real scripts, same ones README names"
if node -e '
  const fs = require("fs"), path = require("path");
  const TG = process.argv[1];
  const fail = m => { console.error(m); process.exit(1); };

  const plugin = JSON.parse(fs.readFileSync(path.join(TG, ".claude-plugin/plugin.json"), "utf8"));
  if (plugin.name !== "team-irfan") fail("plugin.json name is " + plugin.name);
  if (!plugin.hooks) fail("plugin.json declares no hooks file");
  const hooksPath = path.join(TG, plugin.hooks);
  const cfg = JSON.parse(fs.readFileSync(hooksPath, "utf8")).hooks;

  const events = Object.keys(cfg).sort();
  if (events.join(",") !== "PostToolUse,SubagentStop")
    fail("expected exactly PostToolUse,SubagentStop — got " + events.join(","));

  const WANT = {
    PostToolUse:  "hooks/ledger.sh hook",
    SubagentStop: "hooks/subagent-gate.sh",
  };
  const readme = fs.readFileSync(path.join(TG, "README.md"), "utf8");
  for (const [event, tail] of Object.entries(WANT)) {
    const cmds = cfg[event].flatMap(m => m.hooks).map(h => h.command);
    if (cmds.length !== 1) fail(event + " registers " + cmds.length + " commands, expected 1");
    const cmd = cmds[0];
    if (!cmd.startsWith("bash ${CLAUDE_PLUGIN_ROOT}/"))
      fail(event + " command does not use ${CLAUDE_PLUGIN_ROOT}: " + cmd);
    if (!cmd.endsWith(tail)) fail(event + " command is not " + tail + ": " + cmd);
    const script = tail.split(" ")[0];
    if (!fs.existsSync(path.join(TG, script))) fail(tail + " points at a missing script");
    if (!readme.includes(script)) fail("README install section does not name " + script);
  }
' "$TG" 2>"$TMP/perr"; then
  ok "plugin.json → hooks.json: PostToolUse=ledger, SubagentStop=gate, nothing else"
else
  bad "plugin manifest invalid: $(cat "$TMP/perr")"
fi

# ── 24. doctor.sh: hermetic install-health verdicts ──────────────────────────
# Doctor reads the hook-registration file it is handed, never the machine's
# real config — that is what keeps this check deterministic on any machine.
# TG_DOCTOR_FAST=1 skips the run-checks step so the check cannot recurse.
head2 "24. doctor.sh: healthy install PASSes, broken install names the failure"

# (a) synthetic registration file carrying both hooks → every line PASS, exit 0
GOOD="$TMP/doctor-good.json"
printf '{"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"bash x/hooks/ledger.sh hook"}]}],"SubagentStop":[{"hooks":[{"type":"command","command":"bash x/hooks/subagent-gate.sh"}]}]}}\n' > "$GOOD"
OUT=$(TG_DOCTOR_FAST=1 bash "$TG/hooks/doctor.sh" "$GOOD" 2>&1); RC=$?
[ "$RC" -eq 0 ] && grep -q 'DOCTOR PASS' <<< "$OUT" && ! grep -q '^  FAIL' <<< "$OUT" \
  && ok "healthy install → all PASS, DOCTOR PASS, exit 0" \
  || bad "healthy install misdiagnosed (rc=$RC): $(grep '  FAIL' <<< "$OUT")"

# (b) same file with the PostToolUse/ledger entry removed → a FAIL line naming
# the ledger hook, non-zero exit
BADF="$TMP/doctor-bad.json"
printf '{"hooks":{"SubagentStop":[{"hooks":[{"type":"command","command":"bash x/hooks/subagent-gate.sh"}]}]}}\n' > "$BADF"
OUT=$(TG_DOCTOR_FAST=1 bash "$TG/hooks/doctor.sh" "$BADF" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok "unwired ledger → exit $RC (non-zero)" || bad "doctor passed a broken install"
grep -q 'FAIL  ledger hook' <<< "$OUT" \
  && ok "FAIL line names the ledger hook" || bad "failure does not name the ledger hook"
grep -q 'DOCTOR FAIL' <<< "$OUT" \
  && ok "verdict is DOCTOR FAIL" || bad "DOCTOR FAIL verdict missing"

# ── 25. plan-gate.sh: valid plan passes, every broken field named ────────────
head2 "25. plan-gate.sh: valid plan passes, every broken field fails by name"
PG="$TG/hooks/plan-gate.sh"
PRUN="$TMP/plan-run"; mkdir -p "$PRUN"

good_plan() {
  cat > "$PRUN/plan.json" <<'JSON'
{
  "goal": "block/unblock endpoint exists",
  "scope_folders": ["src/app/users"],
  "options": [
    { "id": "A", "approach": "extend service", "files": ["src/app/users/u.ts"], "risk": "low", "expected_calls": 30 },
    { "id": "B", "approach": "new module", "files": ["src/app/block/b.ts"], "risk": "medium", "expected_calls": 45 }
  ],
  "chosen_option_id": "A",
  "test_contract": { "type": "backend-e2e", "cases_source": "plan" },
  "run_cap": 39
}
JSON
}

good_plan
OUT=$(bash "$PG" "$PRUN" 2>&1); RC=$?
[ "$RC" -eq 0 ] && grep -q 'PLAN GATE PASS' <<< "$OUT" \
  && ok "valid plan → PLAN GATE PASS, exit 0" || bad "valid plan rejected (rc=$RC): $OUT"

# missing plan.json entirely
rm -f "$PRUN/plan.json"
OUT=$(bash "$PG" "$PRUN" 2>&1); RC=$?
[ "$RC" -eq 1 ] && grep -q 'plan.json missing' <<< "$OUT" \
  && ok "missing plan.json → named failure" || bad "missing file not caught"

# each required field, removed one at a time, must fail by name
for field in goal scope_folders options chosen_option_id test_contract run_cap; do
  good_plan
  node -e '
    const fs=require("fs"); const f=process.argv[1];
    const p=JSON.parse(fs.readFileSync(f,"utf8"));
    delete p[process.argv[2]];
    fs.writeFileSync(f, JSON.stringify(p));
  ' "$PRUN/plan.json" "$field"
  OUT=$(bash "$PG" "$PRUN" 2>&1); RC=$?
  [ "$RC" -eq 1 ] && grep -q "missing field: $field" <<< "$OUT" \
    && ok "missing $field → fails, named" || bad "missing $field not caught: $OUT"
done

# 4 options
good_plan
node -e '
  const fs=require("fs"); const f=process.argv[1];
  const p=JSON.parse(fs.readFileSync(f,"utf8"));
  p.options.push({id:"C",approach:"x",files:["a"],risk:"r",expected_calls:9},{id:"D",approach:"y",files:["b"],risk:"r",expected_calls:9});
  fs.writeFileSync(f, JSON.stringify(p));
' "$PRUN/plan.json"
OUT=$(bash "$PG" "$PRUN" 2>&1); RC=$?
[ "$RC" -eq 1 ] && grep -q 'options count 4' <<< "$OUT" \
  && ok "4 options → fails (allowed 1-3)" || bad "4 options accepted"

# chosen id not in options
good_plan
node -e 'const fs=require("fs");const f=process.argv[1];const p=JSON.parse(fs.readFileSync(f,"utf8"));p.chosen_option_id="Z";fs.writeFileSync(f,JSON.stringify(p))' "$PRUN/plan.json"
OUT=$(bash "$PG" "$PRUN" 2>&1); RC=$?
[ "$RC" -eq 1 ] && grep -q 'not in options' <<< "$OUT" \
  && ok "unknown chosen_option_id → fails" || bad "unknown chosen id accepted"

# expected_calls not a number
good_plan
node -e 'const fs=require("fs");const f=process.argv[1];const p=JSON.parse(fs.readFileSync(f,"utf8"));p.options[0].expected_calls="thirty";fs.writeFileSync(f,JSON.stringify(p))' "$PRUN/plan.json"
OUT=$(bash "$PG" "$PRUN" 2>&1); RC=$?
[ "$RC" -eq 1 ] && grep -q 'expected_calls is not a number' <<< "$OUT" \
  && ok "string expected_calls → fails" || bad "string expected_calls accepted"

# run_cap arithmetic wrong
good_plan
node -e 'const fs=require("fs");const f=process.argv[1];const p=JSON.parse(fs.readFileSync(f,"utf8"));p.run_cap=60;fs.writeFileSync(f,JSON.stringify(p))' "$PRUN/plan.json"
OUT=$(bash "$PG" "$PRUN" 2>&1); RC=$?
[ "$RC" -eq 1 ] && grep -q 'run_cap 60 != computed 39' <<< "$OUT" \
  && ok "wrong run_cap → fails with the computed value" || bad "wrong run_cap accepted"

# run_cap ceiling at 60
good_plan
node -e 'const fs=require("fs");const f=process.argv[1];const p=JSON.parse(fs.readFileSync(f,"utf8"));p.options[0].expected_calls=90;p.run_cap=60;fs.writeFileSync(f,JSON.stringify(p))' "$PRUN/plan.json"
OUT=$(bash "$PG" "$PRUN" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "cap ceiling: 90 calls → run_cap 60 accepted" || bad "ceiling case rejected: $OUT"

# empty scope_folders
good_plan
node -e 'const fs=require("fs");const f=process.argv[1];const p=JSON.parse(fs.readFileSync(f,"utf8"));p.scope_folders=[];fs.writeFileSync(f,JSON.stringify(p))' "$PRUN/plan.json"
OUT=$(bash "$PG" "$PRUN" 2>&1); RC=$?
[ "$RC" -eq 1 ] && grep -q 'scope_folders is empty' <<< "$OUT" \
  && ok "empty scope_folders → fails" || bad "empty scope_folders accepted"

grep -q 'plan-gate.sh' "$TG/agents/router.md" \
  && ok "orchestrator runs plan-gate before the approval question" \
  || bad "nothing ever runs plan-gate.sh"

# ── 26. ledger cap: plan.json run_cap wins, 60 is the fallback ───────────────
head2 "26. ledger cap: plan.json run_cap wins, 60 is the fallback"
CRUN="$TMP/cap-run"; mkdir -p "$CRUN"
CAP=$(bash "$TG/hooks/ledger.sh" cap "$CRUN")
[ "$CAP" = "60" ] && ok "no plan.json → cap 60" || bad "fallback cap was $CAP"
printf '{"run_cap": 39}\n' > "$CRUN/plan.json"
CAP=$(bash "$TG/hooks/ledger.sh" cap "$CRUN")
[ "$CAP" = "39" ] && ok "plan.json run_cap 39 → cap 39" || bad "cap was $CAP, expected 39"
printf '{"run_cap": "junk"}\n' > "$CRUN/plan.json"
CAP=$(bash "$TG/hooks/ledger.sh" cap "$CRUN")
[ "$CAP" = "60" ] && ok "junk run_cap → fallback 60, not garbage" || bad "junk cap accepted: $CAP"
grep -q 'ledger.sh cap' "$TG/agents/router.md" \
  && ok "orchestrator reads the cap from the hook" || bad "run_cap never read pre-spawn"

# ── 27. 3rd retry stops the run with a written BLOCKED verdict ───────────────
head2 "27. 3rd retry stops the run with a written BLOCKED verdict"
BRUN="$TMP/blocked-run"
bash "$GUARD" "$BRUN" T1 >/dev/null 2>&1
bash "$GUARD" "$BRUN" T1 >/dev/null 2>&1
OUT=$(bash "$GUARD" "$BRUN" T1 2>&1); RC=$?
[ "$RC" -eq 1 ] && grep -q 'verdict=BLOCKED' <<< "$OUT" \
  && ok "3rd attempt → ESCALATE with verdict=BLOCKED" || bad "no BLOCKED verdict in escalation"
grep -q 'BLOCKED task=T1' "$BRUN/blocked.log" 2>/dev/null \
  && ok "blocked.log records the task, hook-written" || bad "blocked.log missing or unnamed"
# the first two attempts must not have written it
BRUN2="$TMP/blocked-run2"
bash "$GUARD" "$BRUN2" T1 >/dev/null 2>&1
[ ! -f "$BRUN2/blocked.log" ] && ok "a plain retry writes no BLOCKED" || bad "retry 1 already wrote blocked.log"

# ── 28. gate.sh fails assertion-free test cases in test-cases.md ─────────────
head2 "28. gate.sh fails assertion-free test cases in test-cases.md"
cd "$FIXTURE" || exit 2
QRUN="$TMP/qa-run"; mkdir -p "$QRUN"
cat > "$QRUN/test-cases.md" <<'EOF2'
# Test cases

### CASE-1 — creates the thing
- source: plan goal
- command: curl -s -i http://127.0.0.1:3000/api/thing
- expect_status: 201
- expect_body: {"id":1}

### CASE-2 — status-only, asserts nothing
- source: plan goal
- command: curl -s -i http://127.0.0.1:3000/api/thing
- expect_status: 200
EOF2
OUT=$(TG_RUN="$QRUN" bash "$GATE" 2>&1); RC=$?
[ "$RC" -eq 1 ] && grep -q 'GATE FAIL: assertion-free test cases' <<< "$OUT" \
  && ok "status-only case → GATE FAIL, named" || bad "assertion-free case passed (rc=$RC)"
grep -q 'CASE-2' <<< "$OUT" && ok "the offending case is named" || bad "no case id in output"

printf -- '- expect_body: {"ok":true}\n' >> "$QRUN/test-cases.md"
OUT=$(TG_RUN="$QRUN" bash "$GATE" 2>&1); RC=$?
[ "$RC" -eq 0 ] && grep -q 'test-case scan ok' <<< "$OUT" \
  && ok "asserting cases pass the scan" || bad "honest cases rejected (rc=$RC)"

# expect(true)-style is caught even with a body line present
printf '### CASE-3 — trivial\n- source: plan goal\n- expect_body: expect(true)\n' >> "$QRUN/test-cases.md"
OUT=$(TG_RUN="$QRUN" bash "$GATE" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok "expect(true)-style case → GATE FAIL" || bad "expect(true) case passed"

# ── verdict ──────────────────────────────────────────────────────────────────
echo
echo "────────────────────────────────────────"
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && { echo "  CHECKS PASS"; exit 0; }
echo "  CHECKS FAIL"
exit 1
