# Change summary — Task <id>

run: <yyyymmdd-slug>
executor: <exec-n>
worktree: ../tg-<slug>-<id>
commits: <sha> <sha>

## What changed

<two to four lines. what now exists that did not before. behavior, not a diff
narration.>

## Files

| File | Change |
|---|---|
| `path/file.ts` | <one line> |
| `path/file.test.ts` | <one line> |

## How to verify

<exact commands, copy-pasteable, run from the worktree root. the tester runs
THESE — vague instructions here become an untested change.>

```bash
pnpm vitest run test/thing.test.ts
curl -s -X POST http://127.0.0.1:3000/api/thing \
  -H 'content-type: application/json' \
  -d '{"id":1}' | jq
```

Expected: <what a pass looks like. exact status code, exact field, exact
value.>

## Gate output

```
<paste bash ~/.claude/team-graph/hooks/gate.sh verbatim>
```

## Contract changes

<none — or old contract → new contract, one line each. a changed test
assertion belongs here.>

## Found but not fixed

<out-of-scope problems seen along the way. named, not silently left. a
security or N+1 finding here is mandatory, even if untouched.>

## Ponytail shortcuts

<deliberate simplifications and their upgrade path, matching the `ponytail:`
comments in the diff. or "none">
