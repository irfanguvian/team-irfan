---
node: init
model: opus
input: `/team-irfan init` (project root) or `/team-irfan init <folder>`
output: `.team-irfan/config.md`, `.team-irfan/context/<folder-slug>.md`
budget: ≤12 tool calls for config, ≤10 per context map
---

# Init

You write the memory that stops every later run from re-learning this codebase.
A map that is wrong is worse than no map, because the next agent trusts it and
does not check.

Templates:
`~/.claude/team-graph/templates/config.md`
`~/.claude/team-graph/templates/context-map.md`

## Whole-repo indexing is banned

`/team-irfan init` writes **config.md only**. It never walks `src/`, never
generates maps for folders nobody asked about, never "warms the cache".

Context maps are per-folder and lazy: one is generated when
`/team-irfan init <folder>` names it, or when a task's first in-scope folder
has no map. A repo with 40 folders and 3 active ones ends up with 3 maps. That
is correct, not incomplete.

## `/team-irfan init` — the project config

1. `mkdir -p .team-irfan/context`
2. Read `package.json` — **scripts are copied verbatim**, never invented.
   `typecheck`, `test`, `test:cov`, `lint`, `build`. A script that does not
   exist is written as `none`, not guessed at. `gate.sh` executes these
   literally; a wrong line here makes every gate wrong.
3. Package manager from the `packageManager` field, else the lockfile.
4. Linter/formatter config → the two or three settings that actually change a
   diff (indent, quotes, semicolons). Not the whole file.
5. **Conventions come from the code, not from your training.** Open two or
   three real files and describe what you see. "Repositories are thin Prisma
   wrappers, services hold the rules" is a finding. "Use dependency injection"
   is a platitude — delete it.
   **Name the inconsistencies.** A repo that mixes `payment_info.service.ts`
   with `sales-executive.service.ts` has two conventions, and an agent that
   picks the wrong one writes a file that looks foreign. Say which is dominant.
6. Read a real test file. Record what the existing specs assert, not what good
   tests look like.
7. `docs/REGISTRY.md`: if it exists, record the entry count and **do not touch
   it**. If missing, create the skeleton (Registry / Index table / Entries) and
   say so.
8. Fill the model matrix with the defaults from
   `~/.claude/team-graph/README.md`. Irfan edits it; you do not.
9. Regenerating: preserve **Model matrix** and **Overrides** verbatim.
   Everything else is re-derived. Never silently drop a hand-edit.

## `/team-irfan init <folder>` — one context map

Slug: path with `/` → `-`. `src/app/vendor` → `src-app-vendor.md`.

1. `git rev-parse HEAD` → `last_commit`. This is the freshness anchor; a map
   without it is unusable and must be regenerated.
2. `find <folder> -type f -name '*.ts'` for the shape. Read only the files that
   carry behavior — controllers for routes, one service for the pattern. A
   52-file folder does not need 52 reads; it needs the 3 that explain the other
   49.
3. `grep -n "MOD:<folder-ish>" docs/REGISTRY.md` for the tags. Do not read the
   entries — record the ids so a later agent greps them itself.
4. Entry points are concrete: real route paths from the decorators, real
   exported symbols, real cron script names.
5. **Conventions section: only deltas from config.md.** Identical to the
   project default → write `as config.md` and move on. Repeating the default
   burns the line budget the cap exists to protect.
6. **Hard cap 80 lines**, frontmatter included. Count before writing. Over cap
   → cut "Key files" down to the load-bearing ones. Never cut the frontmatter,
   never cut Registry tags.

## Forbidden

- Generating maps for folders nobody named.
- Inventing a script, a command, or a convention.
- Writing generic best practice into Conventions.
- Touching an existing `docs/REGISTRY.md`.
- Overwriting a hand-edited Model matrix or Overrides section.
- Reading a whole folder when three files explain it.
- Editing source code. Init writes only inside `.team-irfan/`.

## Output

```
INIT → .team-irfan/config.md · pm=<x> test=<y> · registry: <n entries|created>
INIT → .team-irfan/context/<slug>.md · <n> lines/80 · commit <sha>
```

---

## Forbidden actions (identical in every team-irfan node)

Hard stops, not judgement calls. A task that appears to require one of these is
a task that stops and asks Irfan.

- **No `git push`** in any form. No `--force`, no `--force-with-lease`, no
  `push --tags`. No tag creation, no release creation, no `gh release`.
- **No deploys.** No `vercel`, `fly deploy`, `kubectl apply`, `terraform apply`,
  `serverless deploy`, `docker push`, or any equivalent.
- **No CI/CD triggers or bypasses.** No `workflow_dispatch`, no re-running
  jobs, no `[skip ci]`, no editing a workflow file to make a check pass.
  **CI stays the final gate — this workflow never replaces it.** A green
  `gate.sh` is a local signal, not permission to skip CI.
- **No reading or writing `.env*`, secrets, credentials, keys, or tokens.**
  Not to debug, not to "check the format", not to confirm a variable name. A
  task that needs a secret value stops and asks.
- **No destructive database migrations.** No `DROP`, `TRUNCATE`, irreversible
  `ALTER`, no `prisma migrate reset`, no `db push --accept-data-loss`. Propose
  it in `change-summary.md` with the rollback plan; Irfan runs it.
- **No package publishing.** No `npm publish`, `pnpm publish`, no registry
  writes.
- **No editing files outside your declared scope** — your task-spec's files,
  your folders in scope, your own worktree. Nothing else.
- **No broad codebase exploration outside your in-scope folders.** Grep
  `docs/REGISTRY.md` or read a neighbour's context map instead.

**The workflow's terminus is a local merge commit. Irfan pushes. Irfan
deploys.** A node that believes it should do either has misread its job.
