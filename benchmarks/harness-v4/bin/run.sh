#!/usr/bin/env bash
# Runs agents. The only script besides judge.sh that costs money.
#
#   run.sh <task> <arm> <round>     one cell. No pin checks — the debug path.
#   run.sh all [flags]              every remaining cell, strictly sequential.
#   run.sh --matrix [flags]         the supervised path: pin checks, judge
#                                   calibration, per-arm smoke test, one
#                                   detached lane per arm, ledger, PROGRESS.md,
#                                   notifications, then score+judge+report.
#   run.sh --lane <arms-csv> [flags]  internal: one lane. --matrix spawns these.
#
# Flags (all modes but single-cell)
#   --tasks a,b       subset of Q1,F1,B1,N5,MEM-A,MEM-B (fastest first; MEM-A
#                     must precede MEM-B — the pair shares one clone)
#   --arms a,b        subset of bare,omc,team
#   --lanes N         --matrix only. N parallel lanes; default = one lane per
#                     arm; 1 = strict sequential over every arm. Arms are split
#                     round-robin, a lane never runs two cells at once.
#   --expect-sha SHA  refuse unless HEAD == SHA (default: current HEAD)
#   --redo-infra[=<reason-substring>]
#                     rerun cells recorded as INFRA_FAIL (all of them, or only
#                     those whose reason contains the substring). The old cell
#                     dir is moved to <cell>.infra-<ts>/ and a fresh ledger line
#                     is written. Without this flag an infra cell is never rerun.
#   --dry-run         print the plan (lane layout + every cell command), create
#                     nothing, spawn nothing
#
# Env
#   BENCH_MODEL / BENCH_EFFORT / BENCH_TIER   see lib.sh (tier = model-effort)
#   CLAUDE_BIN=claude     binary to spawn; selftest injects a fake here
#   MAX_SEC=1200          wall cap per cell  -> INFRA_FAIL reason=budget(wall)
#   MAX_TURNS=150         turn cap           -> capped(turns), still a VALID cell
#   CELL_BUDGET_USD=3     watcher cap        -> kill -TERM -> INFRA_FAIL budget
#   JUDGE_MODEL           recorded in matrix.json, honoured by judge.sh
#   TEAM_IRFAN_NOTIFY_URL / TEAM_IRFAN_NOTIFY_MIN_GAP   see notify.sh
#   BENCH_SKIP_PIN=1 / BENCH_SKIP_CALIBRATE=1 / BENCH_SKIP_SMOKE=1
#                         selftest escapes. Each prints a loud warning; never
#                         use them for a measured run.
#
# Mode B headless. The plan gate for arm C is auto-approved, so what is measured
# is team-irfan WITHOUT its human check — say so in every report.
#
# Sequential within an arm. A lane owns runs/<tier>/.lock-<lane>, so a second
# invocation of the same lane refuses to start. Every cell writes meta.json and
# a ledger line before the next cell starts, so a crash loses at most one cell.
#
# Three-state cells: ok/capped(turns)/fail(rc=N) are results; INFRA_FAIL means
# the harness, not the agent, is what failed — those cells are never scored as
# pass or fail, and are never silently rerun (resume skips them on purpose).
#
# MEM cells are the one exception to fresh-worktree-per-cell: MEM-A creates one
# persistent clone per (arm, round); MEM-B runs in the SAME clone as a separate
# process minutes later — the second session finding the first session's state
# (.team-irfan/ for arm C) is the capability under test. run.sh commits the
# working tree after each MEM session so score.sh can diff per session without
# touching the clone.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$H/bin/lib.sh"

MAX_SEC="${MAX_SEC:-1200}"
MAX_TURNS="${MAX_TURNS:-150}"
CELL_BUDGET_USD="${CELL_BUDGET_USD:-3}"
REPO="$(git -C "$H" rev-parse --show-toplevel 2>/dev/null || echo "$H")"

TASKS="Q1 F1 B1 N5 MEM-A MEM-B"
ARMS="bare omc team"
LANES=""; EXPECT_SHA=""; DRY=0; LANE_ARMS=""; LANE=""; REDO_INFRA=""
CELL_STATUS=""; CELL_REASON=""

