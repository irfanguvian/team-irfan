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
# Pinned explicitly: arm A has an empty settings.json and would otherwise take the
# CLI default, while arms B and C inherit the operator's "model": "opus". Same
# model in every arm is the whole premise.
#
# TG_BENCH_MODEL=haiku|sonnet runs the harness×model matrix: it pins --model on
# every arm AND is exported into arm C, where the router overrides its per-node
# matrix uniformly and metrics.sh stamps bench_model into metrics.json. The
# production matrix keeps `haiku: never`; only this variable ever bypasses it,
# and every number it produces is labeled.
case "${TG_BENCH_MODEL:-}" in
  haiku)  MODEL="claude-haiku-4-5-20251001" ;;
  sonnet) MODEL="claude-sonnet-5" ;;
  "")     MODEL="${BENCH_MODEL:-claude-opus-5}" ;;
  *)      echo "run.sh: TG_BENCH_MODEL must be haiku or sonnet, got ${TG_BENCH_MODEL}" >&2; exit 1 ;;
esac
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
  local -a flags=(-p --output-format json --permission-mode bypassPermissions --max-turns "$MAX_TURNS" --model "$MODEL")

  case "$arm" in
    # --mcp-config is variadic: it swallows every following argument, so it must
    # never be the last flag, and the prompt goes in on stdin rather than as a
    # positional (which it would eat).
    bare) flags+=(--mcp-config "$H/configs/bare/mcp-empty.json" --strict-mcp-config) ;;
    team) prompt="/team-irfan $prompt" ;;
  esac

  if [ "$DRY" = 1 ]; then
    echo "[$task/$arm/$round] CLAUDE_CONFIG_DIR=$H/configs/$arm claude ${flags[*]} <<< \"$prompt\""
    return 0
  fi

  mkdir -p "$out" "$WT_ROOT"
  setup_worktree "$task" "$arm" "$round" "$wt"
  # Every arm gets the pre-answered interview at the worktree root, byte for
  # byte — headless runs have no operator to answer clarifying questions, and
  # refusal-on-ambiguity would otherwise be a forfeit. score.sh excludes it.
  cp "$H/tasks/$task/clarifications.md" "$wt/clarifications.md" 2>/dev/null || true
  echo "$wt" > "$out/worktree.path"

  local start end status rc=0
  start=$(date +%s)
  (
    cd "$wt"
    CLAUDE_CONFIG_DIR="$H/configs/$arm" \
    TEAM_IRFAN_AUTO_APPROVE=1 \
    TG_BENCH_MODEL="${TG_BENCH_MODEL:-}" \
    DATABASE_URL="file:./bench-$arm-$round.db" \
    API_KEY=bench-key \
      claude "${flags[@]}" <<< "$prompt"
  ) > "$out/result.json" 2> "$out/stderr.log" &
  local pid=$!
  # claude -p prints one final {"type":"result"} object — but plugins (the
  # OMC daemon) can keep the process alive AFTER that write, so waiting on
  # the pid alone turns every finished cell into fail(timeout) at MAX_SEC.
  # Measured: a cell that completed in 113s was recorded 3230s. Poll for the
  # terminal object instead, then reap the cell's whole tree.
  status="fail(timeout)"
  while :; do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null; rc=$?
      status=ok; [ "$rc" -ne 0 ] && status="fail(rc=$rc)"
      break
    fi
    if [ -s "$out/result.json" ] && tail -c 4000 "$out/result.json" | grep -q '"type":"result"'; then
      status=ok
      break
    fi
    [ $(( $(date +%s) - start )) -ge "$MAX_SEC" ] && break
    sleep 5
  done
  # a terminal object that reports an API error is a failed measurement, not
  # a result — label it so the retry pass picks it up
  if [ "$status" = ok ] && tail -c 4000 "$out/result.json" 2>/dev/null \
       | grep -q '"terminal_reason":"api_error"'; then
    status="fail(api_error)"
  fi
  # reap children and grandchildren (claude + any daemon it spawned)
  local kids c
  kids=$(pgrep -P "$pid" 2>/dev/null)
  for c in $kids; do pkill -TERM -P "$c" 2>/dev/null; done
  pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null
  sleep 1
  for c in $kids; do pkill -KILL -P "$c" 2>/dev/null; done
  pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  end=$(date +%s)

  jq -n --arg t "$task" --arg a "$arm" --arg r "$round" --arg s "$status" \
        --argjson w $((end - start)) --arg wt "$wt" \
        --arg bm "${TG_BENCH_MODEL:-}" --arg m "$MODEL" \
    '{task:$t,arm:$a,round:$r,status:$s,wall_sec:$w,worktree:$wt,model:$m,
      bench_model:(if $bm == "" then null else $bm end)}' > "$out/meta.json"
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

# One automatic re-run for every failed cell (sequential — a failure burst is
# often transient API/DNS weather, and re-running it in parallel re-creates
# the burst). TG_BENCH_RETRY=0 disables. A cell failing twice stays failed.
if [ "${TG_BENCH_RETRY:-1}" != "0" ]; then
  for task in ${TASKS//,/ }; do
    for arm in ${ARMS//,/ }; do
      for r in $(seq 1 "$ROUNDS"); do
        st=$(jq -r '.status // "missing"' "$H/runs/$task/$arm/$r/meta.json" 2>/dev/null || echo missing)
        case "$st" in
          ok) ;;
          *) echo "=== retry $task/$arm/$r (was: $st) ==="; run_cell "$task" "$arm" "$r" ;;
        esac
      done
    done
  done
fi
echo "done. score with: bin/score.sh all"
