#!/usr/bin/env bash
# Shared bench vocabulary. Sourced by every bin/*.sh; zero side effects.
#
# One tier = one (model, effort) pair, e.g. sonnet-low. Each tier owns its own
# runs/ and results/ subtree so sonnet and haiku matrices never collide:
#
#   runs/<tier>/<task>/<arm>/<round>/      per-cell artifacts (gitignored)
#   results/<tier>/results.csv             the durable record
#   results/<tier>/{judgments,same-hole}/  C5 pairwise + C4 same-hole (script)
#   results/<tier>/{PROGRESS.md,ledger.jsonl,matrix.json,DONE|ABORTED,
#                   notifications.log,notify.pending}
#
# Legacy opus files (results/results.csv, results/judgments/, runs/<task>/...)
# predate tiers and stay where they are; report.py --tier opus-legacy reads them.

H="${H:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BENCH_ROOT="${BENCH_ROOT:-$HOME/team-irfan-bench-v4}"
WT_ROOT="${WT_ROOT:-$HOME/team-irfan-bench-v4-wt}"

MODEL="${BENCH_MODEL:-claude-sonnet-5}"
EFFORT="${BENCH_EFFORT:-low}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"   # selftest injects a fake claude here

tier_from_model() {  # claude-sonnet-5 + low -> sonnet-low
  local m=${1#claude-}
  case "$m" in
    sonnet*) m=sonnet ;; haiku*) m=haiku ;; opus*) m=opus ;; fable*) m=fable ;;
    *) m=${m%%-*} ;;
  esac
  echo "$m-$2"
}
TIER="${BENCH_TIER:-$(tier_from_model "$MODEL" "$EFFORT")}"

if [ "$TIER" = opus-legacy ]; then
  RUNS="$H/runs"; RES="$H/results"
else
  RUNS="$H/runs/$TIER"; RES="$H/results/$TIER"
fi

TASKS_ALL="Q1 F1 B1 N5 MEM-A MEM-B"
ARMS_ALL="bare omc team"

die() { echo "${0##*/}: $*" >&2; exit 1; }
rounds_for() { case "$1" in N5|MEM-A|MEM-B) echo 2 ;; *) echo 3 ;; esac; }
base_tag() {
  case "$1" in
    Q1) echo q1-base ;; F1) echo f1-base ;; N5) echo n5-base ;;
    B1) echo b1-base ;; MEM-A|MEM-B) echo mem-base ;;
    *) die "unknown task $1" ;;
  esac
}
cell_dir() { echo "$RUNS/$1/$2/$3"; }   # task arm round
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Cell result vocabulary (meta.json.status / CSV cell_status):
#   status:  ok | capped(time) | capped(turns) | fail(rc=N) | INFRA_FAIL
#   reason:  "" | plugin-load-failed | lane-aborted:<cause> | budget | budget(wall)
#            | driver-absent | auth/ratelimit | preflight:<check>
#   cell_status (score.sh): PASS | FAIL | INFRA_FAIL
#   validity (score.sh):    valid | infra
# Files a bench session leaves in its worktree cwd (hooks write them):
#   .tg-bench/plugin-loaded     {"version","root","ts"}  SessionStart sentinel (team arm)
#   .tg-bench/driver-heartbeat  empty                    first Stop of headless-driver.sh
