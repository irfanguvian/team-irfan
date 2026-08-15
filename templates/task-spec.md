# Task <id> — <short name>

run: <yyyymmdd-slug>
executor: <exec-1 | exec-2 | ...>
worktree: ../tg-<slug>-<id>
surface: backend | frontend | infra | data

## Goal

<one sentence. the behavior that exists after this task and did not before.>

## Folders in scope

<PjM writes this. The executor inherits scope mechanically instead of inferring
it, and loads exactly these context maps — no more, no less. Reading outside
this list is a forbidden action.>

- `src/app/vendor` → `.team-irfan/context/src-app-vendor.md`

## Files in scope

<explicit list. an executor touching anything not on this list is out of
scope — it reports it, it does not fix it.>

- `path/to/file.ts`
- `path/to/file.test.ts`

## Acceptance criteria

<checkable, derived from brief.md. the tester writes cases from THESE, never
from the diff.>

- [ ] <criterion>
- [ ] <criterion>

## Out of scope

- <thing> — <where it belongs instead>

## Guardrails that bite here

<name the sections from skills/guardrails/SKILL.md that this task actually
touches. not all of them — the ones a reviewer must check.>

- §2 testing — <why>
- §7 database — <why>

## Depends on

<other task ids that must merge first, or "none">
