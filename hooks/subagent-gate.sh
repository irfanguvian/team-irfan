#!/usr/bin/env bash
# SubagentStop guard. Rigid, zero LLM, scoped to an active team-graph run.
#
#   no .tg-active marker in cwd  → exit 0, silent. Zero effect on OMC or any
#                                  other workflow. This is the isolation.
#   gate passes                  → exit 0
#   gate fails                   → exit 2 + reason on stderr; Claude Code feeds
#                                  it back and the subagent must fix it
#   already blocked once         → exit 0. stop_hook_active means we are only
#                                  here because we blocked; blocking again
#                                  traps the subagent in a loop.
#
# Lead creates .tg-active in the project root at the start of a FULL run and
# removes it after the merge. FAST runs do not create it — solo-executor runs
# gate.sh inline and pastes the output.

set -uo pipefail

INPUT=$(cat 2>/dev/null)

[ -f .tg-active ] || exit 0

if command -v jq >/dev/null 2>&1; then
  ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
  [ "$ACTIVE" = "true" ] && exit 0
fi

if OUT=$(bash /Users/dealdulutech02/.claude/team-graph/hooks/gate.sh 2>&1); then
  exit 0
fi

{
  echo "team-graph gate blocked this subagent — do not report done:"
  echo "$OUT"
} >&2
exit 2
