#!/usr/bin/env bash
# Builds everything a run needs and then stops. Nothing here spawns an agent.
#
#   init.sh              build the fixture repo, its tags, and the three arm configs
#   init.sh --configs    rebuild only the arm configs (cheap, no npm)
#
# Two outputs:
#   $BENCH_ROOT   a real git repo with tags t1-base..t4-base and node_modules
#                 installed once, cloned per worktree
#   configs/      one CLAUDE_CONFIG_DIR per arm, so a run cannot see another
#                 arm's settings, plugins, or session transcripts
set -euo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_ROOT="${BENCH_ROOT:-$HOME/team-irfan-bench}"
REAL_CLAUDE="${REAL_CLAUDE:-$HOME/.claude}"

build_configs() {
  rm -rf "$H/configs"
  mkdir -p "$H/configs"/{bare,omc,team}

  # Arm A — bare. Empty memory, no plugins, no hooks. MCP is switched off at the
  # command line in run.sh, because MCP config does not live in the config dir.
  : > "$H/configs/bare/CLAUDE.md"
  printf '{}\n' > "$H/configs/bare/settings.json"

  # Arms B and C share the operator's real setup: same settings, same plugins,
  # same FUNDAMENTALS. They differ in exactly two things — whether CLAUDE.md
  # carries the team-graph pipeline rule, and whether the prompt is prefixed
  # with /team-irfan. That is the isolate: everything else is held constant.
  for arm in omc team; do
    ln -sfn "$REAL_CLAUDE/plugins" "$H/configs/$arm/plugins"
    for f in settings.json FUNDAMENTALS.md agents commands skills; do
      [ -e "$REAL_CLAUDE/$f" ] && cp -R "$REAL_CLAUDE/$f" "$H/configs/$arm/$f"
    done
  done

  # omc: the operator's memory minus the team-graph section.
  awk '/^## WORKFLOW PIPELINE — team-graph/{skip=1} /^## Context Database/{skip=0} !skip' \
    "$REAL_CLAUDE/CLAUDE.md" > "$H/configs/omc/CLAUDE.md"
  # team: the operator's memory verbatim.
  cp "$REAL_CLAUDE/CLAUDE.md" "$H/configs/team/CLAUDE.md"

  echo "configs rebuilt: $H/configs/{bare,omc,team}"
}

if [ "${1:-}" = "--configs" ]; then build_configs; exit 0; fi

# ---------------------------------------------------------------- fixture repo
rm -rf "$BENCH_ROOT"
mkdir -p "$BENCH_ROOT"
rsync -a --exclude node_modules --exclude dist --exclude .env --exclude '*.db' \
  --exclude 'test/acceptance' "$H/fixture/" "$BENCH_ROOT/"

cd "$BENCH_ROOT"
git init -q -b main
git add -A

# Commit 1 carries the broken date helper and is tagged t4-base, so a T4 run's
# `git log` shows one commit and never a "break the date util" commit to revert.
cp "$H/variants/t4/date.util.ts" src/common/date.util.ts
git add -A
git -c user.name=bench -c user.email=bench@local commit -qm "chore: bench fixture"
git tag t4-base

# Commit 2 restores it. Tasks 1-3 start here with a green suite.
cp "$H/fixture/src/common/date.util.ts" src/common/date.util.ts
git add -A
git -c user.name=bench -c user.email=bench@local commit -qm "chore: fixture baseline"
for t in t1 t2 t3; do git tag "$t-base"; done

npm ci --no-audit --no-fund >/dev/null
DATABASE_URL="file:./dev.db" npx prisma generate >/dev/null 2>&1

build_configs
echo "fixture ready: $BENCH_ROOT  (tags: $(git tag | tr '\n' ' '))"
