#!/usr/bin/env bash
# team-graph resume point. Zero LLM.
#
#   run-state.sh <run-dir> <node-just-finished> [next-node]
#
# Writes <run-dir>/run-state.json:
#
#   { "completed": ["pm","pjm"], "current": "exec-1" }
#
# "Kill any node mid-run and the next one picks up from disk" is the load-bearing
# claim of the stateless-agent design. Without this file, resume is an inference
# from which artifacts happen to exist — which cannot distinguish "exec-2 never
# started" from "exec-2 died before writing". A read beats a guess.
#
# The orchestrator is the only writer and it runs nodes in sequence, so a plain
# read-modify-write is safe here. The tool-call ledger, which concurrent
# executors do write, is append-only for exactly the opposite reason.

set -uo pipefail

RUN_DIR="${1:-}"; DONE="${2:-}"; NEXT="${3:-}"

[ -z "$RUN_DIR" ] || [ -z "$DONE" ] && {
  echo "usage: run-state.sh <run-dir> <node-just-finished> [next-node]" >&2; exit 2; }

mkdir -p "$RUN_DIR"

TG_DONE="$DONE" TG_NEXT="$NEXT" node -e '
  const fs = require("fs");
  const file = process.argv[1];
  let state = { completed: [], current: null };
  try { state = JSON.parse(fs.readFileSync(file, "utf8")) || state; } catch {}
  if (!Array.isArray(state.completed)) state.completed = [];
  const done = process.env.TG_DONE;
  if (!state.completed.includes(done)) state.completed.push(done);
  state.current = process.env.TG_NEXT || null;
  const tmp = file + "." + process.pid + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2) + "\n");
  fs.renameSync(tmp, file);
  console.log(`run-state: completed=${state.completed.length} current=${state.current ?? "-"}`);
' "$RUN_DIR/run-state.json"
