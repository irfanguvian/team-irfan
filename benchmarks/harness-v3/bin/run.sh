#!/usr/bin/env bash
# Runs agents. This is the only script that costs money.
#
#   run.sh T1 bare 1              one cell of the matrix
#   run.sh all                    every task, fastest first, arms sequential,
#                                 the 3 rounds of an arm in parallel
#   run.sh all --tasks T1,T3      the minimum viable subset from the spec
#   run.sh all --dry-run          print the exact commands, spawn nothing
#
# Mode B (headless) only. The plan gate for arm C is auto-approved, so what is
# measured is the harness WITHOUT its human check — say so in the report.
#
# Fairness: the prompt text is read from tasks/<T>/PROMPT.md and passed byte for
# byte to all three arms. Only the config dir and the /team-irfan prefix differ.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_ROOT="${BENCH_ROOT:-$HOME/team-irfan-bench}"
WT_ROOT="${WT_ROOT:-$HOME/team-irfan-bench-wt}"
MAX_SEC="${MAX_SEC:-2700}"      # 45 min hard stop, per the intervention policy
MAX_TURNS="${MAX_TURNS:-150}"
DRY=0

# Fastest expected first: a one-liner, then a localised fix, then a feature,
# then the open-ended one.
TASKS="T1,T4,T2,T3"
ARMS="bare,omc,team"
ROUNDS=3

die() { echo "run.sh: $*" >&2; exit 1; }

setup_worktree() {
  local task=$1 arm=$2 round=$3 wt=$4
  rm -rf "$wt"
  git -C "$BENCH_ROOT" worktree prune
  git -C "$BENCH_ROOT" worktree add -q --detach "$wt" "$(echo "$task" | tr "A-Z" "a-z")-base"
  # APFS clone: a per-worktree node_modules for the price of a pointer, so one
  # run installing a dependency cannot leak into another.
  cp -Rc "$BENCH_ROOT/node_modules" "$wt/node_modules" 2>/dev/null \
    || cp -R "$BENCH_ROOT/node_modules" "$wt/node_modules"
  sed "s|DB_FILE|bench-$arm-$round.db|" "$wt/.env.example" > "$wt/.env"
  ( cd "$wt" && DATABASE_URL="file:./bench-$arm-$round.db" \
      npx prisma db push --force-reset --skip-generate >/dev/null 2>&1 )
}

run_cell() {
  local task=$1 arm=$2 round=$3
  local wt="$WT_ROOT/$task-$arm-$round"
  local out="$H/runs/$task/$arm/$round"
  local prompt; prompt="$(cat "$H/tasks/$task/PROMPT.md")"
  local -a flags=(-p --output-format json --permission-mode bypassPermissions --max-turns "$MAX_TURNS")

  case "$arm" in
    bare) flags+=(--strict-mcp-config --mcp-config '{"mcpServers":{}}') ;;
    team) prompt="/team-irfan $prompt" ;;
  esac

  if [ "$DRY" = 1 ]; then
    echo "[$task/$arm/$round] CLAUDE_CONFIG_DIR=$H/configs/$arm claude ${flags[*]} <prompt>"
    return 0
  fi

  mkdir -p "$out" "$WT_ROOT"
  setup_worktree "$task" "$arm" "$round" "$wt"
  echo "$wt" > "$out/worktree.path"

  local start end status=ok
  start=$(date +%s)
  (
    cd "$wt"
    CLAUDE_CONFIG_DIR="$H/configs/$arm" \
    TEAM_IRFAN_AUTO_APPROVE=1 \
    DATABASE_URL="file:./bench-$arm-$round.db" \
    API_KEY=bench-key \
      claude "${flags[@]}" "$prompt"
  ) > "$out/result.json" 2> "$out/stderr.log" &
  local pid=$!
  ( sleep "$MAX_SEC"; kill -TERM "$pid" 2>/dev/null ) & local killer=$!
  wait "$pid"; local rc=$?
  kill "$killer" 2>/dev/null
  end=$(date +%s)
  [ "$rc" -ne 0 ] && status="fail(rc=$rc)"
  [ $((end - start)) -ge "$MAX_SEC" ] && status="fail(timeout)"

  jq -n --arg t "$task" --arg a "$arm" --arg r "$round" --arg s "$status" \
        --argjson w $((end - start)) --arg wt "$wt" \
    '{task:$t,arm:$a,round:$r,status:$s,wall_sec:$w,worktree:$wt}' > "$out/meta.json"
  echo "[$task/$arm/$round] $status  $((end - start))s"
}

# ------------------------------------------------------------------- arg parse
if [ $# -ge 3 ] && [ "$1" != "all" ]; then
  run_cell "$1" "$2" "$3"; exit $?
fi
[ "${1:-}" = "all" ] || { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --tasks) TASKS="$2"; shift 2 ;;
    --arms) ARMS="$2"; shift 2 ;;
    --rounds) ROUNDS="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) die "unknown flag $1" ;;
  esac
done

[ -d "$BENCH_ROOT/.git" ] || die "no fixture repo — run bin/init.sh first"

for task in ${TASKS//,/ }; do
  for arm in ${ARMS//,/ }; do
    echo "=== $task / $arm — $ROUNDS rounds in parallel ==="
    pids=()
    for r in $(seq 1 "$ROUNDS"); do run_cell "$task" "$arm" "$r" & pids+=($!); done
    wait "${pids[@]}"
  done
done
echo "done. score with: bin/score.sh all"
