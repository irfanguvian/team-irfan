#!/usr/bin/env bash
# Runs agents. The only script besides judge.sh that costs money.
#
#   run.sh <task> <arm> <round>   one cell (task: Q1 F1 B1 N5 MEM-A MEM-B)
#   run.sh all                    every remaining cell, STRICTLY SEQUENTIALLY,
#                                 fastest tasks first; skips cells that already
#                                 have a result, so it doubles as resume
#   run.sh all --tasks Q1,F1 --arms team --dry-run
#
# Mode B headless. The plan gate for arm C is auto-approved, so what is measured
# is team-irfan WITHOUT its human check — say so in every report.
#
# Sequential only. v3's parallel rounds are the thing that kept failing. A
# lockfile (runs/.lock) makes a second concurrent invocation refuse to start.
# Every cell writes result.json atomically before the next cell starts, so a
# crash loses at most one cell.
#
# MEM cells are the one exception to fresh-worktree-per-cell: MEM-A creates one
# persistent clone per (arm, round); MEM-B runs in the SAME clone as a separate
# process minutes later — the second session finding the first session's state
# (.team-irfan/ for arm C) is the capability under test. run.sh commits the
# working tree after each MEM session so score.sh can diff per session without
# touching the clone.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_ROOT="${BENCH_ROOT:-$HOME/team-irfan-bench-v4}"
WT_ROOT="${WT_ROOT:-$HOME/team-irfan-bench-v4-wt}"
MAX_SEC="${MAX_SEC:-2700}"
MAX_TURNS="${MAX_TURNS:-150}"
# Pinned explicitly: arm A's empty settings.json would otherwise take the CLI
# default while B and C inherit the operator's model. Same model everywhere.
MODEL="${BENCH_MODEL:-claude-opus-5}"
DRY=0

# Fastest first, so a crash early costs little. 3 rounds for the short tasks,
# 2 for the long ones (N5 and the MEM pair). MEM-A must precede MEM-B.
TASKS="Q1,F1,B1,N5,MEM-A,MEM-B"
ARMS="bare,omc,team"

die() { echo "run.sh: $*" >&2; exit 1; }

rounds_for() { case "$1" in N5|MEM-A|MEM-B) echo 2 ;; *) echo 3 ;; esac; }

base_tag() {
  case "$1" in
    Q1) echo q1-base ;; F1) echo f1-base ;; N5) echo n5-base ;;
    B1) echo b1-base ;; MEM-A|MEM-B) echo mem-base ;;
    *) die "unknown task $1" ;;
  esac
}

install_deps() {  # $1 = target dir
  cp -Rc "$BENCH_ROOT/node_modules" "$1/node_modules" 2>/dev/null \
    || cp -R "$BENCH_ROOT/node_modules" "$1/node_modules"
}

setup_db() {  # $1 = dir, $2 = db name
  sed "s|DB_FILE|$2|" "$1/.env.example" > "$1/.env"
  ( cd "$1" && DATABASE_URL="file:./$2" \
      npx prisma db push --force-reset --skip-generate >/dev/null 2>&1 )
}

setup_worktree() {  # standard cells: throwaway worktree per cell
  local task=$1 arm=$2 round=$3 wt=$4
  rm -rf "$wt"
  git -C "$BENCH_ROOT" worktree prune
  git -C "$BENCH_ROOT" worktree add -q --detach "$wt" "$(base_tag "$task")"
  install_deps "$wt"
  setup_db "$wt" "bench-$arm-$round.db"
}

setup_mem_clone() {  # MEM pair: standalone single-commit repo, persists A -> B
  local clone=$1
  rm -rf "$clone"
  mkdir -p "$clone"
  git -C "$BENCH_ROOT" archive mem-base | tar -x -C "$clone"
  ( cd "$clone" && git init -q -b main && git add -A \
      && git -c user.name=bench -c user.email=bench@local commit -qm "chore: app" )
  install_deps "$clone"
  setup_db "$clone" "bench-mem.db"
}

commit_session() {  # snapshot a MEM session's result inside the clone
  local clone=$1 label=$2
  git -C "$clone" add -A
  git -C "$clone" -c user.name=bench -c user.email=bench@local \
    commit -qm "chore: $label" --allow-empty
  git -C "$clone" rev-parse HEAD
}

