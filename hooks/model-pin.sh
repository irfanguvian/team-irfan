#!/usr/bin/env bash
# team-graph PreToolUse(Task) hook: in a bench session, a node inherits the
# session model. Zero LLM.
#
#   exit 0  →  allow
#   exit 2  →  block; stderr goes back to the caller as the reason
#
# The 2026-08-21 sonnet-low matrix leaked opus into 39-73% of the team cells
# it then killed: agent frontmatter pinned `model: opus`, and the lead added a
# `model` parameter to its Task calls on top. The frontmatter pins are gone;
# this closes the second path, so an arm measures the model the arm names.
# Inert outside a bench run — interactive sessions may pin whatever they like.

set -uo pipefail

[ "${TEAM_IRFAN_AUTO_APPROVE:-}" = "1" ] || exit 0

M=$(jq -r '.tool_input.model // empty' 2>/dev/null)
[ -n "$M" ] || exit 0

echo 'bench model pin: session model is pinned for this arm — re-issue the Task call without the "model" parameter' >&2
exit 2
