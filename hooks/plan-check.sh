#!/usr/bin/env bash
# team-graph phase check. Deterministic, zero LLM. Validates the PHASES block
# in <run-dir>/plan.md BEFORE the approval gate is shown.
#
#   usage: plan-check.sh <run-dir>
#
#   exit 0  →  PLAN OK: n phases, max projection X/CAP
#   exit 1  →  PLAN CHECK FAIL: <named reason>  (plan bounced to Product)
#
# Every plan is written against the cap, or split until it is. Each projection
# is RECOMPUTED here from the task count — the model's arithmetic is not a
# measurement, same principle as the ledger. plan-check is design-time; the
# pre-spawn ledger check (ledger.sh cap/read) stays as the runtime backstop.

set -uo pipefail

RUN_DIR="${1:-}"
[ -n "$RUN_DIR" ] || { echo "usage: plan-check.sh <run-dir>" >&2; exit 2; }

PLAN="$RUN_DIR/plan.md"
[ -f "$PLAN" ] || { echo "PLAN CHECK FAIL: plan.md missing at $PLAN"; exit 1; }

# The projection formula is fixed: 26 + 27*tasks (orchestrator overhead + the
# per-task executor/QA/merge chain). A plan declaring a different one fails —
# the formula is the contract, not a suggestion.
awk '
  function fail(msg) { printf "PLAN CHECK FAIL: %s\n", msg; bad = 1; exit 1 }

  /^## PHASES$/      { inblock = 1; next }
  inblock && /^## /  { inblock = 0 }
  !inblock           { next }

  /^budget_cap:/ {
    if ($2 !~ /^[0-9]+$/) fail("budget_cap is not a number: " $2)
    cap = $2 + 0; next
  }
  /^projection_formula:/ {
    line = $0
    sub(/^projection_formula:[ \t]*/, "", line)
    gsub(/[ \t]/, "", line)
    if (line != "26+27*tasks") fail("projection_formula must be 26 + 27*tasks, got: " line)
    formula = 1; next
  }
  /^phase [0-9]+:/ {
    n++
    if (match($0, /tasks:[ \t]*\[[^]]*\]/) == 0) fail("phase " n " has no tasks: [...] list")
    tl = substr($0, RSTART, RLENGTH)
    sub(/^tasks:[ \t]*\[/, "", tl); sub(/\]$/, "", tl)
    gsub(/[ \t]/, "", tl)
    tasks = (tl == "") ? 0 : split(tl, dummy, ",")
    if (match($0, /projected:[ \t]*[0-9]+/) == 0) fail("phase " n " has no projected: number")
    pj = substr($0, RSTART, RLENGTH); sub(/^projected:[ \t]*/, "", pj); pj += 0
    want = 26 + 27 * tasks
    if (pj != want)
      fail("phase " n " projected " pj " != recomputed " want " (26 + 27*" tasks ")")
    if (match($0, /fits:[ \t]*(yes|no)/) == 0) fail("phase " n " has no fits: yes|no")
    ft = substr($0, RSTART, RLENGTH); sub(/^fits:[ \t]*/, "", ft)
    over[n] = pj; fits[n] = ft
    if (pj > max) max = pj
    next
  }

  END {
    if (bad) exit 1
    if (cap == 0 && formula == 0 && n == 0) fail("PHASES block missing")
    if (cap == 0)     fail("budget_cap missing from PHASES block")
    if (formula == 0) fail("projection_formula missing from PHASES block")
    if (n == 0)       fail("PHASES block lists no phases")
    for (i = 1; i <= n; i++) {
      if (over[i] > cap) fail("phase " i " projected " over[i] " over cap " cap " — split it")
      if (fits[i] != "yes") fail("phase " i " says fits: " fits[i] " — a phase that does not fit is not plannable")
    }
    printf "PLAN OK: %d phase%s, max projection %d/%d\n", n, (n == 1 ? "" : "s"), max, cap
  }
' "$PLAN"