# ------------------------------------------------------------------ provenance
repo_plugin_version() { jq -r '.version // ""' "$REPO/.claude-plugin/plugin.json" 2>/dev/null; }
installed_plugin()    { jq -r ".plugins[\"team-irfan@team-irfan\"][0].$1 // \"\"" \
                          "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null; }
GIT_SHA="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo "")"
PLUGIN_VERSION="$(installed_plugin version)"

emit_meta() {  # path task arm round status reason wall worktree sid started ended cost
  jq -n --arg task "$2" --arg arm "$3" --arg round "$4" --arg status "$5" \
        --arg reason "$6" --argjson wall_sec "$7" --arg worktree "$8" \
        --arg session_id "$9" --arg started_at "${10}" --arg ended_at "${11}" \
        --argjson cost_usd_watch "${12}" \
        --arg git_sha "$GIT_SHA" --arg plugin_version "$PLUGIN_VERSION" \
        --arg model "$MODEL" --arg effort "$EFFORT" --arg tier "$TIER" '
    {task:$task,arm:$arm,round:$round,status:$status,reason:$reason,
     wall_sec:$wall_sec,worktree:$worktree,git_sha:$git_sha,
     plugin_version:$plugin_version,model:$model,effort:$effort,tier:$tier,
     session_id:$session_id,started_at:$started_at,ended_at:$ended_at,
     cost_usd_watch:$cost_usd_watch}' > "$1.tmp" && mv "$1.tmp" "$1"
}

after_cell() {  # task arm round status reason cost wall
  mkdir -p "$RES"
  # One line, one write syscall, append mode: safe enough across three lanes.
  jq -nc --arg ts "$(now_iso)" --arg task "$1" --arg arm "$2" --arg round "$3" \
         --arg status "$4" --arg reason "$5" --argjson cost_usd "$6" \
         --argjson wall_sec "$7" '
    {ts:$ts,task:$task,arm:$arm,round:$round,status:$status,reason:$reason,
     cost_usd:$cost_usd,wall_sec:$wall_sec}' >> "$RES/ledger.jsonl"
  bash "$H/bin/progress.sh" "$TIER" >/dev/null 2>&1 || true
  bash "$H/bin/notify.sh" cell-done \
    "$(jq -nc --arg c "$1/$2/$3" --arg s "$4" --argjson cost "$6" \
        '{last:{cell:$c,status:$s,cost:$cost}}')" >/dev/null 2>&1 || true
  CELL_STATUS="$4"; CELL_REASON="$5"
}

# ponytail: approximate — result.json total_cost_usd is authoritative. This only
# has to be right enough to pull the plug on a runaway cell.
# jq body copied from collect.sh (per-model usage x pricing.json), not sourced:
# collect.sh is worker-3's file and must stay free of this script's concerns.
cell_cost() {  # arm session-id -> usd
  local arm=$1 sid=$2 out
  local proj="$H/configs/$arm/projects"
  [ -d "$proj" ] && [ -s "$H/pricing.json" ] || { echo 0; return; }
  local -a f=()
  while IFS= read -r line; do [ -n "$line" ] && f+=("$line"); done < <(
    find "$proj" \( -name "$sid.jsonl" -o -path "*/$sid/subagents/*.jsonl" \) 2>/dev/null)
  [ ${#f[@]} -gt 0 ] || { echo 0; return; }
  out=$(jq -s --slurpfile p "$H/pricing.json" '
    [ .[] | select(.type=="assistant") | .message
      | select(.usage) | {model:(.model // "unknown"), u:.usage} ]
    | group_by(.model)
    | map({ model: .[0].model,
            input:  (map(.u.input_tokens              // 0) | add),
            output: (map(.u.output_tokens             // 0) | add),
            cache_read:  (map(.u.cache_read_input_tokens     // 0) | add),
            cache_write: (map(.u.cache_creation_input_tokens // 0) | add) })
    | [ .[] | . as $x
        | ($p[0][$x.model] // $p[0]["default"] // {in:0,out:0,cache_read:0,cache_write:0}) as $r
        | $x.input * $r["in"] / 1e6 + $x.output * $r.out / 1e6
        + $x.cache_read * $r.cache_read / 1e6 + $x.cache_write * $r.cache_write / 1e6 ]
    | add // 0' "${f[@]}" 2>/dev/null)
  case "$out" in ''|*[!0-9.e+-]*) echo 0 ;; *) echo "$out" ;; esac
}

over_budget() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>b)}'; }

# TERM, five seconds of grace, then KILL. Without the escalation a claude that
# ignores TERM leaves `wait` blocking until the operator notices.
end_process() {
  kill -TERM "$1" 2>/dev/null
  local i
  for i in 1 2 3 4 5; do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 1
  done
  kill -KILL "$1" 2>/dev/null
}

# ---------------------------------------------------------------- fixture prep
install_deps() {  # $1 = target dir
  if [ ! -d "$BENCH_ROOT/node_modules" ]; then
    echo "run.sh: warning: $BENCH_ROOT/node_modules missing — deps not installed" >&2
    return 0
  fi
  cp -Rc "$BENCH_ROOT/node_modules" "$1/node_modules" 2>/dev/null \
    || cp -R "$BENCH_ROOT/node_modules" "$1/node_modules"
}

setup_db() {  # $1 = dir, $2 = db name
  [ -f "$1/.env.example" ] || return 0
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

# A dead or resumed MEM-B attempt must not leave edits for score.sh to diff.
# Rewind to the commit session A ended on; A's .team-irfan/ state survives both
# steps because the fixture gitignores it (so it is untracked, and `clean -fd`
# without -x leaves ignored files alone).
reset_mem_clone() {  # wt arm round
  local wt=$1 target
  target=$(cat "$(cell_dir MEM-A "$2" "$3")/commit.txt" 2>/dev/null)
  [ -n "$target" ] || target=$(git -C "$wt" rev-parse HEAD)
  git -C "$wt" reset -q --hard "$target"
  git -C "$wt" clean -qfd -e node_modules -e .env -e '*.db'
}

commit_session() {  # snapshot a MEM session's result inside the clone
  local clone=$1 label=$2
  git -C "$clone" add -A
  git -C "$clone" -c user.name=bench -c user.email=bench@local \
    commit -qm "chore: $label" --allow-empty
  git -C "$clone" rev-parse HEAD
}

# --------------------------------------------------------------------- one cell
infra_cell() {  # task arm round reason  — no process, no cost, meta only
  local out; out=$(cell_dir "$1" "$2" "$3"); mkdir -p "$out"
  local now; now=$(now_iso)
  emit_meta "$out/meta.json" "$1" "$2" "$3" INFRA_FAIL "$4" 0 "" "" "$now" "$now" 0
  after_cell "$1" "$2" "$3" INFRA_FAIL "$4" 0 0
  echo "[$1/$2/$3] INFRA_FAIL  $4"
}

run_cell() {
  local task=$1 arm=$2 round=$3
  local out wt prompt
  out=$(cell_dir "$task" "$arm" "$round")
  prompt="$(cat "$H/tasks/$task/PROMPT.md")"
  local sid; sid=$(uuidgen | tr 'A-Z' 'a-z')
  local -a flags=(-p --output-format json --permission-mode bypassPermissions \
                  --max-turns "$MAX_TURNS" --model "$MODEL" --effort "$EFFORT" \
                  --session-id "$sid")
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
    echo "[$task/$arm/$round] cd $wt && CLAUDE_CONFIG_DIR=$H/configs/$arm TEAM_IRFAN_AUTO_APPROVE=1 $CLAUDE_BIN ${flags[*]} <<< \"${prompt:0:60}...\""
    return 0
  fi

  mkdir -p "$out" "$WT_ROOT" "$RUNS"
  echo "$task/$arm/$round $(now_iso)" > "$RUNS/.current-$LANE"

  if ! bash "$H/bin/preflight.sh" "$task" "$arm" "$round" "$wt" >> "$out/preflight.log" 2>&1; then
    infra_cell "$task" "$arm" "$round" "preflight:doctor"
    rm -f "$RUNS/.current-$LANE"
    return 0
  fi

  if [ "$task" = MEM-B ] && [ ! -d "$wt/.git" ]; then
    infra_cell "$task" "$arm" "$round" "mem-a-missing"
    rm -f "$RUNS/.current-$LANE"
    return 0
  fi

  case "$task" in
    MEM-A) setup_mem_clone "$wt"
           git -C "$wt" rev-parse HEAD > "$out/base-commit.txt" ;;
    MEM-B) reset_mem_clone "$wt" "$arm" "$round"
           git -C "$wt" rev-parse HEAD > "$out/base-commit.txt" ;;
    *)     setup_worktree "$task" "$arm" "$round" "$wt" ;;
  esac
  echo "$wt" > "$out/worktree.path"
  # Per-session proof files. The MEM clone is reused, so A's sentinel and
  # heartbeat must not be mistaken for B's.
  rm -rf "$wt/.tg-bench" "$wt/.team-irfan/.driver"

  local db="bench-$arm-$round.db"
  case "$task" in MEM-A|MEM-B) db="bench-mem.db" ;; esac

  local started ended start end rc cost=0 kill_reason="" tick=0
  started=$(now_iso); start=$(date +%s)
  # exec, so $pid IS claude and not a wrapper shell the kill would stop at.
  (
    cd "$wt" || exit 97
    export CLAUDE_CONFIG_DIR="$H/configs/$arm" TEAM_IRFAN_AUTO_APPROVE=1 \
           DATABASE_URL="file:./$db" API_KEY=bench-key
    exec "$CLAUDE_BIN" "${flags[@]}" <<< "$prompt"
  ) > "$out/result.json.tmp" 2> "$out/stderr.log" &
  local pid=$!

  # Supervisor: wall clock hard, spend soft-checked every 20 s. No retry, ever.
  while kill -0 "$pid" 2>/dev/null; do
    sleep 2; tick=$((tick + 2)); end=$(date +%s)
    if [ $((end - start)) -ge "$MAX_SEC" ]; then
      kill_reason="budget(wall)"; end_process "$pid"; break
    fi
    if [ $((tick % 20)) -eq 0 ]; then
      cost=$(cell_cost "$arm" "$sid")
      if over_budget "$cost" "$CELL_BUDGET_USD"; then
        kill_reason="budget"; end_process "$pid"; break
      fi
    fi
  done
  wait "$pid"; rc=$?
  end=$(date +%s); ended=$(now_iso)
  cost=$(cell_cost "$arm" "$sid")

  local status=ok reason=""
  if [ -n "$kill_reason" ]; then
    status=INFRA_FAIL; reason="$kill_reason"
  elif [ "$rc" -ne 0 ] \
       && grep -qiE 'rate.?limit|overloaded|usage limit|429' "$out/stderr.log" 2>/dev/null; then
    status=INFRA_FAIL; reason="auth/ratelimit"
  elif [ "$rc" -ne 0 ]; then
    status="fail(rc=$rc)"
  elif [ "$(jq -r '.num_turns // 0' "$out/result.json.tmp" 2>/dev/null)" -ge "$MAX_TURNS" ] 2>/dev/null; then
    # Hitting the turn cap IS the C3 result — a valid cell, not an infra failure.
    status="capped(turns)"
  fi

  # Did the plugin actually load? Without the SessionStart sentinel an arm-C cell
  # measured an unhooked Claude, which is not team-irfan.
  if [ "$arm" = team ] && [ "$status" != INFRA_FAIL ]; then
    local loaded; loaded=$(jq -r '.version // ""' "$wt/.tg-bench/plugin-loaded" 2>/dev/null)
    if [ -z "$loaded" ] || [ "$loaded" != "$(repo_plugin_version)" ]; then
      status=INFRA_FAIL; reason="plugin-load-failed"
    fi
  fi

  case "$task" in
    MEM-A|MEM-B) commit_session "$wt" "session $task $arm r$round" > "$out/commit.txt" ;;
  esac

  emit_meta "$out/meta.json" "$task" "$arm" "$round" "$status" "$reason" \
            $((end - start)) "$wt" "$sid" "$started" "$ended" "$cost"
  if [ -s "$out/result.json.tmp" ]; then
    mv "$out/result.json.tmp" "$out/result.json"   # atomic: result lands last
  else
    rm -f "$out/result.json.tmp"                   # killed before it printed anything
  fi
  local real; real=$(jq -r '.total_cost_usd // 0' "$out/result.json" 2>/dev/null)
  case "$real" in ''|null|*[!0-9.e+-]*) real=0 ;; esac

  after_cell "$task" "$arm" "$round" "$status" "$reason" "$real" $((end - start))
  rm -f "$RUNS/.current-$LANE"
  echo "[$task/$arm/$round] $status ${reason:+($reason)} $((end - start))s \$$real"
}

# ------------------------------------------------------------------- lane logic
cell_done() {  # a cell with a result, or a recorded infra failure, is finished
  local out status reason
  out=$(cell_dir "$1" "$2" "$3")
  status=$(jq -r '.status // ""' "$out/meta.json" 2>/dev/null)
  # The infra check comes first: a killed cell can have both an INFRA_FAIL meta
  # and a partial result.json, and --redo-infra must still see it.
  if [ "$status" != INFRA_FAIL ]; then
    [ -s "$out/result.json" ] && return 0
    return 1
  fi
  # --redo-infra: only an explicit flag reruns an infra cell, and the old
  # attempt is moved aside rather than overwritten. Never silent.
  if [ -n "$REDO_INFRA" ]; then
    reason=$(jq -r '.reason // ""' "$out/meta.json" 2>/dev/null)
    if [ "$REDO_INFRA" = "*" ] || [ "${reason#*"$REDO_INFRA"}" != "$reason" ]; then
      if [ "$DRY" = 1 ]; then
        echo "[$1/$2/$3] would redo (infra: $reason)"
      else
        mv "$out" "$out.infra-$(date -u +%Y%m%dT%H%M%SZ)"
        echo "[$1/$2/$3] redo — previous INFRA_FAIL ($reason) moved aside"
      fi
      return 1
    fi
  fi
  return 0
}

# Every team cell this lane has not reached yet becomes a recorded infra failure
# at zero cost. Counts stay symmetric across arms and resume never reruns them.
abort_lane() {  # cause from-task from-arm from-round
  local cause=$1 ft=$2 fa=$3 fr=$4 seen=0 task arm r
  for task in $TASKS; do
    for arm in $LANE_ARMS; do
      for r in $(seq 1 "$(rounds_for "$task")"); do
        if [ "$seen" = 0 ]; then
          [ "$task/$arm/$r" = "$ft/$fa/$fr" ] && seen=1
          continue
        fi
        [ "$arm" = team ] || continue
        cell_done "$task" "$arm" "$r" && continue
        infra_cell "$task" "$arm" "$r" "lane-aborted:$cause"
      done
    done
  done
  bash "$H/bin/notify.sh" lane-abort \
    "$(jq -nc --arg l "$LANE" --arg c "$cause" '{lane:$l,cause:$c}')" >/dev/null 2>&1 || true
}

lane_loop() {
  for task in $TASKS; do
    for arm in $LANE_ARMS; do
      for r in $(seq 1 "$(rounds_for "$task")"); do
        if cell_done "$task" "$arm" "$r"; then
          [ "$DRY" = 1 ] && echo "[$task/$arm/$r] done — skip"
          continue
        fi
        run_cell "$task" "$arm" "$r"
        [ "$DRY" = 1 ] && continue
        case "$CELL_STATUS:$CELL_REASON" in
          INFRA_FAIL:plugin-load-failed)
            echo "run.sh: lane $LANE aborting — plugin did not load" >&2
            abort_lane plugin-load-failed "$task" "$arm" "$r"
            return 3 ;;
          INFRA_FAIL:auth/ratelimit)
            # Deliberately leaves the remaining cells unrecorded: a rate limit is
            # transient, so a later `--matrix` resume must be free to run them.
            echo "run.sh: lane $LANE aborting — auth/rate limit" >&2
            bash "$H/bin/notify.sh" lane-abort \
              "$(jq -nc --arg l "$LANE" '{lane:$l,cause:"auth/ratelimit"}')" >/dev/null 2>&1 || true
            return 3 ;;
        esac
      done
    done
  done
  return 0
}

with_lock() {  # lock-name then run "$@"
  local lock="$RUNS/.lock-$1"; shift
  mkdir -p "$RUNS"
  if ! mkdir "$lock" 2>/dev/null; then
    # A lock whose owner is gone is a crash, not a running lane. Steal it loudly.
    local owner; owner=$(cat "$lock/pid" 2>/dev/null)
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
      die "another run.sh (pid $owner) holds $lock — one cell at a time per lane"
    fi
    echo "run.sh: stealing stale lock $lock (owner ${owner:-unknown} is gone)" >&2
    rm -rf "$lock"
    mkdir "$lock" 2>/dev/null || die "cannot take $lock"
  fi
  echo $$ > "$lock/pid"
  rm -f "$RUNS/.current-$LANE"   # stale in-flight marker from a crashed lane
  # Expanded now, not at exit: the trap outlives this function's locals.
  # shellcheck disable=SC2064
  trap "rm -rf '$lock' 2>/dev/null; rm -f '$RUNS/.current-$LANE' 2>/dev/null" EXIT
  "$@"
}

# ------------------------------------------------------------------ matrix gates
pin_checks() {
  if [ "${BENCH_SKIP_PIN:-}" = 1 ]; then
    echo "!!! BENCH_SKIP_PIN=1 — measuring an UNPINNED tree. Selftest only. !!!" >&2
    return 0
  fi
  local head expect dirty isha ivers rvers
  head="$GIT_SHA"
  [ -n "$head" ] || die "not a git repo: $REPO"
  expect="${EXPECT_SHA:-$head}"
  [ "$head" = "$expect" ] || die "HEAD $head != --expect-sha $expect
  fix: git -C $REPO checkout $expect   (or rerun with --expect-sha $head)"
  dirty=$(git -C "$REPO" status --porcelain 2>/dev/null \
    | awk '{p=substr($0,4)} p !~ /^benchmarks\/harness-v4\/(runs|results|configs)\// {print}')
  [ -z "$dirty" ] || die "working tree dirty — what ran would not be what is committed:
$dirty
  fix: git -C $REPO commit -am '<msg>'   (or stash)"
  rvers=$(repo_plugin_version)
  ivers=$(installed_plugin version)
  isha=$(installed_plugin gitCommitSha)
  [ -n "$ivers" ] || die "team-irfan plugin is not installed
  fix: claude plugin install team-irfan@team-irfan"
  [ "$isha" = "$head" ] || die "installed plugin sha $isha != HEAD $head
  fix: claude plugin update team-irfan@team-irfan"
  [ "$ivers" = "$rvers" ] || die "installed plugin version $ivers != plugin.json $rvers
  fix: claude plugin update team-irfan@team-irfan"
  PLUGIN_VERSION="$ivers"
}

calibration_gate() {
  if [ "${BENCH_SKIP_CALIBRATE:-}" = 1 ]; then
    echo "!!! BENCH_SKIP_CALIBRATE=1 — judge is ungated. Selftest only. !!!" >&2
    return 0
  fi
  bash "$H/bin/judge.sh" --calibrate \
    || die "judge calibration failed — an uncalibrated judge decides nothing. Fix JUDGE_MODEL first."
}

smoke_arms() {
  if [ "${BENCH_SKIP_SMOKE:-}" = 1 ]; then
    echo "!!! BENCH_SKIP_SMOKE=1 — arm configs unverified. Selftest only. !!!" >&2
    return 0
  fi
  local arm
  for arm in $ARMS; do
    CLAUDE_CONFIG_DIR="$H/configs/$arm" "$CLAUDE_BIN" -p --model "$MODEL" \
      --effort "$EFFORT" --max-turns 1 --output-format json <<< "reply ok" >/dev/null 2>&1 \
      || die "smoke test failed for arm $arm ($MODEL / effort $EFFORT)
  fix: bin/init.sh --configs, then check the model and effort are available to this account"
  done
}

# ----------------------------------------------------------------------- matrix
do_matrix() {
  local -a lane_arms=() pids=()
  local n i=0 arm rc=0

  # Lanes: default one per arm; --lanes N splits the arms round-robin.
  n="${LANES:-$(wc -w <<< "$ARMS" | tr -d ' ')}"
  [ "$n" -ge 1 ] 2>/dev/null || die "--lanes must be >= 1"
  for arm in $ARMS; do
    local slot=$((i % n))
    if [ -z "${lane_arms[$slot]:-}" ]; then lane_arms[$slot]="$arm"
    else lane_arms[$slot]="${lane_arms[$slot]},$arm"; fi
    i=$((i + 1))
  done

  if [ "$DRY" = 1 ]; then
    echo "[dry-run] tier=$TIER model=$MODEL effort=$EFFORT judge=${JUDGE_MODEL:-claude-opus-5}"
    echo "[dry-run] pin: HEAD==${EXPECT_SHA:-$GIT_SHA}, clean tree, installed plugin sha==HEAD, version==$(repo_plugin_version)"
    echo "[dry-run] gates: judge.sh --calibrate; per-arm smoke ($CLAUDE_BIN -p --max-turns 1)"
    echo "[dry-run] would write $RES/matrix.json  cell budget \$$CELL_BUDGET_USD  wall ${MAX_SEC}s"
    for i in "${!lane_arms[@]}"; do
      echo "[dry-run] lane $((i + 1))/$n: arms=${lane_arms[$i]}  lock=$RUNS/.lock-${lane_arms[$i]//,/+}  log=$RUNS/lane-${lane_arms[$i]//,/+}.log"
      ( LANE_ARMS="${lane_arms[$i]//,/ }"; LANE="${lane_arms[$i]//,/+}"; lane_loop )
    done
    echo "[dry-run] then: score.sh all && judge.sh all && same-hole.sh all && report.py --tier $TIER"
    echo "[dry-run] then: $RES/DONE + notify matrix-done   (failure: $RES/ABORTED + notify matrix-abort)"
    return 0
  fi

  pin_checks
  calibration_gate
  smoke_arms

  mkdir -p "$RES" "$RUNS"
  rm -f "$RES/DONE" "$RES/ABORTED"
  jq -n --arg started_at "$(now_iso)" --arg tier "$TIER" --arg git_sha "$GIT_SHA" \
        --arg plugin_version "$PLUGIN_VERSION" --arg model "$MODEL" --arg effort "$EFFORT" \
        --argjson lanes "$n" --arg arms "$ARMS" --arg tasks "$TASKS" \
        --argjson cell_budget_usd "$CELL_BUDGET_USD" --argjson max_sec "$MAX_SEC" \
        --arg judge_model "${JUDGE_MODEL:-claude-opus-5}" \
        --arg expect_sha "${EXPECT_SHA:-$GIT_SHA}" --argjson pid $$ '
    {started_at:$started_at,tier:$tier,git_sha:$git_sha,plugin_version:$plugin_version,
     model:$model,effort:$effort,lanes:$lanes,arms:($arms|split(" ")),
     tasks:($tasks|split(" ")),cell_budget_usd:$cell_budget_usd,max_sec:$max_sec,
     judge_model:$judge_model,expect_sha:$expect_sha,pid:$pid}' > "$RES/matrix.json"
  echo "running" > "$RES/.phase"
  bash "$H/bin/progress.sh" "$TIER" >/dev/null 2>&1 || true

  export BENCH_TIER="$TIER" BENCH_MODEL="$MODEL" BENCH_EFFORT="$EFFORT" \
         CLAUDE_BIN MAX_SEC MAX_TURNS CELL_BUDGET_USD
  for i in "${!lane_arms[@]}"; do
    local label="${lane_arms[$i]//,/+}"
    echo "lane $label: nohup run.sh --lane ${lane_arms[$i]} > $RUNS/lane-$label.log"
    nohup bash "$H/bin/run.sh" --lane "${lane_arms[$i]}" --tasks "${TASKS// /,}" \
      ${REDO_INFRA:+--redo-infra="$REDO_INFRA"} \
      > "$RUNS/lane-$label.log" 2>&1 &
    pids+=($!)
  done
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}" || { rc=$?; echo "lane ${lane_arms[$i]} exited $rc" >&2; }
  done

  # An aborted lane still gets scored and reported: half a matrix on disk is
  # evidence, and the operator needs the report to decide what to rerun.
  local abort=""
  [ "$rc" != 0 ] && abort="lane failure (rc=$rc) — see $RUNS/lane-*.log"

  local report=""
  run_step scoring bash "$H/bin/score.sh" all     || abort="${abort:-score.sh all failed}"
  run_step judging bash "$H/bin/judge.sh" all     || abort="${abort:-judge.sh all failed}"
  run_step judging bash "$H/bin/same-hole.sh" all || abort="${abort:-same-hole.sh all failed}"
  if run_step reporting python3 "$H/bin/report.py" --tier "$TIER" > "$RUNS/report.out" 2>&1; then
    # report.py prints "report: <abs path>" as its last line — trust it, do not
    # re-derive the filename here.
    report=$(sed -n 's/^report: //p' "$RUNS/report.out" | tail -1)
  else
    abort="${abort:-report.py failed}"
  fi
  cat "$RUNS/report.out" 2>/dev/null

  if [ -n "$abort" ]; then
    matrix_abort "$abort"
    return 1
  fi
  [ -n "$report" ] || { matrix_abort "report.py printed no report path"; return 1; }

  echo "$report" > "$RES/DONE"
  echo "done" > "$RES/.phase"
  bash "$H/bin/progress.sh" "$TIER" >/dev/null 2>&1 || true
  bash "$H/bin/notify.sh" matrix-done \
    "$(jq -nc --arg r "$report" '{report:$r}')" >/dev/null 2>&1 || true
  echo "matrix done — report: $report"
}

run_step() {  # phase-name cmd...
  echo "$1" > "$RES/.phase"; shift
  bash "$H/bin/progress.sh" "$TIER" >/dev/null 2>&1 || true
  "$@"
}

matrix_abort() {
  echo "$1" > "$RES/ABORTED"
  echo "aborted" > "$RES/.phase"
  bash "$H/bin/progress.sh" "$TIER" >/dev/null 2>&1 || true
  bash "$H/bin/notify.sh" matrix-abort \
    "$(jq -nc --arg r "$1" '{reason:$r}')" >/dev/null 2>&1 || true
  echo "run.sh: matrix ABORTED — $1" >&2
}

# ------------------------------------------------------------------- arg parse
usage() { sed -n '2,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }

parse_flags() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --tasks)      TASKS="${2//,/ }"; shift 2 ;;
      --arms)       ARMS="${2//,/ }"; shift 2 ;;
      --lanes)      [ "$MODE" = --matrix ] || die "--lanes belongs to --matrix"
                    LANES="$2"; shift 2 ;;
      --redo-infra) REDO_INFRA='*'; shift ;;
      --redo-infra=*) REDO_INFRA="${1#*=}"; shift ;;
      --expect-sha) EXPECT_SHA="$2"; shift 2 ;;
      --dry-run)    DRY=1; shift ;;
      *) die "unknown flag $1" ;;
    esac
  done
}

