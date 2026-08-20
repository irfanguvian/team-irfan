#!/usr/bin/env bash
# Scores finished runs. Deterministic: every number here comes from a command or
# from extract.py. Zero LLM — the pairwise quality review lives in judge.sh.
#
#   score.sh <task> <arm> <round>   score one cell
#   score.sh all                    score every cell that has a result.json
#
# Order matters: the regression gate runs BEFORE the hidden tests are copied in.
# A run that fails the gate, or edited a protected test file, scores pass_rate 0
# whatever its acceptance result was. Q1 is special: ANY source diff is a fail —
# it is a question, not a change request.
#
# MEM cells are scored from the commits run.sh recorded, in a throwaway checkout
# — never in the live clone, which session B may still need pristine.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_ROOT="${BENCH_ROOT:-$HOME/team-irfan-bench-v4}"
WT_ROOT="${WT_ROOT:-$HOME/team-irfan-bench-v4-wt}"
CSV="$H/results/results.csv"

NOISE=(':(exclude).omc' ':(exclude).claude' ':(exclude).claude.json' ':(exclude).team-irfan')

protected_for() {
  case "$1" in
    N5) echo "test/invoices.contract.spec.ts test/customers.contract.spec.ts test/refunds.contract.spec.ts test/audit.contract.spec.ts test/reports.overview.contract.spec.ts" ;;
    B1) echo "test/reports.spec.ts" ;;
    MEM-A) echo "test/reports.overview.contract.spec.ts" ;;
    MEM-B) echo "test/customers.contract.spec.ts" ;;
    *) echo "" ;;
  esac
}

score_cell() {
  local task=$1 arm=$2 round=$3
  local out="$H/runs/$task/$arm/$round"
  [ -s "$out/result.json" ] || { echo "skip $task/$arm/$round (no result)"; return 0; }

  local wt grade_dir cleanup_dir=""
  wt=$(cat "$out/worktree.path" 2>/dev/null || echo "")
  [ -d "$wt" ] || { echo "skip $task/$arm/$round (worktree gone)"; return 0; }

  # 1. what changed --------------------------------------------------------
  local files diff_loc
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

  # 2. out-of-scope files (agent-runtime bookkeeping is not role bleed) ----
  local oos=0 oos_list=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in .omc/*|.claude/*|.claude.json|.team-irfan/*|CLAUDE.md.backup*) continue ;; esac
    local hit=0
    while IFS= read -r pat; do
      [ -z "$pat" ] && continue
      # shellcheck disable=SC2053
      [[ "$f" == $pat ]] && hit=1 && break
    done < "$H/tasks/$task/scope.allowlist"
    [ "$hit" = 0 ] && { oos=$((oos+1)); oos_list="$oos_list $f"; }
  done <<< "$files"
  echo "$oos_list" | tr ' ' '\n' | sed '/^$/d' > "$out/out-of-scope.txt"

  # 3. protected test guard ------------------------------------------------
  local guard=ok p
  for p in $(protected_for "$task"); do
    if echo "$files" | grep -qx "$p"; then guard="edited:$p"; break; fi
  done

  # 4/5. gates and hidden acceptance — Q1 is judged on its diff alone ------
  local regression=pass passed=0 total=0 pass_rate=0
  if [ "$task" = Q1 ]; then
    jq -r '.result // ""' "$out/result.json" > "$out/answer.md"
    total=1
    [ "$diff_loc" = 0 ] && [ -z "$(echo "$files" | sed '/^$/d')" ] && passed=1
    pass_rate=$passed
    regression=n/a
  else
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

  # 6. cost, tokens, transcript fields -------------------------------------
  "$H/bin/collect.sh" "$task" "$arm" "$round" > "$out/metrics.json"

  local sid jsonl
  sid=$(jq -r '.session_id // ""' "$out/result.json")
  jsonl=$(find "$H/configs/$arm/projects" -name "$sid.jsonl" 2>/dev/null | head -1)
  local -a xargs=(--result "$out/result.json" --meta "$out/meta.json" --worktree "$wt")
  [ -n "$jsonl" ] && xargs+=(--transcript "$jsonl")
  [ -f "$H/tasks/$task/bugfile.txt" ] && xargs+=(--bug-file "$(cat "$H/tasks/$task/bugfile.txt")")
  python3 "$H/bin/extract.py" "${xargs[@]}" > "$out/extract.json"

  # 7. false_done: the arm said done AND the hidden acceptance disagrees ----
  local claims_done false_done hidden_ok
  claims_done=$(jq -r '.claims_done' "$out/extract.json")
  hidden_ok=$(awk -v pr="$pass_rate" 'BEGIN{print (pr==1)?1:0}')
  false_done=false
  [ "$claims_done" = true ] && [ "$hidden_ok" = 0 ] && false_done=true

  # 8. one row -------------------------------------------------------------
  local status; status=$(jq -r '.status // "?"' "$out/meta.json" 2>/dev/null || echo "?")
  jq -r --arg task "$task" --arg arm "$arm" --arg round "$round" --arg st "$status" \
        --arg pr "$pass_rate" --arg passed "$passed" --arg total "$total" \
        --arg reg "$regression" --arg guard "$guard" --arg oos "$oos" --arg dl "$diff_loc" \
        --arg fd "$false_done" --slurpfile x "$out/extract.json" '
    ($x[0]) as $X |
    [$task,$arm,$round,$st,$pr,$passed,$total,$reg,$guard,$oos,$dl,
     (.cost_usd|tostring),(.tokens_in|tostring),(.tokens_out|tostring),
     (.tool_calls|tostring),(.num_turns|tostring),(.wall_sec|tostring),
     ($X.verified_before_done|tostring),($X.claims_done|tostring),$fd,
     ($X.rework_loops|tostring),($X.plan_exists|tostring),
     ($X.predicted_calls|tostring),($X.actual_calls|tostring),
     ($X.prediction_error|tostring),($X.plan_adherence|tostring),
     ($X.replans|tostring),($X.calls_to_locate|tostring)] | @csv
  ' "$out/metrics.json" >> "$CSV"

  [ -n "$cleanup_dir" ] && rm -rf "$cleanup_dir"
  echo "[$task/$arm/$round] pass=$passed/$total regression=$regression guard=$guard oos=$oos false_done=$false_done"
}

mkdir -p "$H/results"
if [ ! -s "$CSV" ]; then
  echo 'task,arm,round,status,pass_rate,passed,total,regression,guard,oos_files,diff_loc,cost_usd,tokens_in,tokens_out,tool_calls,num_turns,wall_sec,verified_before_done,claims_done,false_done,rework_loops,plan_exists,predicted_calls,actual_calls,prediction_error,plan_adherence,replans,calls_to_locate' > "$CSV"
fi

if [ "${1:-}" = "all" ]; then
  for d in "$H"/runs/*/*/*; do
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
