#!/usr/bin/env bash
# Turns one finished run into numbers. Reads only files on disk; spawns nothing.
#
#   collect.sh T1 bare 1   ->  json on stdout   (cell dir per BENCH_TIER)
#
# Primary cost is `total_cost_usd` straight out of Claude Code's own JSON result,
# which already prices whatever model mix the run used — including an arm C run's
# subagents. `cost_recomputed_usd` re-derives it from the session transcript and
# pricing.json; if the two disagree by much, trust the first and fix the second.
set -uo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
task=$1 arm=$2 round=$3
out="$(cell_dir "$task" "$arm" "$round")"
res="$out/result.json"

# An INFRA_FAIL cell may have no result.json at all: a lane abort never spawned
# a process, a budget kill never let it print. score.sh still writes it a row.
# Cost then falls back to the watcher's running estimate in meta (0 for a lane
# abort, the real spend for a budget kill) — approximate, and the only number
# that exists once the process was killed before it could report.
if [ ! -s "$res" ]; then
  jq -n --slurpfile meta "$out/meta.json" '
    ($meta[0] // {}) as $M
    | ($M.cost_usd_watch // 0) as $c
    | {cost_usd:$c, cost_recomputed_usd:$c, tokens_in:0, tokens_out:0,
       cache_read:0, cache_write:0, tool_calls:0, num_turns:0,
       wall_sec: ($M.wall_sec // 0), models: [], session_id: ($M.session_id // "")}'
  exit 0
fi

sid=$(jq -r '.session_id // ""' "$res")
jsonl=$(find "$H/configs/$arm/projects" -name "$sid.jsonl" 2>/dev/null | head -1)

# Per-model token totals, so a mixed-model run is priced per model rather than
# at one blended rate.
if [ -n "$jsonl" ]; then
  per_model=$(jq -s '
    [ .[] | select(.type=="assistant") | .message
      | select(.usage) | {model: (.model // "unknown"), u: .usage} ]
    | group_by(.model)
    | map({ model: .[0].model,
            input:  (map(.u.input_tokens              // 0) | add),
            output: (map(.u.output_tokens             // 0) | add),
            cache_read:  (map(.u.cache_read_input_tokens     // 0) | add),
            cache_write: (map(.u.cache_creation_input_tokens // 0) | add) })
  ' "$jsonl")
  tool_calls=$(jq -s '[ .[] | select(.type=="assistant") | .message.content // []
                        | .[]? | select(.type=="tool_use") ] | length' "$jsonl")
else
  per_model='[]'; tool_calls=0
fi

recomputed=$(jq -n --argjson m "$per_model" --slurpfile p "$H/pricing.json" '
  [ $m[] | . as $x | ($p[0][$x.model] // $p[0]["default"] // {in:0,out:0,cache_read:0,cache_write:0}) as $r
    | $x.input * $r["in"] / 1e6
    + $x.output * $r.out / 1e6
    + $x.cache_read * $r.cache_read / 1e6
    + $x.cache_write * $r.cache_write / 1e6 ] | add // 0')

jq -n \
  --slurpfile r "$res" \
  --slurpfile meta "$out/meta.json" \
  --argjson per_model "$per_model" \
  --argjson tool_calls "$tool_calls" \
  --argjson recomputed "$recomputed" '
  ($r[0]) as $R | ($meta[0] // {}) as $M | {
    cost_usd:  ($R.total_cost_usd // 0),
    cost_recomputed_usd: $recomputed,
    tokens_in:   ([$per_model[].input]  | add // 0),
    tokens_out:  ([$per_model[].output] | add // 0),
    cache_read:  ([$per_model[].cache_read]  | add // 0),
    cache_write: ([$per_model[].cache_write] | add // 0),
    tool_calls: $tool_calls,
    num_turns:  ($R.num_turns // 0),
    wall_sec:   ($M.wall_sec // (($R.duration_ms // 0) / 1000 | floor)),
    models:     [$per_model[].model],
    session_id: ($R.session_id // "")
  }'