MODE="${1:-}"
case "$MODE" in
  --matrix)
    shift; parse_flags "$@"
    do_matrix; exit $? ;;
  --lane)
    [ $# -ge 2 ] || usage
    LANE_ARMS="${2//,/ }"; LANE="${2//,/+}"; shift 2
    parse_flags "$@"
    ARMS="$LANE_ARMS"
    [ -d "$BENCH_ROOT/.git" ] || die "no fixture repo — run bin/init.sh first"
    with_lock "$LANE" lane_loop; exit $? ;;
  all)
    shift; parse_flags "$@"
    [ -d "$BENCH_ROOT/.git" ] || die "no fixture repo — run bin/init.sh first"
    LANE_ARMS="$ARMS"; LANE="all"
    if [ "$DRY" = 1 ]; then lane_loop; exit $?; fi
    pin_checks
    with_lock all lane_loop
    rc=$?
    echo "done. score with: bin/score.sh all"
    exit $rc ;;
  ""|-h|--help) usage ;;
  *)
    [ $# -eq 3 ] || usage   # single-cell takes no flags; --matrix/all take those
    LANE="single-$2"
    if [ -f "$(cell_dir "$1" "$2" "$3")/meta.json" ]; then
      echo "run.sh: overwriting the existing $1/$2/$3 cell (single-cell mode is explicit)" >&2
    fi
    with_lock "single-$2" run_cell "$1" "$2" "$3"
    exit $? ;;
esac
