---
name: team-graph-context-loading
description: Map-first context loading for every team-graph node. Agents read context maps, not folders. Canonical rule — agent prompts carry the short form and point here.
---

# Context loading — map-first

An agent that re-reads a folder it already has a map for is paying twice for
the same knowledge. This rule exists so the graph stops re-learning the
codebase on every run.

## The rule

### 1. Resolve folders in scope

- FULL path: the `folders in scope` field in your task block in `plan.md`. Product writes it, so
  executors inherit scope mechanically rather than inferring it.
- FAST path / Router / PM: derive from the task. Name them explicitly before
  reading anything — an unnamed scope is an unbounded one.

### 2. Load the maps, not the folders

```
.team-irfan/config.md                        ← always
.team-irfan/context/<folder-slug>.md         ← one per in-scope folder, nothing else
```

Slug = path with `/` → `-`. `src/app/vendor` → `src-app-vendor.md`.

`config.md` carries the stack, the exact gate commands, and the project-wide
conventions. The map carries what is specific to that folder. Together they
replace the exploratory read pass.

### 3. Freshness check — one command per folder

```bash
git diff --name-only <last_commit> -- <folder>
```

`last_commit` comes from the map's frontmatter.

- **Empty output → the map is current.** Trust it. **Do not re-read the
  folder.** This is the whole point; skipping this check and reading anyway
  costs exactly what the map was built to save.
- **Non-empty → the map is stale for those files only.** Re-read **only the
  files listed**, never the folder. Update the affected rows, set
  `last_commit` to the current HEAD and `updated` to today. **≤10 tool calls.**
  Over 10 means the folder changed enough to regenerate — hand it to
  `agents/init.md` instead of patching.
- Map has no `last_commit` → treat as missing, regenerate.

### 4. Missing map

Generate it for **that folder only**, following `agents/init.md`. Then proceed.
Never generate maps for folders the task does not touch — whole-repo indexing
is banned.

### 5. Outside scope is forbidden

Reading, grepping, or listing files outside the in-scope folders is a forbidden
action, not a judgement call.

Need something from elsewhere:

1. `grep -n "FEAT:<x>"` / `grep -n "MOD:<x>"` in `docs/REGISTRY.md`, then
   `sed -n` the matched entries only. Never `cat` it.
2. Read the neighbouring folder's context map — that is what it is for.
3. Still blocked → ask Irfan. Subagents have no channel: state the assumption
   explicitly in your output artifact and let the orchestrator surface it.

## Why the check is not optional

The failure mode this prevents is silent: an agent reads a stale map, produces
a change against a convention that moved three commits ago, and the gate passes
because the code compiles. The freshness check is one `git diff` per folder. It
is cheaper than every alternative, including being wrong once.

## What a refresh is not

- Not a re-read of the folder. Only the files `git diff` named.
- Not an excuse to widen scope. A changed file outside the in-scope folders
  stays outside.
- Not a rewrite. Patch the affected rows, keep the rest, keep the line cap.
