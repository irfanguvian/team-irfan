# Plan — <feature>

run: <yyyymmdd-slug>
author: Product
status: draft | approved

## Open questions for Irfan

<at the TOP, so answering them and approving the plan is one interaction at
the single gate. blocking questions only, source "ask user". or "none">

- [ ] <question> — blocks: <which rule below>

## Goal

<one sentence. the behavior that exists after this run and did not before.>

## Work list

<the task restated as verifiable items. each one checkable, none vague.>

- [ ] <item — observable behavior, not implementation>
- [ ] <item>

## Business rules

<the rules that decide correct behavior. every rule was found in the code /
registry, or came from Irfan. an inferred rule is a question above, not a rule.>

| Rule | Source |
|---|---|
| <rule> | code `path/file.ts:42` \| registry `R-00xx` \| confirmed by user \| **ask user** |

## Scope

**In:**
- <thing> — source: `path/file.ts:42` | `R-00xx` | confirmed by user

**Out:**
- <thing> — <where it belongs instead>

## SCOPE

<the execution shape, drawn so the cap is approved with the numbers visible.>

- execution path: <the chosen approach, one line, with expected_calls>
- parallel lanes: <which tasks run concurrently, or "none">
- merge points: <the dependency order the orchestrator merges in>
- rejected alternative: <the approach not taken + one line why>

## PHASES

<every plan is written against the cap, or split until it is. one phase =
self-contained goal: merges alone, gates green alone, ships value alone.
single-phase when the whole goal fits — the block still appears.
hooks/plan-check.sh recomputes every projection; arithmetic is not yours.>

```
budget_cap: 60
projection_formula: 26 + 27*tasks
phase 1: <goal>  tasks: [T1]  projected: 53  fits: yes
phase 2: <goal>  tasks: [T2]  projected: 53  fits: yes
```

## Tasks

<one block per task. one task = one executor = one worktree = one merge.
executors receive their own block only — it is the contract.>

### Task T1 — <short name>

surface: backend | frontend | infra | data

**Goal:** <one sentence. the behavior that exists after this task.>

**Folders in scope:**
- `src/app/vendor` → `.team-irfan/context/src-app-vendor.md`

**Files in scope:**
- `path/to/file.ts`
- `path/to/file.test.ts`

**Acceptance criteria:**
- [ ] <checkable, derived from the plan. QA writes its cases from plan.json,
  never from the diff.>

**Out of scope:**
- <thing> — <where it belongs instead>

**Guardrails that bite here:**
- §2 testing — <why. name only the sections a reviewer must actually check.>

**Depends on:** <other task ids that must merge first, or "none">

independent: yes | no

<yes ⇔ no file shared with any other task. the orchestrator parallelises ONLY
independent lanes.>

## Test contract

type: backend-e2e | frontend-browser | both
cases_source: plan

## Run cap

run_cap: <min(round(chosen expected_calls × 1.3), 60)>
