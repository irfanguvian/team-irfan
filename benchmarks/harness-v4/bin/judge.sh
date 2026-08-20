#!/usr/bin/env bash
# Pairwise, blind, order-swapped quality review (claim C5) + the MEM same-hole
# check (claim C4). The only script besides run.sh that spends money.
#
#   judge.sh --calibrate                    gate: 3 planted pairs, both orders each.
#                                           A judge that misses any is not used.
#   judge.sh pair <task> <round> <X> <Y>    judge runs/<task>/{X,Y}/<round>/diff.txt
#   judge.sh all                            every task/round/pairing with two diffs
#   judge.sh same-hole <arm> <round>        did MEM-B fall into the known hole?
#
# The judge never sees arm names, transcripts, or costs. Every pairing is judged
# twice with presentation order swapped; a flip between the two passes is
# recorded as tie (position bias kill). One judge model for the whole matrix:
# JUDGE_MODEL, default claude-opus-5.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_ROOT="${BENCH_ROOT:-$HOME/team-irfan-bench-v4}"
JUDGE_MODEL="${JUDGE_MODEL:-claude-opus-5}"
MAX_DIFF_LINES=400

die() { echo "judge.sh: $*" >&2; exit 1; }

base_tag() {
  case "$1" in
    Q1) echo q1-base ;; F1) echo f1-base ;; N5) echo n5-base ;;
    B1) echo b1-base ;; MEM-A|MEM-B) echo mem-base ;;
    *) die "unknown task $1" ;;
  esac
}

clip() { head -n "$MAX_DIFF_LINES"; }

# one judgment: task-text-file, before-text-file, diff1, diff2 -> "1|2|tie" on stdout
judge_once() {
  local task_f=$1 before_f=$2 diff1_f=$3 diff2_f=$4
  local prompt
  prompt=$(python3 - "$H/judge/prompt.md" "$task_f" "$before_f" "$diff1_f" "$diff2_f" <<'PY'
import sys
tpl, task, before, d1, d2 = [open(p).read() for p in sys.argv[1:6]]
out = tpl.replace('{TASK}', task).replace('{BEFORE}', before)
out = out.replace('{DIFF1}', d1).replace('{DIFF2}', d2)
sys.stdout.write(out)
PY
)
  local rawf; rawf=$(mktemp)
  CLAUDE_CONFIG_DIR="$H/configs/bare" \
    claude -p --output-format json --model "$JUDGE_MODEL" --max-turns 1 \
      --mcp-config "$H/configs/bare/mcp-empty.json" --strict-mcp-config \
      <<< "$prompt" > "$rawf" 2>/dev/null
  python3 - "$rawf" <<'PY'
import json, re, sys
try:
    result = json.load(open(sys.argv[1])).get("result", "")
except Exception:
    print("error"); sys.exit()
m = re.search(r'\{.*\}', result, re.S)
if not m:
    print("error"); sys.exit()
try:
    v = json.loads(m.group(0))
except Exception:
    print("error"); sys.exit()
w = str(v.get("winner", "error")).strip()
print(w if w in ("1", "2", "tie") else "error")
PY
  rm -f "$rawf"
}

# two passes, order swapped. echoes "first|second|final" where final is
# resolved to labels X/Y/tie given the file order (X first).
judge_pair_files() {
  local task_f=$1 before_f=$2 x_f=$3 y_f=$4
  local p1 p2
  p1=$(judge_once "$task_f" "$before_f" "$x_f" "$y_f")   # X as DIFF-1
  p2=$(judge_once "$task_f" "$before_f" "$y_f" "$x_f")   # Y as DIFF-1
  local final=tie
  if [ "$p1" = error ] || [ "$p2" = error ]; then
    final=error
  elif [ "$p1" = 1 ] && [ "$p2" = 2 ]; then final=X
  elif [ "$p1" = 2 ] && [ "$p2" = 1 ]; then final=Y
  elif [ "$p1" = tie ] && [ "$p2" = tie ]; then final=tie
  else final=tie   # disagreement between orders = position-dependent = tie
  fi
  echo "$p1|$p2|$final"
}

