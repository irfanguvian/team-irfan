# Router rubric cases

Seven sample tasks and the route the rubric in `agents/router.md` must produce.
Printed by `run-checks.sh` for Irfan to eyeball — a human judges these, no
agent scores them.

| # | Task | Expected | Why |
|---|---|---|---|
| 1 | "rename `qualifiesForBulkDiscount` to `isBulkEligible` in cart.ts" | **HAND-BACK** | one rename, under five minutes by hand. Running the graph on it costs more than doing it |
| 2 | "where does the bulk discount threshold live?" | **QUESTION** | asks, does not change. Grep and answer, zero agents |
| 3 | "fix the seeded bug in tests/fixture" | **FAST** | ≤2 files (`cart.ts` + its test), known pattern, no schema or contract change |
| 4 | "make it better" | **HAND-BACK** | too ambiguous to triage. No acceptance criterion can be stated in one sentence |
| 5 | "add a tiered discount table with per-customer overrides, a migration, and an admin endpoint" | **FULL** | 3+ files, schema change, API contract change, multi-surface |
| 6 | "`POST /invoices` returns 200 on invalid body. It should return 400. Fix it" | **FAST** | wrong and expected behavior in one sentence — that IS the acceptance criterion; finding the file is the executor's job |
| 7 | "the invoice list is slow. make it faster" — with `clarifications.md` at repo root | **FAST** | ambiguity is pre-answered in the shipped file (no contract change, judgement on the rest); refusing anyway forfeits a runnable task |

## Boundary notes

- Case 3 is the live smoke test. FAST, not FULL — two files and an existing
  pattern. If the router sends it FULL, the rubric is too timid and the cost
  shows up on every small fix.
- Case 4 is HAND-BACK, **not** QUESTION. The router does not get to ask a
  clarifying question and keep going; ambiguity hands the task back with the
  missing piece named.
- Case 1 is HAND-BACK even though it is trivially FAST-shaped. The tiebreak is
  explicit: Irfan's five minutes beat fifteen tool calls.
- Case 7 vs case 4: same vagueness, different route — the shipped
  `clarifications.md` flips it. No file at the repo root → HAND-BACK stands.
- A named-pattern perf bug (N+1) with consumers is FAST, not FULL: the
  contract suite is the deterministic protection and gate.sh runs it. FULL
  for that shape is the 2026-08-20 T3 failure — 19x bare's cost for the
  same one-file fix.
