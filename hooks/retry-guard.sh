#!/usr/bin/env bash
# team-graph retry counter. Zero LLM. Called by the Tester on every FAIL.
#
#   usage: retry-guard.sh <run-dir> <task-id>
#
#   exit 0  →  RETRY <n>/2  — send the failure report back to the SAME executor
#   exit 1  →  ESCALATE     — stop. Lead takes it, then Irfan.
#
# State lives in <run-dir>/retries.json, keyed by task id. The agent holds no
# counter of its own; kill it mid-run and the count survives.

set -uo pipefail

RUN_DIR="${1:-}"
TASK_ID="${2:-}"
LIMIT=2   # attempts 1 and 2 retry, the 3rd escalates

if [ -z "$RUN_DIR" ] || [ -z "$TASK_ID" ]; then
  echo "usage: retry-guard.sh <run-dir> <task-id>" >&2
  exit 2
fi

mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/retries.json"
[ -f "$STATE" ] || echo '{}' > "$STATE"

N=$(TG_TASK="$TASK_ID" node -e '
  const fs = require("fs");
  const file = process.argv[1];
  const id = process.env.TG_TASK;
  let state = {};
  try { state = JSON.parse(fs.readFileSync(file, "utf8")) || {}; } catch { state = {}; }
  state[id] = (state[id] || 0) + 1;
  const tmp = file + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2) + "\n");
  fs.renameSync(tmp, file);   // atomic replace, no half-written counter
  console.log(state[id]);
' "$STATE" 2>/dev/null)

if [ -z "$N" ]; then
  echo "retry-guard: could not update $STATE" >&2
  exit 2
fi

if [ "$N" -gt "$LIMIT" ]; then
  echo "ESCALATE task=$TASK_ID attempts=$N limit=$LIMIT"
  echo "refusing to continue — hand the failure to Lead, then to Irfan"
  exit 1
fi

echo "RETRY $N/$LIMIT task=$TASK_ID"
exit 0
