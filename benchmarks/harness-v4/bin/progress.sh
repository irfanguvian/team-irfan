#!/usr/bin/env bash
# The operator's window into a running matrix. Zero LLM, reads only files.
#
#   progress.sh [tier]          rewrite results/<tier>/PROGRESS.md (atomic)
#   progress.sh --json [tier]   print the same numbers as JSON, write nothing
#
# Inputs: results/<tier>/{ledger.jsonl,matrix.json,.phase,DONE,ABORTED} and
# runs/<tier>/.current-<lane> (one line "<task>/<arm>/<round> <started_at>"
# written by run.sh while a cell is in flight). Never reads a transcript, never
# asks a model anything.
#
# run.sh calls this after every cell; three lanes can race, so the rewrite sits
# behind a mkdir lock. A lock older than 30 s is assumed dead and stolen.
set -uo pipefail

JSON=0
if [ "${1:-}" = "--json" ]; then JSON=1; shift; fi
[ -n "${1:-}" ] && export BENCH_TIER="$1"

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$H/bin/lib.sh"

led="$RES/ledger.jsonl"; [ -s "$led" ] || led=/dev/null
mat="$RES/matrix.json"

arms="$(jq -r '.arms[]?' "$mat" 2>/dev/null)"; [ -n "$arms" ] || arms="$ARMS_ALL"
tasks="$(jq -r '.tasks[]?' "$mat" 2>/dev/null)"; [ -n "$tasks" ] || tasks="$TASKS_ALL"

# Per-arm cell totals: rounds_for is the single source of how many rounds a task gets.
per_arm=0
for t in $tasks; do per_arm=$((per_arm + $(rounds_for "$t"))); done
totals='{}'
for a in $arms; do
  totals=$(jq -c --arg a "$a" --argjson n "$per_arm" '.[$a]=$n' <<< "$totals")
done

# In-flight cells, one file per lane.
current='{}'
for f in "$RUNS"/.current-*; do
  [ -f "$f" ] || continue
  read -r cell started < "$f" || continue
  [ -n "${cell:-}" ] || continue
  arm=$(cut -d/ -f2 <<< "$cell")
  current=$(jq -c --arg a "$arm" --arg c "$cell" --arg s "${started:-}" \
              '.[$a]={cell:$c,started:$s}' <<< "$current")
done

phase=$(cat "$RES/.phase" 2>/dev/null || echo unknown)
[ -f "$RES/DONE" ] && phase="done"
[ -f "$RES/ABORTED" ] && phase="aborted"

stats=$(jq -s --argjson totals "$totals" --argjson current "$current" \
     --arg tier "$TIER" --arg phase "$phase" \
     --arg started "$(jq -r '.started_at // ""' "$mat" 2>/dev/null)" \
     --arg sha "$(jq -r '.git_sha // ""' "$mat" 2>/dev/null)" \
     --arg pv "$(jq -r '.plugin_version // ""' "$mat" 2>/dev/null)" \
     --arg model "$MODEL" --arg effort "$EFFORT" '
  ([ to_entries[] | .value + {i:.key,
       k:(.value.task+"/"+.value.arm+"/"+.value.round)} ]) as $all
  | ($all | group_by(.k) | map(max_by([.ts,.i]))) as $c
  | { tier:$tier, phase:$phase, started_at:$started, git_sha:$sha,
      plugin_version:$pv, model:$model, effort:$effort,
      total: ([$totals[]] | add // 0),
      done:  ($c | length),
      infra: ([$c[] | select(.status=="INFRA_FAIL")] | length),
      cost:  ([$c[].cost_usd] | add // 0),
      last:  (($all | max_by([.ts,.i])) | if . == null then null else
               {cell:(.task+"/"+.arm+"/"+.round), status:.status,
                reason:.reason, cost:.cost_usd, ts:.ts} end),
      infra_cells: [ $c[] | select(.status=="INFRA_FAIL")
                     | {cell:(.task+"/"+.arm+"/"+.round), reason:.reason} ],
      arms: [ ($totals|keys_unsorted)[] as $a
              | ($c | map(select(.arm==$a))) as $ca
              | ($ca | map(.wall_sec) | sort) as $w
              | (if ($w|length)==0 then 0 else $w[(($w|length)/2)|floor] end) as $med
              | ([$totals[$a] - ($ca|length), 0] | max) as $rem
              | { arm:$a, done:($ca|length), total:$totals[$a],
                  infra: ([$ca[]|select(.status=="INFRA_FAIL")]|length),
                  cost: ([$ca[].cost_usd] | add // 0),
                  median_wall: $med, remaining: $rem,
                  eta_min: (($rem * $med / 60) | floor),
                  last: (($ca | max_by([.ts,.i])) | if . == null then null else
                          {cell:(.task+"/"+.arm+"/"+.round), status:.status,
                           cost:.cost_usd} end),
                  current: ($current[$a].cell // null),
                  current_started: ($current[$a].started // null) } ] }
  | . + {eta_min: ([.arms[].eta_min] | max // 0)}
' "$led" 2>/dev/null)
[ -n "$stats" ] || stats='{}'

if [ "$JSON" = 1 ]; then printf '%s\n' "$stats"; exit 0; fi

[ -d "$RES" ] || exit 0
lock="$RES/.progress.lock"
if ! mkdir "$lock" 2>/dev/null; then
  now=$(date +%s)
  mtime=$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo "$now")
  # Fresh lock: another lane is writing the same numbers. Let it.
  [ $((now - mtime)) -gt 30 ] || exit 0
  rmdir "$lock" 2>/dev/null
  mkdir "$lock" 2>/dev/null || exit 0
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT

tmp="$RES/PROGRESS.md.tmp.$$"
{
  jq -r '
    "# Bench progress — tier \(.tier)",
    "",
    "- phase: **\(.phase)**   ·   started: \(.started_at // "?")   ·   updated: '"$(now_iso)"'",
    "- model: \(.model) / effort \(.effort)   ·   sha: \(.git_sha // "?")   ·   plugin: \(.plugin_version // "?")",
    "- cells: **\(.done)/\(.total)** done   ·   infra: \(.infra)   ·   cost so far: $\(.cost*100|round/100)   ·   ETA \(.eta_min) min",
    "",
    "| arm | done | infra | cost | median wall | ETA | in flight | last cell |",
    "|---|---|---|---|---|---|---|---|",
    ( .arms[] |
      "| \(.arm) | \(.done)/\(.total) | \(.infra) | $\(.cost*100|round/100) | \(.median_wall)s | \(.eta_min)m | \(if .current then "\(.current) (since \(.current_started))" else "—" end) | \(if .last then "\(.last.cell) \(.last.status) $\(.last.cost*100|round/100)" else "—" end) |"),
    "",
    (if (.infra_cells|length) > 0 then
       "## INFRA_FAIL cells (excluded from every claim)\n",
       (.infra_cells[] | "- `\(.cell)` — \(.reason // "?")")
     else "No infra failures." end),
    ""
  ' <<< "$stats"
  echo "_Regenerated by bin/progress.sh after every cell. Never edit by hand._"
} > "$tmp" 2>/dev/null && mv "$tmp" "$RES/PROGRESS.md"
rm -f "$tmp"
exit 0
