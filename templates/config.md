# team-irfan config — <project name>

generated: <date> · by `/team-irfan init` · commit `<sha>`

Regenerate with `/team-irfan init --force`. Hand-edits survive regeneration only
in the **Model matrix** and **Overrides** sections — everything else is
re-derived from the repo.

## Stack

<one line: framework, language, runtime.>

| | |
|---|---|
| package manager | <pnpm@x.y.z — from packageManager field or lockfile> |
| test runner | <vitest — from devDependencies> |
| linter/formatter | <biome / eslint+prettier> |
| ORM / DB | <prisma + postgres> |
| graphify index | <src/graphify-out present — executors may query it \| none> |

## Commands

`gate.sh` reads these instead of guessing. Wrong command here = wrong gate.

```
typecheck: <exact script>
test:      <exact script>
coverage:  <exact script>
lint:      <exact script>
build:     <exact script>
```

## Conventions

Extracted from this codebase. Not best practice — **what this repo actually
does.** Where the repo is inconsistent, say so; that is information, not noise.

### Folder layout

<how modules are organised, with a real path as the example.>

### File naming

<the per-file suffix pattern, with the real inconsistencies named.>

### Tests

<where they live, what they are named, what style they are written in, what
the existing specs actually assert.>

### Formatting

<from the linter config, not from taste.>

## Registry

`docs/REGISTRY.md` — <exists, n entries \| created by init>. Grep by
`FEAT:` `MOD:` `STATUS:` `DEC:` before reading code.

## Model matrix

Overrides the default in `~/.claude/team-graph/README.md`. Delete a row to fall
back to the default.

| node | model |
|---|---|
| router | <opus> |
| pm | <opus> |
| lead | <opus> |
| pjm | <sonnet> |
| executor | <sonnet> |
| tester | <sonnet> |
| solo-executor | <sonnet> |
| retro | <sonnet> |

## Overrides

<hand-written notes that must survive regeneration. Empty by default.>
