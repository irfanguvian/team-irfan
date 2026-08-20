#!/usr/bin/env bash
# What has run, what has not, and the exact command to finish it.
#
#   status.sh
#
# Reads runs/ only. Costs nothing, changes nothing. First thing to run when
# picking the benchmark back up after a break or a crash.
set -uo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS="Q1 F1 B1 N5 MEM-A MEM-B"
ARMS="bare omc team"

rounds_for() { case "$1" in N5|MEM-A|MEM-B) echo 2 ;; *) echo 3 ;; esac; }

incomplete=0
printf '%-7s %-6s %s\n' TASK ARM ROUNDS
printf '%-7s %-6s %s\n' ---- --- ------
for t in $TASKS; do
  for a in $ARMS; do
    line=""
    for r in $(seq 1 "$(rounds_for "$t")"); do
      if [ -s "$H/runs/$t/$a/$r/result.json" ] && [ -f "$H/runs/$t/$a/$r/meta.json" ]; then
        st=$(jq -r '.status' "$H/runs/$t/$a/$r/meta.json" 2>/dev/null)
        case "$st" in ok) line="$line $r:done" ;; *) line="$line $r:$st" ;; esac
      else
        line="$line $r:--"
        incomplete=1
      fi
    done
    printf '%-7s %-6s %s\n' "$t" "$a" "$line"
  done
done

[ -d "$H/runs/.lock" ] && echo && echo "NOTE: runs/.lock present — a run is active (or crashed; rmdir it if no run lives)"

scored=$(( $(wc -l < "$H/results/results.csv" 2>/dev/null || echo 1) - 1 ))
judged=$(ls "$H/results/judgments" 2>/dev/null | wc -l | tr -d ' ')
echo
echo "scored rows: $scored   judgments: $judged"
echo
if [ "$incomplete" = 0 ]; then
  echo "matrix complete. next:"
  echo "  bin/score.sh all"
  echo "  bin/judge.sh --calibrate && bin/judge.sh all"
  echo "  bin/report.py"
else
  echo "to finish (run.sh all skips finished cells — it IS the resume path):"
  echo "  bin/init.sh --configs            # refresh OAuth copies if stale"
  echo "  bin/run.sh all"
  echo "  bin/score.sh all && bin/judge.sh --calibrate && bin/judge.sh all && bin/report.py"
fi
