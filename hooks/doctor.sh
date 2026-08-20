#!/usr/bin/env bash
# team-graph install doctor. Zero LLM, on-demand, read-only outside $TMPDIR.
# Verifies install health and prints PASS/FAIL per item. Any FAIL → exit 1.
#
#   usage: doctor.sh [hook-registration-json]
#
# The argument is whichever JSON file registers the two hooks on this machine:
# ~/.claude/settings.json for a manual install (the default), or this repo's
# hooks/hooks.json for a plugin install. Both carry the same two command
# strings, so one grep serves both. Hermetic on purpose — the harness feeds it
# synthetic files instead of the machine's real config.
#
#   TG_DOCTOR_FAST=1   skip the full run-checks suite. The harness sets it so
#                      the doctor check cannot recurse into run-checks, and it
#                      keeps a quick health poke under a second.
#
# Scope is install health only: hook registration, fixture deps, live wiring
# probes. Behaviour of the gate, ledger, graph and prompts is run-checks' job —
# doctor invokes it, never re-implements it.

set -uo pipefail

TG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="${1:-$HOME/.claude/settings.json}"
FAILED=0

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILED=1; }

echo "team-graph doctor · $TG"
echo

# 1+2 — hook registration in the named file
if [ -f "$SETTINGS" ]; then
  grep -q 'ledger\.sh hook' "$SETTINGS" \
    && pass "ledger hook registered in $SETTINGS" \
    || fail "ledger hook (hooks/ledger.sh hook) not registered in $SETTINGS"
  grep -q 'subagent-gate\.sh' "$SETTINGS" \
    && pass "subagent gate registered in $SETTINGS" \
    || fail "subagent gate (hooks/subagent-gate.sh) not registered in $SETTINGS"
else
  fail "hook registration file not found: $SETTINGS"
fi

# 2b — memory hook registered (v3): SubagentStop/Stop ingest via memory.sh
if [ -f "$SETTINGS" ]; then
  grep -q 'memory\.sh hook' "$SETTINGS" \
    && pass "memory hook registered in $SETTINGS" \
    || fail "memory hook (hooks/memory.sh hook ...) not registered in $SETTINGS"
fi

# 3 — fixture deps, without which run-checks refuses to run
[ -d "$TG/tests/fixture/node_modules" ] \
  && pass "fixture deps installed" \
  || fail "fixture deps missing — run: (cd $TG/tests/fixture && npm install)"

# 4 — ledger wiring probe: one fake PostToolUse payload through the real hook
# path must land exactly one line in ledger.log
PROBE=$(mktemp -d "${TMPDIR:-/tmp}/tg-doctor.XXXXXX")
trap 'rm -rf "$PROBE"' EXIT
mkdir -p "$PROBE/run"
( cd "$PROBE" \
  && printf '%s\n' "$PROBE/run" > .tg-active \
  && echo '{"tool_name":"Bash"}' | bash "$TG/hooks/ledger.sh" hook )
LINES=$(wc -l < "$PROBE/run/ledger.log" 2>/dev/null | tr -d ' ')
[ "${LINES:-0}" = "1" ] \
  && pass "ledger wiring probe (1 payload → 1 ledger.log line)" \
  || fail "ledger probe wrote ${LINES:-0} lines, expected 1"

# 4b — memory wiring probe: one fact in, one hit back, one log line, in a
# throwaway dir. Deterministic; no LLM, no project state touched.
MPROBE="$PROBE/mem"
mkdir -p "$MPROBE"
printf 'gotcha|probe|init|doctor probe fact about the widget frobnicator\n' > "$MPROBE/seed.txt"
( cd "$MPROBE" && bash "$TG/hooks/memory.sh" ingest --agent product --artifact seed.txt --infer false >/dev/null 2>&1 )
MOUT=$( cd "$MPROBE" && bash "$TG/hooks/memory.sh" retrieve --agent product --query "widget frobnicator" 2>/dev/null )
grep -q 'doctor probe fact' <<< "$MOUT" \
  && pass "memory probe (ingest → retrieve round-trip)" \
  || fail "memory probe failed — memory.sh ingest/retrieve broken"
grep -qE ' ingest product ok ' "$MPROBE/.team-irfan/memory/memory.log" 2>/dev/null \
  && pass "memory.log records the probe ingest" \
  || fail "memory.log missing or unparseable after probe"

# 5 — both hooks inert without the marker: the isolation every other workflow
# on this machine depends on
rm -f "$PROBE/.tg-active"
( cd "$PROBE" && echo '{}' | bash "$TG/hooks/subagent-gate.sh" >/dev/null 2>&1 )
RC=$?
[ "$RC" -eq 0 ] \
  && pass "subagent-gate inert without .tg-active" \
  || fail "subagent-gate fired without a marker (rc=$RC)"

# 6 — the deterministic suite itself
if [ "${TG_DOCTOR_FAST:-}" = "1" ]; then
  echo "  SKIP  run-checks (TG_DOCTOR_FAST=1)"
else
  OUT=$(bash "$TG/tests/run-checks.sh" 2>&1 | tail -3)
  if grep -q 'CHECKS PASS' <<< "$OUT"; then
    pass "run-checks: $(grep -oE '[0-9]+ passed, [0-9]+ failed' <<< "$OUT" | head -1)"
  else
    fail "run-checks failing — run: bash $TG/tests/run-checks.sh"
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then echo "DOCTOR PASS"; exit 0; fi
echo "DOCTOR FAIL"
exit 1
