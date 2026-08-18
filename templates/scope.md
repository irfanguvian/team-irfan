# Scope — <feature>

run: <yyyymmdd-slug>
author: PM

## Problem

<what is broken or missing, in one paragraph, in business terms. no solution
language.>

## Scope in

<the rules that decide correct behavior. every rule was found in the code /
registry, or is marked "ask user". never invented.>

| Rule | Source |
|---|---|
| <rule> | code `path/file.ts:42` \| registry `R-00xx` \| **ask user** |

## Scope out

<named explicitly, so no downstream node drifts into it.>

- <thing> — <where it belongs instead>

## Open questions

<blocking questions only, source "ask user". a question you can answer by
grepping is not a question, it is work you skipped. PjM folds these into
plan.md; Irfan answers them at the single plan gate.>

- [ ] <question> — blocks: <which rule above>

## Acceptance

<how anyone knows this is done. observable behavior, not implementation.>

- <criterion>
