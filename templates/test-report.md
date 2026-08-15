# Test report — Task <id>

run: <yyyymmdd-slug>
attempt: <1 | 2 | 3>
tester: tester
verdict: **PASS** | **FAIL**

## Cases

<derived from task-spec.md acceptance criteria, never from the diff.>

| # | Behavior asserted | Result |
|---|---|---|
| 1 | <sentence> | pass \| fail |
| 2 | <sentence> | pass \| fail |

## Evidence

<real command output. not a summary of it. the shortest decisive lines.>

```
$ <exact command from change-summary.md "How to verify">
<output>
```

```
$ curl -s -i http://127.0.0.1:3000/api/thing
<output>
```

## Bugs found

<one block per bug. this block goes back to the SAME executor verbatim.>

### BUG-1 — <one line>

- expected: <what acceptance criterion says>
- actual: <what happened>
- reproduce: `<exact command>`
- evidence:
  ```
  <output>
  ```

## Not covered

<what this report does NOT prove. silence here reads as full coverage, which
is a lie if a path was skipped.>

## Retry state

```
<paste bash ~/.claude/team-graph/hooks/retry-guard.sh <run> <task-id> output>
```

**Verdict:** PASS — merge · FAIL — return to executor <n> · ESCALATE — Lead
