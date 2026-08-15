#!/usr/bin/env bash
# team-graph tool-call ledger. Zero LLM, zero self-report.
#
#   ledger.sh bump <run-dir> [node]   record one tool call
#   ledger.sh read <run-dir>          print the total, refresh ledger.json
#   ledger.sh hook                    PostToolUse mode — stdin is the hook payload
#
# Why this file exists: the tool-call total governs routing, budget enforcement
# and every evaluation aggregate, and it used to be maintained by the
# orchestrator — an LLM counting its own tool calls. A number the measured party
# types is not a measurement.
#
# Truth is the append-only journal <run-dir>/ledger.log, one node name per line.
# Short appends to an O_APPEND file are atomic, so concurrent executors cannot
# lose each other's writes and no lock is needed. ledger.json is derived from the
# journal on `read` and never edited in place — one derivation site, so a stale
# copy cannot disagree with the count.
#
# Hook mode is gated on .tg-active exactly like subagent-gate.sh: no marker, no
# effect. Outside a team-graph run this script does nothing at all. The marker's
# first line is the run directory; an empty marker (the pre-v2.2 `touch` form)
# leaves the hook inert rather than guessing a path.

set -uo pipefail

usage() {
  echo "usage: ledger.sh {bump <run-dir> [node] | read <run-dir> | hook}" >&2
  exit 2
}

MODE="${1:-}"
[ -n "$MODE" ] || usage
shift

# ------------------------------------------------------------------ bump

do_bump() {
  local run="${1:-}" node="${2:-unattributed}"
  [ -n "$run" ] || usage
  mkdir -p "$run" || return 1
  # one short token per line. A newline in a node name would forge extra calls.
  node=$(printf '%s' "$node" | tr -d '\n\r' | cut -c1-64)
  [ -n "$node" ] || node=unattributed
  printf '%s\n' "$node" >> "$run/ledger.log"
}

# ------------------------------------------------------------------ read

do_read() {
  local run="${1:-}"
  [ -n "$run" ] || usage
  local log="$run/ledger.log"
  if [ ! -f "$log" ]; then echo 0; return 0; fi
  TG_LOG="$log" TG_OUT="$run/ledger.json" node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.env.TG_LOG, "utf8")
      .split("\n").map(s => s.trim()).filter(Boolean);
    const per = {};
    for (const l of lines) per[l] = (per[l] || 0) + 1;
    const tmp = process.env.TG_OUT + "." + process.pid + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(per, null, 2) + "\n");
    fs.renameSync(tmp, process.env.TG_OUT);
    console.log(lines.length);
  ' 2>/dev/null || wc -l < "$log" | tr -d ' '
}

# ------------------------------------------------------------------ hook

# PostToolUse payloads carry no reliable agent identity. A correct total beats an
# attributed guess, so an unknown caller is recorded as "unattributed" rather
# than dropped.
node_from_payload() {
  local input="$1"
  if command -v jq >/dev/null 2>&1; then
    local n
    n=$(printf '%s' "$input" | jq -r '.agent_name // .subagent_type // empty' 2>/dev/null)
    [ -n "$n" ] && { printf '%s' "$n"; return; }
  fi
  printf 'unattributed'
}

do_hook() {
  local input run
  input=$(cat 2>/dev/null)          # drain stdin even when inert
  [ -f .tg-active ] || exit 0
  run=$(head -n1 .tg-active 2>/dev/null | tr -d '[:space:]')
  [ -n "$run" ] && [ -d "$run" ] || exit 0
  do_bump "$run" "$(node_from_payload "$input")"
  exit 0                             # never fail the tool call that triggered us
}

case "$MODE" in
  bump) do_bump "${1:-}" "${2:-}" ;;
  read) do_read "${1:-}" ;;
  hook) do_hook ;;
  *)    usage ;;
esac
