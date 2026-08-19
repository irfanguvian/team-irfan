#!/usr/bin/env bash
# Deterministic half of `/team-irfan init`. Zero LLM. Run from a project root.
#
#   init-scaffold.sh config          → .team-irfan/config.md  (commands filled from package.json)
#   init-scaffold.sh map <folder>    → .team-irfan/context/<slug>.md  (frontmatter + headings)
#
# Detection is a deterministic check and never gets handed to a prompt: a
# package manager and a script name are facts in a file, not judgement. The
# init agent fills only the probabilistic sections — Purpose, Key files,
# Conventions — which are the parts that actually need reading code.

set -uo pipefail

MODE="${1:-}"
[ -f package.json ] || { echo "no package.json in $(pwd) — run from the project root" >&2; exit 2; }

mkdir -p .team-irfan/context

# .team-irfan is local-only, never committed. Create .gitignore if the project
# has none — otherwise a repo without one leaves the context maps visible in
# `git status`, which is exactly what "local only" is meant to prevent.
if ! grep -qs '^\.team-irfan/' .gitignore; then
  printf '\n# team-irfan local context (never committed)\n.team-irfan/\n' >> .gitignore
fi

case "$MODE" in
config)
  node -e '
    const fs = require("fs");
    const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
    const s = pkg.scripts || {};
    const dev = { ...(pkg.devDependencies || {}), ...(pkg.dependencies || {}) };
    const has = f => fs.existsSync(f);

    const pm = pkg.packageManager ? pkg.packageManager
      : has("pnpm-lock.yaml") ? "pnpm"
      : has("yarn.lock") ? "yarn"
      : (has("bun.lockb") || has("bun.lock")) ? "bun"
      : "npm";
    const run = pm.split("@")[0];
    const runner = dev.vitest ? "vitest" : dev.jest ? "jest" : "none";
    const linter = has("biome.json") || has("biome.jsonc") ? "biome"
      : dev.eslint ? "eslint" + (dev.prettier ? " + prettier" : "") : "none";
    const orm = dev.prisma || dev["@prisma/client"] ? "prisma"
      : dev.typeorm ? "typeorm" : dev["drizzle-orm"] ? "drizzle" : "none";

    // a script that does not exist is written as `none`, never guessed at
    const cmd = name => s[name] ? `${run} ${name}` : "none";
    const pick = (...names) => { for (const n of names) if (s[n]) return `${run} ${n}`; return "none"; };

    const rows = [
      ["typecheck", pick("typecheck", "type-check", "tsc")],
      ["test",      pick("test")],
      ["coverage",  pick("test:cov", "coverage", "test:coverage")],
      ["lint",      pick("lint")],
      ["build",     pick("build")],
    ];
    const width = Math.max(...rows.map(r => r[0].length));

    const registryExists = has("docs/REGISTRY.md");
    const graphify = has("graphify-out") || has("src/graphify-out");

    const out = `# team-irfan config — ${pkg.name || "unnamed"}

generated: ${new Date().toISOString().slice(0,10)} · by \`/team-irfan init\` · commit \`${process.env.TG_SHA || "unknown"}\`

Regenerate with \`/team-irfan init --force\`. Hand-edits survive regeneration
only in **Model matrix** and **Overrides**.

## Stack

<one line: framework, language, runtime — filled by the init agent>

| | |
|---|---|
| package manager | \`${pm}\` |
| test runner | ${runner} |
| linter/formatter | ${linter} |
| ORM / DB | ${orm} |
| graphify index | ${graphify ? "present — executors may `graphify query` instead of reading files" : "none"} |

## Commands

\`gate.sh\` reads these instead of guessing. Wrong command here = wrong gate.
A script absent from package.json is \`none\`, not a guess.

\`\`\`
${rows.map(([k, v]) => k.padEnd(width) + ": " + v).join("\n")}
\`\`\`

## Conventions

<filled by the init agent from the actual code — folder layout, file naming,
layering, tests, formatting. Name the inconsistencies; a repo with two
conventions is information, not noise.>

## Registry

\`docs/REGISTRY.md\` — ${registryExists ? "exists, left untouched by init" : "created by init (skeleton)"}.
Grep by \`FEAT:\` \`MOD:\` \`STATUS:\` \`DEC:\` before reading code.

## Model matrix

| node | model |
|---|---|
| router | opus |
| product | opus |
| lead | opus |
| init | opus |
| evaluation | opus |
| executor | sonnet |
| qa | sonnet |
| solo-executor | sonnet |

## Overrides

_(hand-written notes here survive regeneration — empty)_
`;
    fs.writeFileSync(".team-irfan/config.md", out);
    console.log(`INIT → .team-irfan/config.md · pm=${pm} runner=${runner} registry=${registryExists ? "existing" : "created"}`);
  ' || exit 1

  if [ ! -f docs/REGISTRY.md ]; then
    mkdir -p docs
    cat > docs/REGISTRY.md <<'EOF'
# Registry

Context database for this project. Searched, not read whole.
Grep by tag: `FEAT:` `MOD:` `STATUS:` `DEC:`

## Index
| Feature | Modules | Latest | Status |
|---|---|---|---|

## Entries
EOF
  fi
  ;;

map)
  FOLDER="${2:-}"
  [ -n "$FOLDER" ] || { echo "usage: init-scaffold.sh map <folder>" >&2; exit 2; }
  [ -d "$FOLDER" ] || { echo "no such folder: $FOLDER" >&2; exit 2; }
  SLUG=$(printf '%s' "${FOLDER%/}" | tr '/' '-')
  SHA=$(git rev-parse HEAD 2>/dev/null || echo unknown)
  N=$(find "$FOLDER" -type f -name '*.ts' -o -type f -name '*.tsx' -o -type f -name '*.js' 2>/dev/null | wc -l | tr -d ' ')
  OUT=".team-irfan/context/$SLUG.md"
  cat > "$OUT" <<EOF
---
folder: ${FOLDER%/}
last_commit: $SHA
updated: $(date +%Y-%m-%d)
---

## Purpose

<2-3 lines, filled by the init agent. $N source files in this folder.>

## Key files

<file → one line each. Only the files that carry behavior — the ones that
explain the rest. Not every file.>

## Entry points

<routes, exported symbols, cron jobs, queue consumers.>

## Conventions

<ONLY deltas from config.md. Identical to the project default → "as config.md".>

## Depends on / used by

**Depends on:**
**Used by:**

## Registry tags

<FEAT/MOD/DEC ids to grep in docs/REGISTRY.md before reading any code here.>

<!-- HARD CAP 80 LINES. Over cap = cut Key files to the load-bearing ones. -->
EOF
  echo "INIT → $OUT · $(wc -l < "$OUT" | tr -d ' ') lines/80 · commit ${SHA:0:7} · $N source files"
  ;;

*)
  echo "usage: init-scaffold.sh config | map <folder>" >&2; exit 2 ;;
esac
