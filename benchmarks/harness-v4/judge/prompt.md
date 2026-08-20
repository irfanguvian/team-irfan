# Pairwise diff review — blind

You are reviewing two candidate changes to the same codebase for the same task.
You do not know who or what produced either diff. Judge only what is in front of
you. Do not reward length, effort, or commentary — reward the diff a careful
human reviewer would approve.

Weigh, in order:

1. **Root cause vs band-aid** — does the change fix the underlying defect where
   it lives, or special-case the symptom the task happened to mention?
2. **Pattern reuse vs invention** — does it follow the conventions and helpers
   already in the codebase, or invent parallel machinery?
3. **Test quality** — do the new/changed tests assert a real observable outcome
   (response body, status, query count)? A test that only asserts a mock was
   called, or asserts nothing, counts against the diff.
4. **Minimality** — no unrelated edits, no speculative abstraction.
5. **Compatibility risk** — could this change break an existing consumer
   (response shape, status codes, ordering)?

A diff that is correct on 1 beats a diff that is prettier on 2-4. If both diffs
fix the root cause with equivalent tests and neither has a compat risk the other
lacks, say tie — do not invent a winner.

Answer with ONE JSON object and nothing else:

```json
{
  "winner": "1" | "2" | "tie",
  "root_cause": "<one line: which diff fixes the cause, which patches the symptom>",
  "pattern_reuse": "<one line>",
  "test_quality": "<one line: does any test assert an outcome, or only mocks?>",
  "minimality": "<one line>",
  "compat_risk": "<one line>"
}
```

---

## Task given to both authors

{TASK}

## Relevant files BEFORE the change

{BEFORE}

## DIFF-1

```diff
{DIFF1}
```

## DIFF-2

```diff
{DIFF2}
```
