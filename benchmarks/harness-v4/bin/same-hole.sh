#!/usr/bin/env bash
# Did MEM session B fall into the hole session A already dug? (claim C4)
#
#   same-hole.sh <arm> <round>   one MEM pair
#   same-hole.sh all             every MEM-B cell in the tier
#
# Zero LLM. Two independent channels, never mixed:
#
# hits_code — did B reach for a band-aid? The family is a fixed, written-down
#   list (tasks/MEM-B/bandaid.markers) grepped over CODE ONLY:
#     diff        lines ADDED in MEM-B's diff.txt — what B shipped
#     transcript  new content of every Edit/Write/MultiEdit in B's session and
#                 its subagents whose file_path is under src/ or prisma/ —
#                 what B tried, including attempts it backed out of.
#   Prose is excluded on purpose: .team-irfan/**, *.md and comment-only lines
#   never count. Team is the only arm that writes prose artifacts, so counting
#   them would hand C4 a bias against the arm C4 is about.
#
# retro_recorded — did session A record a lesson about this bug class? True when
#   the clone has a file under .team-irfan/memory/** or .team-irfan/handoffs/*.md
#   mentioning MEM-A's bug file or "N+1" (case-insensitive), restricted to files
#   older than session B's start so B cannot supply its own evidence. Markers are
#   deliberately NOT used here: a retro reading "do NOT add a cache" is a lesson
#   recorded, not a band-aid taken. bare/omc have no cross-session memory, so it
#   is always false for them — the asymmetry claim C4 exists to measure.
#
# C4 scoring (report.py): team with retro_recorded AND same_hole = falsified.
set -uo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MARKERS="$H/tasks/MEM-B/bandaid.markers"
[ -s "$MARKERS" ] || die "no markers file: $MARKERS"

# strip diff/JSON leading whitespace, drop comment-only lines
decomment() { sed -E 's/^[[:space:]]+//' | grep -vE '^(//|#|\*|/\*)' || true; }

transcripts_for() {  # arm session_id -> one path per line (session + its subagents)
  [ -n "${2:-}" ] || return 0
  local main
  main=$(find "$H/configs/$1/projects" -name "$2.jsonl" 2>/dev/null | head -1)
  [ -n "$main" ] || return 0
  echo "$main"
  find "${main%.jsonl}/subagents" -name '*.jsonl' 2>/dev/null
}

one() {
  local arm=$1 round=$2
  local out; out=$(cell_dir MEM-B "$arm" "$round")
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  : > "$tmp/diff"; : > "$tmp/transcript"
  [ -s "$out/diff.txt" ] && grep '^+' "$out/diff.txt" | grep -v '^+++' \
    | sed 's/^+//' | decomment > "$tmp/diff"

  local sid
  sid=$(jq -r '.session_id // ""' "$out/result.json" 2>/dev/null || echo "")
  [ -n "$sid" ] || sid=$(jq -r '.session_id // ""' "$out/meta.json" 2>/dev/null || echo "")
  local t
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
           | select(.name=="Edit" or .name=="Write" or .name=="MultiEdit")
           | select((.input.file_path // "") | test("(^|/)(src|prisma)/"))
           | (.input.new_string // empty), (.input.content // empty),
             (.input.edits[]?.new_string // empty)' "$t" 2>/dev/null
  done < <(transcripts_for "$arm" "$sid") | decomment > "$tmp/transcript"

  # ---- hits ---------------------------------------------------------------
  : > "$tmp/hits.tsv"
  local pat where line
  while IFS= read -r pat; do
    case "$pat" in ''|'#'*) continue ;; esac
    for where in diff transcript; do
      line=$(grep -m1 -E "$pat" "$tmp/$where" 2>/dev/null || true)
      [ -n "$line" ] && printf '%s\t%s\t%s\n' \
        "$pat" "$where" "$(printf '%s' "$line" | cut -c1-200)" >> "$tmp/hits.tsv"
    done
  done < "$MARKERS"

  # ---- retro_recorded (team only) — prose channel, markers NOT used -------
  local retro=false method=script
  if [ "$arm" = team ]; then
    local wta; wta=$(cat "$(cell_dir MEM-A "$arm" "$round")/worktree.path" 2>/dev/null || echo "")
    if [ -d "$wta/.team-irfan" ]; then
      # only artifacts that predate session B — B must not vouch for A
      local started; started=$(jq -r '.started_at // ""' "$out/meta.json" 2>/dev/null || echo "")
      local -a age=()
      [ -n "$started" ] && { age=(! -newermt "$started"); method=script,pre-B; }
      find "$wta/.team-irfan/memory" "$wta/.team-irfan/handoffs" \
        -type f ${age[@]+"${age[@]}"} -print0 2>/dev/null > "$tmp/retro.files"
      # "A wrote something down about this bug" = names the buggy file, or N+1
      local bug; bug=$(cat "$H/tasks/MEM-A/bugfile.txt" 2>/dev/null || echo "")
      local lesson="N\\+1|${bug//./\\.}|$(basename "$bug")"
      if [ -s "$tmp/retro.files" ] \
         && xargs -0 grep -laiE "$lesson" < "$tmp/retro.files" 2>/dev/null | grep -q .; then
        retro=true
      fi
    fi
  fi

  local same_hole=false
  [ -s "$tmp/hits.tsv" ] && same_hole=true

  mkdir -p "$RES/same-hole"
  local dest="$RES/same-hole/$arm-r$round.json"
  jq -Rn --arg arm "$arm" --arg round "$round" --argjson sh "$same_hole" \
        --argjson retro "$retro" --arg method "$method" \
        --rawfile hits "$tmp/hits.tsv" '
    {arm:$arm, round:$round, same_hole:$sh,
     hits_code: ($hits | split("\n") | map(select(length>0) | split("\t"))
                  | map({marker:.[0], where:.[1], line:(.[2] // "")})),
     retro_recorded:$retro, method:$method}' > "$dest"

  echo "[same-hole $arm r$round] same_hole=$same_hole retro_recorded=$retro hits=$(wc -l < "$tmp/hits.tsv" | tr -d ' ') -> $dest"
}

case "${1:-}" in
  all)
    for d in "$RUNS"/MEM-B/*/*; do
      [ -d "$d" ] || continue
      one "$(basename "$(dirname "$d")")" "$(basename "$d")"
    done
    ;;
  "") sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1 ;;
  *)  [ $# -eq 2 ] || die "usage: same-hole.sh <arm> <round> | all"
      one "$1" "$2" ;;
esac
