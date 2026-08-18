# Plan — <feature>

run: <yyyymmdd-slug>
author: PjM
status: draft | approved

## Goal

<one sentence. the behavior that exists after this run and did not before.>

## Work list

<the task restated as verifiable items. each one checkable, none vague.>

- [ ] <item — observable behavior, not implementation>
- [ ] <item>

## Scope

<from PM's scope.md. every rule carries a source: file:line, registry R-id,
or "ask user".>

**In:**
- <thing> — source: `path/file.ts:42` | `R-00xx` | ask user

**Out:**
- <thing> — <where it belongs instead>

## Options

<from Lead. 1–3 options, never more. one marked recommended with a one-line
reason.>

### Option A — <approach, one line> ← recommended: <one line why>

- files: `path/a.ts`, `path/b.ts`
- risk: <one line>
- expected_calls: <number>

### Option B — <approach, one line>

- files: ...
- risk: ...
- expected_calls: <number>

## Chosen option

<id> — <one line>

## Test contract

type: backend-e2e | frontend-browser | both
cases_source: plan

## Open questions for Irfan

<PM's open questions, folded here. answered at the single plan gate, nowhere
else. or "none">

- [ ] <question>

## Run cap

run_cap: <min(round(chosen expected_calls × 1.3), 60)>
