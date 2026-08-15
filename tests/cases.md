# Router rubric cases

Five sample tasks and the route the rubric in `agents/router.md` must produce.
Printed by `run-checks.sh` for Irfan to eyeball — a human judges these, no
agent scores them.

| # | Task | Expected | Why |
|---|---|---|---|
| 1 | "rename `qualifiesForBulkDiscount` to `isBulkEligible` in cart.ts" | **HAND-BACK** | one rename, under five minutes by hand. Running the graph on it costs more than doing it |
| 2 | "where does the bulk discount threshold live?" | **QUESTION** | asks, does not change. Grep and answer, zero agents |
| 3 | "fix the seeded bug in tests/fixture" | **FAST** | ≤2 files (`cart.ts` + its test), known pattern, no schema or contract change |
| 4 | "make it better" | **HAND-BACK** | too ambiguous to triage. No acceptance criterion can be stated in one sentence |
| 5 | "add a tiered discount table with per-customer overrides, a migration, and an admin endpoint" | **FULL** | 3+ files, schema change, API contract change, multi-surface |

## Boundary notes

- Case 3 is the live smoke test. FAST, not FULL — two files and an existing
  pattern. If the router sends it FULL, the rubric is too timid and the cost
  shows up on every small fix.
- Case 4 is HAND-BACK, **not** QUESTION. The router does not get to ask a
  clarifying question and keep going; ambiguity hands the task back with the
  missing piece named.
- Case 1 is HAND-BACK even though it is trivially FAST-shaped. The tiebreak is
  explicit: Irfan's five minutes beat fifteen tool calls.
