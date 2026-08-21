#!/usr/bin/env bash
# Push, don't poll. The operator starts one matrix and gets told how it ends.
#
#   notify.sh <event> ['<json>']
#
# events: cell-done      batched — appended to results/<tier>/notify.pending and
#                        flushed only when the last flush is older than
#                        TEAM_IRFAN_NOTIFY_MIN_GAP seconds (default 600)
#         lane-abort | matrix-done | matrix-abort   flushed immediately
#
# A flush carries `batched`: how many cell-done events piled up in
# notify.pending since the last one, so nothing is silently dropped.
#
# The optional JSON is merged into the payload (run.sh passes {last:{...}} and,
# for matrix-done, {report:"..."}).
#
# Transport: TEAM_IRFAN_NOTIFY_URL set -> one-line JSON POSTed with curl (10 s
# cap); unset -> appended to results/<tier>/notifications.log. Every step is
# best-effort: this script never fails a run, never blocks it, always exits 0.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$H/bin/lib.sh"

event="${1:-cell-done}"
extra="${2:-}"; [ -n "$extra" ] || extra='{}'
gap="${TEAM_IRFAN_NOTIFY_MIN_GAP:-600}"
[ -d "$RES" ] || exit 0
jq -e . >/dev/null 2>&1 <<< "$extra" || extra='{}'

pending="$RES/notify.pending"
lastf="$RES/.notify-last"
lock="$RES/.notify.lock"

# Three lanes append here. mkdir lock, and a caller that cannot get it within a
# second gives up rather than blocking a cell.
hold() {
  local n=0
  while [ "$n" -lt 5 ]; do
    mkdir "$lock" 2>/dev/null && return 0
    n=$((n + 1)); sleep 0.2
  done
  return 1
}
hold || exit 0
trap 'rm -rf "$lock" 2>/dev/null' EXIT

flush=1
if [ "$event" = cell-done ]; then
  printf '%s\n' "$extra" >> "$pending" 2>/dev/null
  if [ -f "$lastf" ]; then
    now=$(date +%s)
    mtime=$(stat -f %m "$lastf" 2>/dev/null || stat -c %Y "$lastf" 2>/dev/null || echo 0)
    [ $((now - mtime)) -ge "$gap" ] || flush=0
  fi
fi
[ "$flush" = 1 ] || exit 0
batched=$(cat "$pending" 2>/dev/null | wc -l | tr -d ' ')

stats=$(bash "$H/bin/progress.sh" --json "$TIER" 2>/dev/null)
[ -n "$stats" ] || stats='{}'
payload=$(jq -c --arg event "$event" --arg ts "$(now_iso)" --argjson extra "$extra" \
     --argjson batched "${batched:-0}" '
  { tier: .tier, event: $event, done: .done, total: .total, infra: .infra,
    cost: ((.cost // 0)*100|round/100), eta_min: .eta_min, phase: .phase,
    batched: $batched, last: .last, ts: $ts } + $extra' <<< "$stats" 2>/dev/null)
[ -n "$payload" ] || exit 0

if [ -n "${TEAM_IRFAN_NOTIFY_URL:-}" ]; then
  printf '%s' "$payload" \
    | curl -fsS -m 10 -X POST -H 'content-type: application/json' -d @- \
           "$TEAM_IRFAN_NOTIFY_URL" >/dev/null 2>&1 || true
else
  printf '%s\n' "$payload" >> "$RES/notifications.log" 2>/dev/null || true
fi
: > "$pending" 2>/dev/null || true
: > "$lastf" 2>/dev/null || true
exit 0
