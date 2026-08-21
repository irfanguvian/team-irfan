#!/usr/bin/env bash
# Builds everything a run needs and then stops. Nothing here spawns an agent.
#
#   init.sh              build the fixture repo, its tags, and the three arm configs
#   init.sh --configs    rebuild only the arm configs (cheap, no npm)
#
# The fixture is the v3 NestJS+Prisma invoices app plus fixture-patches/base
# (customers, refunds, audit modules and their contract tests). Each task state
# is a SINGLE ORPHAN COMMIT tagged <task>-base — no state's history contains
# another state's bug being planted or removed, so `git log` leaks nothing.
#
#   q1-base / f1-base   clean modules, correct date util (invoices N+1 present,
#                       as committed in the v3 fixture — it is N5's 5th seed)
#   n5-base             + four more seeded N+1s (customers, refunds, audit, reports)
#   b1-base             + broken shared date util, clean services
#   mem-base            + reports overview N+1 and customers activity N+1
set -euo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V3="$H/../harness-v3"
BENCH_ROOT="${BENCH_ROOT:-$HOME/team-irfan-bench-v4}"
REAL_CLAUDE="${REAL_CLAUDE:-$HOME/.claude}"

build_configs() {
  rm -rf "$H/configs"
  mkdir -p "$H/configs"/{bare,omc,team}

  # Credentials: the live token sits in the macOS Keychain, which a non-default
  # CLAUDE_CONFIG_DIR cannot reach. Mode 600, configs/ is gitignored, but these
  # ARE a plaintext copy of the OAuth token: delete configs/ when finished.
  # Tokens expire — a resume weeks later must re-run this script.
  if creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null); then
    for arm in bare omc team; do
      printf '%s' "$creds" | jq '{claudeAiOauth}' > "$H/configs/$arm/.credentials.json"
      chmod 600 "$H/configs/$arm/.credentials.json"
      # Claude Code >= 2.1.238 reads macOS creds from a per-config-dir Keychain
      # item, "Claude Code-credentials-<sha256(dir)[0:8]>", and ignores the file.
      # Write both. Refresh-token rotation in one arm can invalidate the others'
      # copy; if a lane dies with "OAuth session expired", rerun --configs.
      suffix=$(printf '%s' "$H/configs/$arm" | shasum -a 256 | cut -c1-8)
      security add-generic-password -U -a "$USER" -s "Claude Code-credentials-$suffix" \
        -w "$(printf '%s' "$creds" | jq -c '{claudeAiOauth}')" >/dev/null 2>&1 \
        || echo "warning: could not write Keychain item for $arm" >&2
    done
  else
    echo "warning: no Keychain credentials found — arms will not authenticate" >&2
  fi

  for arm in bare omc team; do
    jq 'del(.projects, .mcpServers)' "$HOME/.claude.json" > "$H/configs/$arm/.claude.json"
  done

  # Arm A — bare: empty memory, no plugins, no hooks, MCP off at the CLI.
  : > "$H/configs/bare/CLAUDE.md"
  printf '{}\n' > "$H/configs/bare/settings.json"
  printf '{"mcpServers":{}}\n' > "$H/configs/bare/mcp-empty.json"

  # Arms B and C share the operator's real setup; they differ in exactly two
  # things — whether CLAUDE.md carries the team-graph pipeline rule, and whether
  # the prompt is prefixed with /team-irfan. That is the isolate.
  for arm in omc team; do
    ln -sfn "$REAL_CLAUDE/plugins" "$H/configs/$arm/plugins"
    for f in settings.json FUNDAMENTALS.md agents commands skills; do
      [ -e "$REAL_CLAUDE/$f" ] && cp -R "$REAL_CLAUDE/$f" "$H/configs/$arm/$f"
    done
  done
  awk '/^## WORKFLOW PIPELINE — team-graph/{skip=1} /^## Context Database/{skip=0} !skip' \
    "$REAL_CLAUDE/CLAUDE.md" > "$H/configs/omc/CLAUDE.md"
  cp "$REAL_CLAUDE/CLAUDE.md" "$H/configs/team/CLAUDE.md"

  echo "configs rebuilt: $H/configs/{bare,omc,team}"
}

if [ "${1:-}" = "--configs" ]; then build_configs; exit 0; fi

[ -d "$V3/fixture" ] || { echo "init.sh: harness-v3 fixture not found at $V3/fixture" >&2; exit 1; }

# ---------------------------------------------------------------- fixture repo
rm -rf "$BENCH_ROOT"
mkdir -p "$BENCH_ROOT"
cd "$BENCH_ROOT"
git init -q -b main

# lay down one state's tree, commit it PARENTLESS, tag it
reset_tree() {
  find "$BENCH_ROOT" -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} +
  rsync -a --exclude node_modules --exclude dist --exclude .env --exclude '*.db' \
    --exclude '.omc' --exclude 'test/acceptance' "$V3/fixture/" "$BENCH_ROOT/"
  rsync -a "$H/fixture-patches/base/" "$BENCH_ROOT/"
  for patch in "$@"; do rsync -a "$H/fixture-patches/$patch/" "$BENCH_ROOT/"; done
}

snapshot() {
  local tag=$1
  git add -A
  local tree commit
  tree=$(git write-tree)
  commit=$(GIT_AUTHOR_NAME=bench GIT_AUTHOR_EMAIL=bench@local \
           GIT_COMMITTER_NAME=bench GIT_COMMITTER_EMAIL=bench@local \
           git commit-tree "$tree" -m "chore: bench fixture")
  git tag -f "$tag" "$commit"
}

reset_tree b1;        snapshot b1-base
reset_tree n5;        snapshot n5-base
reset_tree mem;       snapshot mem-base
reset_tree;           snapshot q1-base; git tag -f f1-base q1-base
# leave the clean tree checked out on main for npm ci / prisma generate
git -c user.name=bench -c user.email=bench@local commit -qm "chore: bench fixture"

npm ci --no-audit --no-fund >/dev/null
DATABASE_URL="file:./dev.db" npx prisma generate >/dev/null 2>&1

build_configs
[ -f "$H/pricing.json" ] || cp "$V3/pricing.json" "$H/pricing.json"
echo "fixture ready: $BENCH_ROOT  (tags: $(git tag | tr '\n' ' '))"