run_cell() {
  local task=$1 arm=$2 round=$3
  local out="$H/runs/$task/$arm/$round"
  local wt prompt
  prompt="$(cat "$H/tasks/$task/PROMPT.md")"
  local -a flags=(-p --output-format json --permission-mode bypassPermissions \
                  --max-turns "$MAX_TURNS" --model "$MODEL")
  case "$arm" in
    # --mcp-config is variadic — never last, and the prompt goes in on stdin.
    bare) flags+=(--mcp-config "$H/configs/bare/mcp-empty.json" --strict-mcp-config) ;;
    team) prompt="/team-irfan $prompt" ;;
  esac

  case "$task" in
    MEM-A|MEM-B) wt="$WT_ROOT/MEM-$arm-$round" ;;
    *)           wt="$WT_ROOT/$task-$arm-$round" ;;
  esac

  if [ "$DRY" = 1 ]; then
    echo "[$task/$arm/$round] CLAUDE_CONFIG_DIR=$H/configs/$arm claude ${flags[*]} <<< \"$prompt\"  (wt: $wt)"
    return 0
  fi
  if [ "$task" = MEM-B ] && [ ! -d "$wt/.git" ]; then
    die "MEM-B needs MEM-A's clone — run MEM-A $arm $round first"
  fi

  mkdir -p "$out" "$WT_ROOT"
  case "$task" in
    MEM-A) setup_mem_clone "$wt"
           git -C "$wt" rev-parse HEAD > "$out/base-commit.txt" ;;
    MEM-B) git -C "$wt" rev-parse HEAD > "$out/base-commit.txt" ;;
    *)     setup_worktree "$task" "$arm" "$round" "$wt" ;;
  esac
  echo "$wt" > "$out/worktree.path"

  local db="bench-$arm-$round.db"
  case "$task" in MEM-A|MEM-B) db="bench-mem.db" ;; esac

  local start end status=ok
  start=$(date +%s)
  (
    cd "$wt"
    CLAUDE_CONFIG_DIR="$H/configs/$arm" \
    TEAM_IRFAN_AUTO_APPROVE=1 \
    DATABASE_URL="file:./$db" \
    API_KEY=bench-key \
      claude "${flags[@]}" <<< "$prompt"
  ) > "$out/result.json.tmp" 2> "$out/stderr.log" &
  local pid=$!
  ( sleep "$MAX_SEC"; kill -TERM "$pid" 2>/dev/null ) & local killer=$!
  wait "$pid"; local rc=$?
  kill "$killer" 2>/dev/null
  end=$(date +%s)

  # A capped cell is scored, not discarded — hitting the cap IS the C3 result.
  if [ $((end - start)) -ge "$MAX_SEC" ]; then
    status="capped(time)"
  elif [ "$rc" -ne 0 ]; then
    status="fail(rc=$rc)"
  elif [ "$(jq -r '.num_turns // 0' "$out/result.json.tmp" 2>/dev/null)" -ge "$MAX_TURNS" ]; then
    status="capped(turns)"
  fi

  case "$task" in
    MEM-A|MEM-B) commit_session "$wt" "session $task $arm r$round" > "$out/commit.txt" ;;
  esac

  jq -n --arg t "$task" --arg a "$arm" --arg r "$round" --arg s "$status" \
        --argjson w $((end - start)) --arg wt "$wt" \
    '{task:$t,arm:$a,round:$r,status:$s,wall_sec:$w,worktree:$wt}' > "$out/meta.json"
  mv "$out/result.json.tmp" "$out/result.json"   # atomic: result lands last
  echo "[$task/$arm/$round] $status  $((end - start))s"
}

# ------------------------------------------------------------------- arg parse
if [ $# -ge 3 ] && [ "$1" != "all" ]; then
  mkdir -p "$H/runs"
  # LOCK_SUFFIX lets per-arm lanes coexist (single-cell mode only); arms share
  # nothing but the OAuth rate limit. Default stays one lock, one run.
  lock="$H/runs/.lock${LOCK_SUFFIX:-}"
  if ! mkdir "$lock" 2>/dev/null; then die "another run.sh holds $lock"; fi
  trap 'rmdir "$lock" 2>/dev/null' EXIT
  run_cell "$1" "$2" "$3"; exit $?
fi
[ "${1:-}" = "all" ] || { sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --tasks) TASKS="$2"; shift 2 ;;
    --arms) ARMS="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) die "unknown flag $1" ;;
  esac
done

[ -d "$BENCH_ROOT/.git" ] || die "no fixture repo — run bin/init.sh first"
mkdir -p "$H/runs"
if [ "$DRY" = 0 ]; then
  if ! mkdir "$H/runs/.lock" 2>/dev/null; then
    die "another run.sh holds runs/.lock — sequential means one at a time"
  fi
  trap 'rmdir "$H/runs/.lock" 2>/dev/null' EXIT
fi

for task in ${TASKS//,/ }; do
  for arm in ${ARMS//,/ }; do
    for r in $(seq 1 "$(rounds_for "$task")"); do
      if [ -s "$H/runs/$task/$arm/$r/result.json" ]; then
        [ "$DRY" = 1 ] && echo "[$task/$arm/$r] done — skip"
        continue
      fi
      run_cell "$task" "$arm" "$r"
    done
  done
done
echo "done. score with: bin/score.sh all"
