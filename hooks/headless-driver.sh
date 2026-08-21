#!/usr/bin/env bash
# Stop-hook driver for headless team-graph runs. Rigid, zero LLM.
#
# Two haiku matrix runs (2026-08-19, 2026-08-20) proved prompt text cannot
# hold turn persistence: "do not end the turn" was in the router both times
# and the orchestrator still ended it — narrating a delegation it never made
# (T2 r1/r2, T4 r2) or asking a BLOCKING question at an auto-approved gate
# (T3 r2). FUNDAMENTALS applied to the harness itself: deterministic checks
# are never handed to the prompt.
#
#   TEAM_IRFAN_AUTO_APPROVE != 1     → exit 0. Interactive sessions keep both
#                                      human gates; this driver does not exist.
#   no ROUTE: FULL/FAST in transcript → exit 0 (HAND-BACK, QUESTION, or not a
#                                      team-graph session).
#   terminal artifact present         → exit 0. FULL: a file in
#                                      .team-irfan/handoffs/ (STEP 6 writes it;
#                                      headless worktrees start with none).
#                                      FAST: a Verdict: line in the tail of the
#                                      assistant transcript (the 4-question
#                                      report ends with one).
#   otherwise                         → exit 2, marching orders on stderr.
#
# stop_hook_active is deliberately ignored: this is a driver, not a gate — it
# must keep pushing across turns. The per-session counter caps it at 25 blocks
# so a wedged run still terminates instead of looping forever.
#
# Under auto-approve it also touches .tg-bench/driver-heartbeat in cwd — on-disk
# proof for the harness that the hook was loaded and ran at all.

set -uo pipefail

[ "${TEAM_IRFAN_AUTO_APPROVE:-}" = "1" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Proof this driver ran at all. score.sh reads it: a transcript that routed
# FULL/FAST with no heartbeat means the hook never fired, so the cell measured
# an unhooked run, not a team-graph one. Best-effort, never fails the hook.
mkdir -p .tg-bench 2>/dev/null && { [ -e .tg-bench/driver-heartbeat ] || : > .tg-bench/driver-heartbeat; } 2>/dev/null

INPUT=$(cat 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

ASSISTANT=$(jq -r 'select(.type=="assistant")
  | [.message.content[]? | select(.type=="text") | .text] | join("\n")' \
  "$TRANSCRIPT" 2>/dev/null)

ROUTE=$(printf '%s\n' "$ASSISTANT" | grep -oE 'ROUTE: *(FULL|FAST)' | tail -1)
[ -n "$ROUTE" ] || exit 0

case "$ROUTE" in
  *FULL*)
    # STEP 6 writes the handoff; headless worktrees start with none, so any
    # file here means the run reached its terminal step.
    if ls .team-irfan/handoffs/*.md >/dev/null 2>&1; then exit 0; fi ;;
  *FAST*)
    if printf '%s\n' "$ASSISTANT" | tail -40 | grep -q 'Verdict:'; then exit 0; fi ;;
esac

COUNT_DIR=".team-irfan/.driver"
COUNT_FILE="$COUNT_DIR/$SESSION.count"
mkdir -p "$COUNT_DIR" 2>/dev/null || exit 0
N=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
case "$N" in (*[!0-9]*|'') N=0 ;; esac
[ "$N" -ge 25 ] && exit 0
echo $((N + 1)) > "$COUNT_FILE"

{
  echo "team-graph headless driver: this run routed ${ROUTE#ROUTE: } and has not finished. Do not narrate the next step — execute it in this turn:"
  echo "- About to delegate? Spawn that node NOW (FAST: read solo-executor.md and follow it here; FULL: spawn the next node the plan names)."
  echo "- At the approval gate? TEAM_IRFAN_AUTO_APPROVE=1 — the gate is auto-approved. BLOCKING questions are forbidden: answer them yourself from clarifications.md, then the repo (package.json scripts ARE the gate commands), then a stated default, and record each answer in the plan's assumptions."
  echo "- Keep driving node after node until the terminal artifact exists (FULL: .team-irfan/handoffs/<date>-<slug>.md written and the summary printed; FAST: the 4-question report ending with a Verdict: line)."
} >&2
exit 2