# ------------------------------------------------------------------ calibrate
calibrate() {
  local fails=0
  for d in "$H"/judge/calibration/*/; do
    local name expected before tmp
    name=$(basename "$d")
    expected=$(python3 -c "import json;print(json.load(open('$d/meta.json'))['expected'])")
    tmp=$(mktemp)
    for f in $(cd "$d/before" && find . -type f | sort); do
      { echo "### ${f#./}"; echo '```ts'; cat "$d/before/$f"; echo '```'; } >> "$tmp"
    done
    local verdict final
    verdict=$(judge_pair_files "$d/task.md" "$tmp" "$d/diff-A.patch" "$d/diff-B.patch")
    rm -f "$tmp"
    final=${verdict##*|}
    # expected uses labels A/B/tie; final uses X/Y/tie with A passed as X
    local got=$final
    [ "$final" = X ] && got=A
    [ "$final" = Y ] && got=B
    if [ "$got" = "$expected" ]; then
      echo "ok   $name  ($verdict) -> $got"
    else
      echo "FAIL $name  ($verdict) -> $got, wanted $expected"
      fails=$((fails+1))
    fi
  done
  echo
  if [ "$fails" = 0 ]; then
    echo "calibration passed — judge $JUDGE_MODEL usable"
  else
    echo "calibration FAILED ($fails) — fix judge/prompt.md or JUDGE_MODEL before judging anything real"
  fi
  exit "$fails"
}

# ------------------------------------------------------------------ real pair
judge_real() {
  local task=$1 round=$2 x=$3 y=$4
  local dx="$H/runs/$task/$x/$round/diff.txt" dy="$H/runs/$task/$y/$round/diff.txt"
  [ -s "$dx" ] || { echo "skip $task r$round $x-vs-$y (no diff for $x)"; return 0; }
  [ -s "$dy" ] || { echo "skip $task r$round $x-vs-$y (no diff for $y)"; return 0; }
  [ -d "$BENCH_ROOT/.git" ] || die "no fixture repo — bin/init.sh first"

  local tag before xa ya
  tag=$(base_tag "$task")
  before=$(mktemp); xa=$(mktemp); ya=$(mktemp)
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    { echo "### $f"; echo '```ts'; git -C "$BENCH_ROOT" show "$tag:$f" 2>/dev/null; echo '```'; } >> "$before"
  done < "$H/tasks/$task/judge.files"
  clip < "$dx" > "$xa"; clip < "$dy" > "$ya"

  local verdict final winner
  verdict=$(judge_pair_files "$H/tasks/$task/PROMPT.md" "$before" "$xa" "$ya")
  rm -f "$before" "$xa" "$ya"
  final=${verdict##*|}
  case "$final" in X) winner=$x ;; Y) winner=$y ;; *) winner=$final ;; esac

  mkdir -p "$H/results/judgments"
  jq -n --arg t "$task" --arg r "$round" --arg x "$x" --arg y "$y" \
        --arg w "$winner" --arg passes "$verdict" --arg model "$JUDGE_MODEL" \
    '{task:$t,round:$r,arms:[$x,$y],winner:$w,passes:$passes,judge_model:$model}' \
    > "$H/results/judgments/$task-r$round-$x-vs-$y.json"
  echo "[$task r$round] $x vs $y -> $winner  ($verdict)"
}

# ------------------------------------------------------------------ same-hole
same_hole() {
  local arm=$1 round=$2
  local out="$H/runs/MEM-B/$arm/$round"
  [ -s "$out/diff.txt" ] || die "no MEM-B diff for $arm/$round — score it first"
  local sid jsonl cmds
  sid=$(jq -r '.session_id // ""' "$out/result.json" 2>/dev/null)
  jsonl=$(find "$H/configs/$arm/projects" -name "$sid.jsonl" 2>/dev/null | head -1)
  cmds=$(mktemp)
  if [ -n "$jsonl" ]; then
    jq -r 'select(.type=="assistant") | .message.content[]? |
           select(.type=="tool_use") | "\(.name): \(.input.command // .input.file_path // "")"' \
      "$jsonl" 2>/dev/null | head -200 > "$cmds"
  else
    echo "(transcript unavailable)" > "$cmds"
  fi

  local prompt raw
  prompt=$(python3 - "$H/judge/same-hole.md" "$cmds" "$out/diff.txt" <<'PY'
import sys
tpl, cmds, diff = [open(p).read() for p in sys.argv[1:4]]
sys.stdout.write(tpl.replace('{COMMANDS}', cmds).replace('{DIFF}', diff[:40000]))
PY
)
  rm -f "$cmds"
  raw=$(CLAUDE_CONFIG_DIR="$H/configs/bare" \
    claude -p --output-format json --model "$JUDGE_MODEL" --max-turns 1 \
      --mcp-config "$H/configs/bare/mcp-empty.json" --strict-mcp-config \
      <<< "$prompt" 2>/dev/null)
  mkdir -p "$H/results/judgments"
  printf '%s' "$raw" | python3 - "$arm" "$round" "$H/results/judgments" <<'PY'
import json, re, sys
arm, rnd, outdir = sys.argv[1:4]
try:
    result = json.load(sys.stdin).get("result", "")
    m = re.search(r'\{.*\}', result, re.S)
    v = json.loads(m.group(0)) if m else {}
except Exception:
    v = {}
rec = {"arm": arm, "round": rnd,
       "same_hole": v.get("same_hole"), "evidence": v.get("evidence", "")}
path = f"{outdir}/same-hole-{arm}-{rnd}.json"
json.dump(rec, open(path, "w"), indent=2)
print(f"[same-hole {arm} r{rnd}] {rec['same_hole']} — {rec['evidence']}")
PY
}

# ------------------------------------------------------------------ dispatch
case "${1:-}" in
  --calibrate) calibrate ;;
  pair) [ $# -eq 5 ] || die "usage: judge.sh pair <task> <round> <armX> <armY>"
        judge_real "$2" "$3" "$4" "$5" ;;
  same-hole) [ $# -eq 3 ] || die "usage: judge.sh same-hole <arm> <round>"
             same_hole "$2" "$3" ;;
  all)
    for task in F1 N5 B1 MEM-A MEM-B; do
      for round in 1 2 3; do
        [ -d "$H/runs/$task" ] || continue
        judge_real "$task" "$round" bare team
        judge_real "$task" "$round" omc team
        judge_real "$task" "$round" bare omc
      done
    done
    for arm in bare omc team; do
      for round in 1 2 3; do
        [ -s "$H/runs/MEM-B/$arm/$round/diff.txt" ] && same_hole "$arm" "$round"
      done
    done
    ;;
  *) sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
