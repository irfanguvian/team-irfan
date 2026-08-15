#!/usr/bin/env bash
# team-graph verification harness. Deterministic, zero agents.
# Every check must pass. Any failure exits non-zero.
#
#   bash ~/.claude/team-graph/tests/run-checks.sh

set -uo pipefail

TG=/Users/dealdulutech02/.claude/team-graph
FIXTURE="$TG/tests/fixture"
GATE="$TG/hooks/gate.sh"
GUARD="$TG/hooks/retry-guard.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/tg-checks.XXXXXX")

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
head2() { echo; echo "── $1"; }

cleanup() {
  rm -f "$FIXTURE/src/stub.test.ts" "$FIXTURE/src/typeerror.ts"
  git -C "$FIXTURE" checkout -- src 2>/dev/null
  [ -f "$FIXTURE/src/cart.test.ts.bak" ] && mv "$FIXTURE/src/cart.test.ts.bak" "$FIXTURE/src/cart.test.ts"
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
check_fields brief.md          '## Problem' '## Business logic' '## Open questions for Irfan' '## Acceptance' '## Out of scope'
check_fields task-spec.md      '## Goal' '## Files in scope' '## Acceptance criteria' '## Out of scope'
check_fields change-summary.md '## What changed' '## Files' '## How to verify' '## Gate output'
check_fields test-report.md    'verdict:' '## Cases' '## Evidence' '## Bugs found' '## Not covered'
check_fields report.md         '**Done:**' '**Fine or not:**' '**Blockers:**' '**Next:**' '**Verdict:**'
check_fields lessons.md        '## Candidate rules'

# ── 4b. every agent contract declares its budget and forbidden list ──────────
head2 "4b. agent contracts declare budget + forbidden actions"
for a in router solo-executor pm pjm lead executor tester retro; do
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

# ── verdict ──────────────────────────────────────────────────────────────────
echo
echo "────────────────────────────────────────"
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && { echo "  CHECKS PASS"; exit 0; }
echo "  CHECKS FAIL"
exit 1
