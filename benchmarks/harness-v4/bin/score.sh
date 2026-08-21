#!/usr/bin/env bash
# Scores finished runs. Deterministic: every number here comes from a command or
# from extract.py. Zero LLM — the pairwise quality review lives in judge.sh.
#
#   score.sh <task> <arm> <round>   score one cell
#   score.sh all                    score every cell in the tier's runs/ tree
#
# Tier comes from BENCH_TIER (or BENCH_MODEL+BENCH_EFFORT) via lib.sh; the CSV
# is $RES/results.csv. Cells are read from $RUNS/<task>/<arm>/<round>/.
#
# Order matters: the regression gate runs BEFORE the hidden tests are copied in.
# A run that fails the gate, or edited a protected test file, scores pass_rate 0
# whatever its acceptance result was. Q1 is special: ANY source diff is a fail —
# it is a question, not a change request.
#
# MEM cells are scored from the commits run.sh recorded, in a throwaway checkout
# — never in the live clone, which session B may still need pristine.
#
# A cell whose meta.json says INFRA_FAIL still gets a row (that is the point of
# three-state cells): validity=infra, false_done forced false, cost 0 when the
# lane aborted before the process ever started. Verdicts filter those out;
# nothing is silently dropped.
#
# CSV columns (38) — the first 28 are v4's original schema, unchanged in order:
#   task,arm,round,status,pass_rate,passed,total,regression,guard,oos_files,
#   diff_loc,cost_usd,tokens_in,tokens_out,tool_calls,num_turns,wall_sec,
#   verified_before_done,claims_done,false_done,rework_loops,plan_exists,
#   predicted_calls,actual_calls,prediction_error,plan_adherence,replans,
#   calls_to_locate,
#   tier,git_sha,plugin_version,model,effort,session_id,validity,reason,
#   cell_status,failure_mode,cost_source
# A CSV written with the old 28-column header is never appended to: the legacy
# opus results.csv is a durable record, per-tier CSVs are created fresh.
#
# One row per (task,arm,round), rewritten in place: a matrix that aborted and
# resumed runs score.sh all more than once, and a doubled row would double-count
# in every rate and every MIN_N.
set -uo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CSV="$RES/results.csv"

HEADER='task,arm,round,status,pass_rate,passed,total,regression,guard,oos_files,diff_loc,cost_usd,tokens_in,tokens_out,tool_calls,num_turns,wall_sec,verified_before_done,claims_done,false_done,rework_loops,plan_exists,predicted_calls,actual_calls,prediction_error,plan_adherence,replans,calls_to_locate,tier,git_sha,plugin_version,model,effort,session_id,validity,reason,cell_status,failure_mode,cost_source'

# .tg-bench is the harness's own sentinel/heartbeat dir — never the agent's work.
NOISE=(':(exclude).omc' ':(exclude).claude' ':(exclude).claude.json'
       ':(exclude).team-irfan' ':(exclude).tg-bench')

# extract.py's shape, for cells that never produced a transcript.
NULL_EXTRACT='{"verified_before_done":null,"claims_done":null,"rework_loops":null,"plan_exists":null,"predicted_calls":null,"actual_calls":null,"prediction_error":null,"plan_adherence":null,"replans":null,"calls_to_locate":null}'

# One row per cell, last write wins. mkdir is the lock; 10s then proceed —
# a stale lock must not wedge scoring at the end of a paid matrix.
csv_put() {  # task arm round row
  local lock="$RES/.csv.lock" n=0
  until mkdir "$lock" 2>/dev/null || [ "$n" -ge 50 ]; do n=$((n+1)); sleep 0.2; done
  [ -s "$CSV" ] || echo "$HEADER" > "$CSV"
  grep -v "^\"$1\",\"$2\",\"$3\"," "$CSV" > "$CSV.tmp"
  printf '%s\n' "$4" >> "$CSV.tmp"
  mv "$CSV.tmp" "$CSV"
  rmdir "$lock" 2>/dev/null
}

protected_for() {
  case "$1" in
    N5) echo "test/invoices.contract.spec.ts test/customers.contract.spec.ts test/refunds.contract.spec.ts test/audit.contract.spec.ts test/reports.overview.contract.spec.ts" ;;
    B1) echo "test/reports.spec.ts" ;;
    MEM-A) echo "test/reports.overview.contract.spec.ts" ;;
    MEM-B) echo "test/customers.contract.spec.ts" ;;
    *) echo "" ;;
  esac
}

