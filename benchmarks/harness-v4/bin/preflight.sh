#!/usr/bin/env bash
# Is this machine fit to run this cell? Zero LLM, spawns no agent.
#
#   preflight.sh <task> <arm> <round> <worktree>
#
# arm team: the repo's own doctor must PASS, in fast mode so it cannot recurse
#           into run-checks. A team cell run against a broken install measures
#           the install, not team-irfan.
# arm bare/omc: nothing to check.
#
# Always writes runs/<tier>/<task>/<arm>/<round>/preflight.json. Exit 1 = refuse
# the cell; run.sh turns that into INFRA_FAIL reason=preflight:doctor and spawns
# no process, so the cell costs $0.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$H/bin/lib.sh"

[ $# -ge 4 ] || die "usage: preflight.sh <task> <arm> <round> <worktree>"
task=$1 arm=$2 round=$3 wt=$4
out=$(cell_dir "$task" "$arm" "$round")
mkdir -p "$out" || die "cannot create $out"
REPO="$(git -C "$H" rev-parse --show-toplevel 2>/dev/null || echo "$H")"

emit() {  # status check rc detail
  jq -n --arg arm "$arm" --arg status "$1" --arg check "$2" --argjson rc "$3" \
        --arg detail "$4" --arg worktree "$wt" --arg ts "$(now_iso)" \
     '{arm:$arm,status:$status,check:$check,rc:$rc,detail:$detail,
       worktree:$worktree,ts:$ts}' > "$out/preflight.json.tmp" \
    && mv "$out/preflight.json.tmp" "$out/preflight.json"
}

if [ "$arm" != team ]; then emit noop none 0 ""; exit 0; fi

log="$(TG_DOCTOR_FAST=1 bash "$REPO/hooks/doctor.sh" "$REPO/hooks/hooks.json" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ]; then
  emit ok doctor 0 "$(printf '%s' "$log" | tail -1)"
  exit 0
fi
emit fail doctor "$rc" "$(printf '%s' "$log" | grep -E '^ *FAIL' | head -5 | tr '\n' ';')"
echo "preflight: doctor FAIL for $task/$arm/$round" >&2
printf '%s\n' "$log" >&2
exit 1
