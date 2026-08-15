#!/usr/bin/env bash
# Shared write primitives. Sourced, never executed.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/atomic.sh"
#
#   atomic_cp <src> <dst>        replace dst in one step, never half-written
#   with_lock <file> <cmd...>    serialise a read-modify-write on <file>
#
# Two different problems, two different tools, and the difference matters:
#
#   Atomic replace fixes torn READS. A reader either sees the old file or the
#   new one, never a truncated one.
#
#   It does NOT fix lost WRITES. Two processes that read the same counter,
#   increment it, and atomically replace it both wrote correctly and one update
#   is still gone. Read-modify-write needs a lock; nothing else will do.
#
# Where a counter is bumped often enough that lock contention would cost more
# than it saves — the tool-call ledger, once per tool call — the right answer is
# neither: make the store append-only so there is nothing to read first. See
# hooks/ledger.sh.
#
# flock(1) is not on macOS, so the lock is a mkdir: a single syscall that
# succeeds for exactly one caller.

# shellcheck shell=bash

atomic_cp() {
  local src="$1" dst="$2" tmp="$2.$$.tmp"
  cp "$src" "$tmp" || return 1
  mv "$tmp" "$dst"
}

atomic_write() {   # atomic_write <dst>  — content on stdin
  local dst="$1" tmp="$1.$$.tmp"
  cat > "$tmp" || return 1
  mv "$tmp" "$dst"
}

with_lock() {
  local target="$1"; shift
  local lock="$target.lock" waited=0
  until mkdir "$lock" 2>/dev/null; do
    waited=$((waited+1))
    if [ "$waited" -gt 400 ]; then          # ~20s — the holder is dead, not slow
      rmdir "$lock" 2>/dev/null || true
      mkdir "$lock" 2>/dev/null || return 1
      break
    fi
    sleep 0.05
  done
  "$@"
  local rc=$?
  rmdir "$lock" 2>/dev/null
  return $rc
}
