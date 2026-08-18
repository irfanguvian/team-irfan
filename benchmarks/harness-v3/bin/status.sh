#!/usr/bin/env bash
# What has run, what has not, and the exact command to finish it.
#
#   status.sh
#
# Reads runs/ only. Costs nothing, changes nothing. This is the first thing to
# run when picking the benchmark back up after a break.
set -uo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS="T1 T4 T2 T3"
ARMS="bare omc team"
missing_tasks=""

printf '%-6s %-8s %s\n' TASK ARM ROUNDS
printf '%-6s %-8s %s\n' ---- --- ------
for t in $TASKS; do
  for a in $ARMS; do
    line=""
    have=0
    for r in 1 2 3; do
      if [ -s "$H/runs/$t/$a/$r/result.json" ] && [ -f "$H/runs/$t/$a/$r/meta.json" ]; then
        line="$line $r:done"; have=$((have+1))
      else
        line="$line $r:--"
      fi
    done
    [ "$have" -lt 3 ] && missing_tasks="$missing_tasks $t"
    printf '%-6s %-8s %s\n' "$t" "$a" "$line"
  done
done

scored=$(( $(wc -l < "$H/runs/results.csv" 2>/dev/null || echo 1) - 1 ))
echo
echo "scored rows in runs/results.csv: $scored"

uniq_missing=$(echo "$missing_tasks" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ',' | sed 's/,$//')
if [ -z "$uniq_missing" ]; then
  echo "matrix complete. publish with: bin/publish.sh <label>"
else
  echo
  echo "to finish, in order:"
  echo "  bin/init.sh                      # refresh configs — OAuth tokens expire"
  echo "  bin/selftest.sh                  # confirm the scorer still grades correctly"
  echo "  bin/run.sh all --tasks $uniq_missing"
  echo "  bin/score.sh all && bin/publish.sh full"
  echo
  echo "note: run.sh rebuilds a worktree for every cell it runs, including cells"
  echo "      that already have results. To avoid re-spending on finished work,"
  echo "      run only the missing task/arm pairs:"
  for t in $TASKS; do
    for a in $ARMS; do
      n=0
      for r in 1 2 3; do [ -s "$H/runs/$t/$a/$r/result.json" ] && [ -f "$H/runs/$t/$a/$r/meta.json" ] && n=$((n+1)); done
      [ "$n" -lt 3 ] && echo "      bin/run.sh all --tasks $t --arms $a"
    done
  done
fi