transcript_for() {  # arm session_id -> path or ""
  [ -n "${2:-}" ] || return 0
  find "$H/configs/$1/projects" -name "$2.jsonl" 2>/dev/null | head -1
}

score_cell() {
  local task=$1 arm=$2 round=$3
  local out; out=$(cell_dir "$task" "$arm" "$round")

  local mstatus mreason
  mstatus=$(jq -r '.status // ""'  "$out/meta.json" 2>/dev/null || echo "")
  mreason=$(jq -r '.reason // ""'  "$out/meta.json" 2>/dev/null || echo "")
  local infra=0
  [ "$mstatus" = INFRA_FAIL ] && infra=1

  if [ ! -s "$out/result.json" ] && [ "$infra" = 0 ]; then
    echo "skip $task/$arm/$round (no result)"; return 0
  fi

  local wt; wt=$(cat "$out/worktree.path" 2>/dev/null || echo "")
  if [ ! -d "$wt" ] && [ "$infra" = 0 ]; then
    echo "skip $task/$arm/$round (worktree gone)"; return 0
  fi

  local files="" diff_loc=0 grade_dir="" cleanup_dir=""
  local oos=0 oos_list="" guard=ok
  local regression=n/a passed=0 total=0 pass_rate=0

  # An infra cell with no worktree (lane abort) has nothing to diff or grade;
  # one that ran far enough to leave a worktree is still measured, for the record.
  if [ -d "$wt" ]; then
    # 1. what changed ------------------------------------------------------
    case "$task" in
      MEM-A|MEM-B)
        local base head
        base=$(cat "$out/base-commit.txt"); head=$(cat "$out/commit.txt")
        git -C "$wt" diff "$base" "$head" -- . "${NOISE[@]}" > "$out/diff.txt"
        diff_loc=$(git -C "$wt" diff --numstat "$base" "$head" -- . "${NOISE[@]}" \
          | awk '{a+=$1; d+=$2} END {print (a+d)+0}')
        files=$(git -C "$wt" diff --name-only "$base" "$head" -- . "${NOISE[@]}")
        # grade in a throwaway checkout of the session's commit, not the live clone
        grade_dir="$WT_ROOT/score-$task-$arm-$round"; cleanup_dir="$grade_dir"
        rm -rf "$grade_dir"; mkdir -p "$grade_dir"
        git -C "$wt" archive "$head" | tar -x -C "$grade_dir"
        cp -Rc "$BENCH_ROOT/node_modules" "$grade_dir/node_modules" 2>/dev/null \
          || cp -R "$BENCH_ROOT/node_modules" "$grade_dir/node_modules"
        sed "s|DB_FILE|score.db|" "$grade_dir/.env.example" > "$grade_dir/.env"
        ( cd "$grade_dir" && DATABASE_URL="file:./score.db" \
            npx prisma db push --force-reset --skip-generate >/dev/null 2>&1 )
        ;;
      *)
        rm -rf "$wt/test/acceptance"   # a re-score must not grade last score's copy
        git -C "$wt" add -A >/dev/null 2>&1
        git -C "$wt" diff --cached -- . "${NOISE[@]}" > "$out/diff.txt"
        diff_loc=$(git -C "$wt" diff --cached --numstat -- . "${NOISE[@]}" \
          | awk '{a+=$1; d+=$2} END {print (a+d)+0}')
        files=$(git -C "$wt" diff --cached --name-only -- . "${NOISE[@]}")
        grade_dir="$wt"
        ;;
    esac

    # 2. out-of-scope files (agent-runtime bookkeeping is not role bleed) --
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      case "$f" in .omc/*|.claude/*|.claude.json|.team-irfan/*|.tg-bench/*|CLAUDE.md.backup*) continue ;; esac
      local hit=0
      while IFS= read -r pat; do
        [ -z "$pat" ] && continue
        # shellcheck disable=SC2053
        [[ "$f" == $pat ]] && hit=1 && break
      done < "$H/tasks/$task/scope.allowlist"
      [ "$hit" = 0 ] && { oos=$((oos+1)); oos_list="$oos_list $f"; }
    done <<< "$files"
    echo "$oos_list" | tr ' ' '\n' | sed '/^$/d' > "$out/out-of-scope.txt"

    # 3. protected test guard ----------------------------------------------
    local p
    for p in $(protected_for "$task"); do
      if echo "$files" | grep -qx "$p"; then guard="edited:$p"; break; fi
    done

    # 4/5. gates and hidden acceptance — Q1 is judged on its diff alone ----
    if [ "$task" = Q1 ]; then
      jq -r '.result // ""' "$out/result.json" > "$out/answer.md" 2>/dev/null || : > "$out/answer.md"
      total=1
      [ "$diff_loc" = 0 ] && [ -z "$(echo "$files" | sed '/^$/d')" ] && passed=1
      pass_rate=$passed
    else
      regression=pass
      ( cd "$grade_dir" && npx vitest run test ) > "$out/regression-tests.log" 2>&1 || regression=fail
      ( cd "$grade_dir" && npm run build ) > "$out/build.log" 2>&1 || regression=fail
      ( cd "$grade_dir" && npm run lint )  > "$out/lint.log"  2>&1 || regression=fail

      mkdir -p "$grade_dir/test/acceptance"
      cp "$H/tasks/$task/hidden/"*.spec.ts "$grade_dir/test/acceptance/"
      ( cd "$grade_dir" && npx vitest run test/acceptance --reporter=json \
          --outputFile="$out/acceptance.json" ) > "$out/acceptance.log" 2>&1 || true

      passed=$(jq -r '.numPassedTests // 0' "$out/acceptance.json" 2>/dev/null || echo 0)
      total=$(jq -r '.numTotalTests // 0'  "$out/acceptance.json" 2>/dev/null || echo 0)
      if [ "$total" -gt 0 ]; then
        pass_rate=$(awk -v p="$passed" -v t="$total" 'BEGIN{printf "%.4f", p/t}')
      fi
      if [ "$regression" = fail ] || [ "$guard" != ok ]; then pass_rate=0; fi
    fi
  fi

  # 6. cost, tokens, transcript fields -------------------------------------
  # collect.sh handles a missing result.json itself: it falls back to the
  # watcher's running estimate in meta, which is all a budget-killed cell left.
  local sid="" jsonl="" cost_source=result
  "$H/bin/collect.sh" "$task" "$arm" "$round" > "$out/metrics.json"
  if [ -s "$out/result.json" ]; then
    sid=$(jq -r '.session_id // ""' "$out/result.json")
  else
    cost_source=watch
  fi
  [ -n "$sid" ] || sid=$(jq -r '.session_id // ""' "$out/meta.json" 2>/dev/null || echo "")
  jsonl=$(transcript_for "$arm" "$sid")

  if [ -s "$out/result.json" ]; then
    local -a args=(--result "$out/result.json" --meta "$out/meta.json" --worktree "$wt")
    [ -n "$jsonl" ] && args+=(--transcript "$jsonl")
    [ -f "$H/tasks/$task/bugfile.txt" ] && args+=(--bug-file "$(cat "$H/tasks/$task/bugfile.txt")")
    python3 "$H/bin/extract.py" "${args[@]}" > "$out/extract.json"
  else
    echo "$NULL_EXTRACT" > "$out/extract.json"
  fi

  # 7. validity: an infra cell measures the harness, not the arm ------------
  local validity=valid reason="$mreason"
  if [ "$infra" = 1 ]; then
    validity=infra
    [ -n "$reason" ] || reason=INFRA_FAIL
  elif [ "$arm" = team ] && [ -z "$jsonl" ]; then
    # no transcript = no evidence of what team-irfan did. Not a silent pass.
    validity=infra; reason=transcript-missing
  elif [ "$arm" = team ] \
       && grep -qE 'ROUTE: (FULL|FAST)' "$jsonl" 2>/dev/null \
       && [ ! -e "$wt/.tg-bench/driver-heartbeat" ]; then
    # team routed to a pipeline but the headless driver never fired: the run
    # measured a broken harness, not team-irfan.
    validity=infra; reason=driver-absent
  fi

  # 8. false_done: the arm said done AND the hidden acceptance disagrees ----
  local claims_done false_done hidden_ok
  claims_done=$(jq -r '.claims_done' "$out/extract.json")
  hidden_ok=$(awk -v pr="$pass_rate" 'BEGIN{print (pr==1)?1:0}')
  false_done=false
  [ "$claims_done" = true ] && [ "$hidden_ok" = 0 ] && false_done=true
  [ "$validity" = infra ] && false_done=false

  # 9. three-state cell + why it failed ------------------------------------
  local cell_status failure_mode=""
  if [ "$validity" = infra ]; then
    cell_status=INFRA_FAIL; failure_mode="$reason"
  elif [ "$hidden_ok" = 1 ]; then
    cell_status=PASS
  else
    cell_status=FAIL
    if [ "$arm" = team ]; then
      local drv="$wt/.team-irfan/.driver/$sid.count" blocks=0
      [ -s "$drv" ] && blocks=$(tr -dc '0-9' < "$drv")
      if [ -n "$jsonl" ] && grep -q 'ROUTE: FULL' "$jsonl" 2>/dev/null \
         && ! compgen -G "$wt/.team-irfan/handoffs/*.md" >/dev/null; then
        failure_mode=persistence
      elif [ -n "$jsonl" ] && grep -q 'ROUTE: FAST' "$jsonl" 2>/dev/null \
           && ! grep -q 'Verdict:' "$jsonl" 2>/dev/null; then
        failure_mode=persistence
      elif [ "${blocks:-0}" -ge 25 ] 2>/dev/null; then
        failure_mode=persistence
      fi
    fi
    [ -z "$failure_mode" ] && [ "$mstatus" = "capped(turns)" ] && failure_mode=capped
  fi

  # 10. one row ------------------------------------------------------------
  local status="${mstatus:-?}"
  local git_sha plugin_version model effort tier_c
  git_sha=$(jq -r '.git_sha // ""'        "$out/meta.json" 2>/dev/null || echo "")
  plugin_version=$(jq -r '.plugin_version // ""' "$out/meta.json" 2>/dev/null || echo "")
  model=$(jq -r '.model // ""'            "$out/meta.json" 2>/dev/null || echo "")
  effort=$(jq -r '.effort // ""'          "$out/meta.json" 2>/dev/null || echo "")
  tier_c=$(jq -r '.tier // ""'            "$out/meta.json" 2>/dev/null || echo "")
  [ -n "$tier_c" ] || tier_c="$TIER"

  local row; row="$(jq -r --arg task "$task" --arg arm "$arm" --arg round "$round" --arg st "$status" \
        --arg pr "$pass_rate" --arg passed "$passed" --arg total "$total" \
        --arg reg "$regression" --arg guard "$guard" --arg oos "$oos" --arg dl "$diff_loc" \
        --arg fd "$false_done" --slurpfile x "$out/extract.json" \
        --arg tier "$tier_c" --arg sha "$git_sha" --arg pv "$plugin_version" \
        --arg model "$model" --arg effort "$effort" --arg sid "$sid" \
        --arg validity "$validity" --arg reason "$reason" \
        --arg cs "$cell_status" --arg fm "$failure_mode" --arg csrc "$cost_source" '
    ($x[0]) as $X |
    [$task,$arm,$round,$st,$pr,$passed,$total,$reg,$guard,$oos,$dl,
     (.cost_usd|tostring),(.tokens_in|tostring),(.tokens_out|tostring),
     (.tool_calls|tostring),(.num_turns|tostring),(.wall_sec|tostring),
     ($X.verified_before_done|tostring),($X.claims_done|tostring),$fd,
     ($X.rework_loops|tostring),($X.plan_exists|tostring),
     ($X.predicted_calls|tostring),($X.actual_calls|tostring),
     ($X.prediction_error|tostring),($X.plan_adherence|tostring),
     ($X.replans|tostring),($X.calls_to_locate|tostring),
     $tier,$sha,$pv,$model,$effort,$sid,$validity,$reason,$cs,$fm,$csrc] | @csv
  ' "$out/metrics.json")"

  csv_put "$task" "$arm" "$round" "$row"

  [ -n "$cleanup_dir" ] && rm -rf "$cleanup_dir"
  echo "[$task/$arm/$round] $cell_status pass=$passed/$total regression=$regression guard=$guard oos=$oos false_done=$false_done validity=$validity${reason:+ ($reason)}${failure_mode:+ mode=$failure_mode}"
}

mkdir -p "$RES"
if [ -s "$CSV" ] && [ "$(head -1 "$CSV")" != "$HEADER" ]; then
  die "$CSV has a different header (legacy 28-column schema?) — move it aside; per-tier CSVs are written fresh"
fi

if [ "${1:-}" = "all" ]; then
  for d in "$RUNS"/*/*/*; do
    [ -d "$d" ] || continue
    round=$(basename "$d"); arm=$(basename "$(dirname "$d")")
    task=$(basename "$(dirname "$(dirname "$d")")")
    case "$task" in Q1|F1|N5|B1|MEM-A|MEM-B) score_cell "$task" "$arm" "$round" ;; esac
  done
elif [ $# -eq 3 ]; then
  score_cell "$1" "$2" "$3"
else
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1
fi
echo "csv: $CSV"
