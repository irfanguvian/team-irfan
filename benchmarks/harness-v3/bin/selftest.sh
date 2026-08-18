#!/usr/bin/env bash
# Proves the scorer works before any money is spent on agents.
#
#   selftest.sh
#
# Stands in canned patches for the agent — a correct fix per task, plus the two
# band-aids the traps exist to catch — and asserts the scorer grades each one the
# way the spec says it should. If this fails, the benchmark is measuring nothing
# and no run is worth starting.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_ROOT="${BENCH_ROOT:-$HOME/team-irfan-bench}"
WT_ROOT="${WT_ROOT:-$HOME/team-irfan-bench-wt}"
fails=0

# task | fake-arm label | patch | expected pass_rate
CASES="
T1|good|T1-good.py|1
T2|good|T2-good.py|1
T3|good|T3-good.py|1
T3|contractbreak|T3-contractbreak.py|0
T4|good|T4-good.py|1
T4|bandaid|T4-bandaid.py|0
"

for case in $CASES; do
  IFS='|' read -r task arm patch want <<< "$case"
  wt="$WT_ROOT/$task-$arm-selftest"
  out="$H/runs/$task/$arm/selftest"
  mkdir -p "$out" "$WT_ROOT"

  rm -rf "$wt"
  git -C "$BENCH_ROOT" worktree prune
  git -C "$BENCH_ROOT" worktree add -q --detach "$wt" "$(echo "$task" | tr 'A-Z' 'a-z')-base"
  cp -Rc "$BENCH_ROOT/node_modules" "$wt/node_modules" 2>/dev/null \
    || cp -R "$BENCH_ROOT/node_modules" "$wt/node_modules"
  sed "s|DB_FILE|bench-$arm.db|" "$wt/.env.example" > "$wt/.env"
  ( cd "$wt" && DATABASE_URL="file:./bench-$arm.db" \
      npx prisma db push --force-reset --skip-generate >/dev/null 2>&1 )

  python3 "$H/selftest/$patch" "$wt"

  echo "$wt" > "$out/worktree.path"
  printf '{"session_id":"selftest","total_cost_usd":0,"num_turns":0,"duration_ms":0}\n' > "$out/result.json"
  printf '{"task":"%s","arm":"%s","round":"selftest","status":"selftest","wall_sec":0}\n' \
    "$task" "$arm" > "$out/meta.json"

  "$H/bin/score.sh" "$task" "$arm" selftest >/dev/null 2>&1
  got=$(tail -1 "$H/runs/results.csv" | awk -F'","' '{print $4}')
  if [ "$(awk -v g="$got" -v w="$want" 'BEGIN{print (g==w)?1:0}')" = 1 ]; then
    echo "ok   $task/$patch -> pass_rate $got"
  else
    echo "FAIL $task/$patch -> pass_rate $got, wanted $want"
    fails=$((fails+1))
  fi
done

echo
[ "$fails" = 0 ] && echo "selftest passed" || echo "selftest failed: $fails case(s)"
exit "$fails"
