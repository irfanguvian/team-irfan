---
folder: <path/from/repo/root>
last_commit: <git rev-parse HEAD at generation time>
updated: <yyyy-mm-dd>
---

## Purpose

<2-3 lines. What this folder is responsible for, in domain terms.>

## Key files

<file → one line each. Only files an agent would need to open. A folder with
50 files does not get 50 rows — it gets the ones that carry the behavior.>

| File | What it does |
|---|---|
| `x.service.ts` | <one line> |

## Entry points

<routes, exported symbols, cron jobs, queue consumers — the ways the outside
world reaches this folder.>

## Conventions

<ONLY where this folder differs from config.md. Identical to the project
default means write "as config.md" and stop. Repeating the default wastes the
line budget this cap exists to protect.>

## Depends on / used by

**Depends on:** <folders/packages this one imports>
**Used by:** <folders that import this one>

## Registry tags

<the FEAT/MOD/DEC ids to grep in docs/REGISTRY.md before reading any code here.>

<!-- HARD CAP 80 LINES. Over cap = cut Key files to the load-bearing ones. -->
