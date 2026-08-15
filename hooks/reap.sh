#!/usr/bin/env bash
# team-graph crash cleanup. Zero LLM. Run from the project root at the START of
# a FULL run, before `git switch -c`.
#
#   reap.sh [--dry-run]
#
# Removing a dead run's residue is a deterministic operation with a
# deterministic detection rule, so it is a script, not a line in a prompt. The
# prompt rule ("never leave .tg-active behind") cannot execute in the one case
# that matters: the run that died before reaching it.
#
# A stale .tg-active is the expensive one. It leaves subagent-gate.sh armed for
# EVERY unrelated session in that directory, so the isolation guarantee silently
# inverts into a global side effect.
#
# Env:
#   TG_REAP_AGE   minutes a run directory may be untouched before its residue is
#                 considered dead. Default 120. 0 means "nothing is live".
#
# Branches are REPORTED, never deleted. A worktree branch created at HEAD reads
# as already-merged the moment it exists, so "delete merged orphans" would eat
# the branch of a run that crashed before its first commit. Printing costs a
# line; deleting costs the work.

set -uo pipefail

TG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGE="${TG_REAP_AGE:-120}"
DRY=no
[ "${1:-}" = "--dry-run" ] && DRY=yes

act() { [ "$DRY" = yes ] && { echo "reap: would $*"; return 1; }; return 0; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "reap: not a git repo — nothing to reap"; exit 0; }

# ------------------------------------------------------------- live runs

# A run is live if its directory was touched inside the age window. Every node
# writes an artifact, so an untouched run directory is a run nobody is running.
LIVE_SLUGS=""
if [ -d "$TG/runs" ]; then
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    id=$(basename "$d")
    # run ids are <yyyymmdd>-<slug>; the slug is what worktree names carry
    LIVE_SLUGS="$LIVE_SLUGS${id#*-}"$'\n'
  done <<< "$(find "$TG/runs" -mindepth 1 -maxdepth 1 -type d -mmin "-$AGE" 2>/dev/null)"
  LIVE_SLUGS=$(printf '%s' "$LIVE_SLUGS" | sed '/^$/d')
fi

REAPED=0

# ------------------------------------------------------------- worktrees

# git worktree list --porcelain emits blank-line-separated records; the first
# record is the main worktree, which is never a tg- throwaway.
WT=""
BR=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*) WT="${line#worktree }"; BR="" ;;
    "branch "*)   BR="${line#branch refs/heads/}" ;;
    "")
      [ -n "$WT" ] || continue
      name=$(basename "$WT")
      case "$name" in tg-*) ;; *) WT=""; continue ;; esac
      keep=no
      while IFS= read -r slug; do
        [ -n "$slug" ] || continue
        case "$name" in *"$slug"*) keep=yes ;; esac
      done <<< "$LIVE_SLUGS"
      if [ "$keep" = yes ]; then
        echo "reap: $name belongs to a live run — kept"
      elif act "remove worktree $WT"; then
        if git worktree remove "$WT" 2>/dev/null; then
          echo "reap: removed orphan worktree $name"
          REAPED=$((REAPED+1))
          [ -n "$BR" ] && echo "reap: branch $BR left in place — delete it yourself if it holds nothing"
        else
          echo "reap: $name has uncommitted work — left alone, resolve it by hand"
        fi
      fi
      WT=""
      ;;
  esac
done <<< "$(git worktree list --porcelain 2>/dev/null)"$'\n'
# ^ the trailing $'\n' matters: command substitution strips every trailing
#   newline, so without it the LAST record never meets its blank-line terminator
#   and the last worktree is silently never examined.

[ "$DRY" = yes ] || git worktree prune 2>/dev/null

# ------------------------------------------------------------- .tg-active

if [ -f .tg-active ]; then
  if [ -n "$LIVE_SLUGS" ]; then
    echo "reap: .tg-active kept — $(printf '%s' "$LIVE_SLUGS" | tr '\n' ' ')still live"
  elif act "remove .tg-active"; then
    rm -f .tg-active
    echo "reap: removed stale .tg-active (no run touched in ${AGE}m)"
    REAPED=$((REAPED+1))
  fi
fi

[ "$REAPED" -eq 0 ] && echo "reap: nothing to clean"
exit 0
