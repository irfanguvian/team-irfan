#!/usr/bin/env bash
# SessionStart proof-of-load sentinel for bench runs. Rigid, zero LLM.
#
# The 2026-08-20 opus matrix recorded 6 team cells that never had the plugin
# loaded — the manifest was stale and nothing on disk said so, so the numbers
# looked like a team-graph result. This hook leaves the evidence: if the plugin
# is loaded, the file exists and carries the version that loaded it. The harness
# compares it against the repo's plugin.json and marks the cell INFRA_FAIL when
# it disagrees or is missing. No model is asked whether the plugin loaded.
#
#   TEAM_IRFAN_AUTO_APPROVE != 1  → exit 0. Interactive sessions leave no trace.
#   otherwise                     → .tg-bench/plugin-loaded in cwd, exit 0.
#
# Never prints to stdout (hook stdout can be injected into the session context)
# and never fails a session: every error path still exits 0.

set -uo pipefail

[ "${TEAM_IRFAN_AUTO_APPROVE:-}" = "1" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERSION=$(jq -r '.version // empty' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)

mkdir -p .tg-bench 2>/dev/null || exit 0
jq -nc --arg v "$VERSION" --arg r "$ROOT" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{version:$v,root:$r,ts:$ts}' > .tg-bench/plugin-loaded 2>/dev/null

exit 0
