# Review — <feature>

run: <yyyymmdd-slug>
author: Lead (mode=review)
verdict: **PASS** | **BLOCKED**

This is the machine ship gate — no human sign-off follows it. Every claim
below is backed by pasted command output, in this file. A sentence with no
output behind it is an opinion, and this report is not for opinions.

## Backward compatibility

<every changed public function signature, route, or DTO/response shape, listed
explicitly — or "none". ANY breaking change ⇒ verdict BLOCKED, never a
footnote.>

## Gate

```
<bash ~/.claude/team-graph/hooks/gate.sh — output pasted verbatim>
```

## Scope

```
<git diff --name-only <base>..HEAD — pasted. every path must be inside
plan.json scope_folders.>
```

## Findings

<file:line + the offending lines quoted. or "none".>

## Diff

```
<git diff --stat <base>..HEAD — pasted verbatim>
```

**Verdict:** PASS | BLOCKED — <one line: the blocking cause, or what a future
session needs to know>
