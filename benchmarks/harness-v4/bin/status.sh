#!/usr/bin/env bash
# What has run, what has not, and the exact command to finish it.
#
#   status.sh [tier]     tier defaults to BENCH_TIER (see lib.sh)
#
# Reads runs/<tier>/ and results/<tier>/ only. Costs nothing, changes nothing.
# First thing to run when picking the benchmark back up after a break or a crash.
set -uo pipefail

[ -n "${1:-}" ] && export BENCH_TIER="$1"
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$H/bin/lib.sh"

echo "tier $TIER   ·   $MODEL / effort $EFFORT"
echo "runs: $RUNS"
echo "results: $RES"
echo

incomplete=0
printf '%-7s %-6s %s\n' TASK ARM ROUNDS
printf '%-7s %-6s %s\n' ---- --- ------
for t in $TASKS_ALL; do
  for a in $ARMS_ALL; do
    line=""
    for r in $(seq 1 "$(rounds_for "$t")"); do
      c=$(cell_dir "$t" "$a" "$r")
      st=$(jq -r '.status // ""' "$c/meta.json" 2>/dev/null)
      case "$st" in
        ok)         line="$line $r:done" ;;
        INFRA_FAIL) line="$line $r:INFRA" ;;
        "")         line="$line $r:--"; incomplete=1 ;;
        *)          line="$line $r:$st" ;;
      esac
      # A cell with a meta but no result is only finished if it is an infra cell.
      [ -n "$st" ] && [ "$st" != INFRA_FAIL ] && [ ! -s "$c/result.json" ] && incomplete=1
    done
    printf '%-7s %-6s %s\n' "$t" "$a" "$line"
  done
done

if [ -s "$RES/ledger.jsonl" ]; then
  echo
  jq -r 'select(.status=="INFRA_FAIL")
         | "INFRA  \(.task)/\(.arm)/\(.round)  \(.reason // "?")"' \
    "$RES/ledger.jsonl" 2>/dev/null | sort -u
fi

for f in "$RUNS"/.lock-*; do
  [ -d "$f" ] || continue
  echo
  echo "NOTE: $f present — a lane is active (or crashed; rmdir it if no run lives)"
done

scored=$(( $(cat "$RES/results.csv" 2>/dev/null | wc -l) - 1 ))
[ "$scored" -lt 0 ] && scored=0
judged=$(ls "$RES/judgments" 2>/dev/null | wc -l | tr -d ' ')
echo
echo "scored rows: $scored   judgments: $judged"
[ -f "$RES/PROGRESS.md" ] && echo "live progress: $RES/PROGRESS.md"
[ -f "$RES/DONE" ]    && echo "DONE: report at $(cat "$RES/DONE")"
[ -f "$RES/ABORTED" ] && echo "ABORTED: $(cat "$RES/ABORTED")"
echo
if [ "$incomplete" = 0 ] && [ -n "$(ls "$RUNS" 2>/dev/null)" ]; then
  echo "matrix complete. next:"
  echo "  bin/score.sh all && bin/judge.sh all && bin/same-hole.sh all && bin/report.py --tier $TIER"
else
  echo "to finish (--matrix skips finished cells and recorded INFRA cells — it IS the resume path):"
  echo "  bin/init.sh --configs            # refresh OAuth copies if stale"
  echo "  BENCH_TIER=$TIER bin/run.sh --matrix"
fi
