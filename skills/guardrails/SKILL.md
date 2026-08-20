---
name: team-graph-guardrails
description: Hard engineering rules every team-graph node obeys. Security, performance, API, database, testing, and naming. Read this before writing or reviewing any code in a team-graph run.
---

# Guardrails

Extracted from the global engineering rules and FUNDAMENTALS. These are the rules
that survive; they are not advice. A violation is a FAIL and goes back to the
executor.

Not in scope here: evaluation loops, telemetry, session metrics, mutation
scoring, golden-set replay. Team-graph does not measure itself. It ships work.

---

## 1. Naming and readability (checked on every diff)

Code is read far more than it is written. A reviewer must understand a function
from its name and signature alone.

- Name a function for the **behavior it produces**, not for how it does it.
  `chargeInvoice()` not `runPaymentLogic()`. `expireStaleSessions()` not
  `processSessions()`.
- No invented abbreviations. `request` not `req` in new code, `configuration`
  not `cfg`, `response` not `res`. Match the surrounding file if it already has
  a convention — consistency beats this rule inside one file.
- Booleans read as predicates: `isExpired`, `hasWriteAccess`, `canRefund`.
  Never `flag`, `status2`, `check`.
- A name that needs a comment to explain it is the wrong name. Fix the name,
  delete the comment.
- Test names state the behavior asserted, in a sentence:
  `it("rejects a refund once the invoice is settled")`, never
  `it("test refund 2")`.
- Function does two things joined by "and"? Split it or rename it honestly.
- Comments explain **why**, never **what**. The code already says what.

## 2. Testing

**Vitest. Never Jest.** For Node/TypeScript projects, always.

### Testing Trophy — weight effort in this order

1. **Static** — types, lint. Cheapest, catches the most. Free coverage.
2. **Integration** — the bulk of the work. Real database, real module wiring.
   Mock only third-party network boundaries.
3. **Unit** — pure logic, algorithms, edge-case branches. Few.
4. **E2E** — critical user paths only. Very few.

Default to integration. A unit test that mocks everything the function touches
asserts nothing but the mock.

### Test scenarios come from the plan, never from the diff

Derive cases from the plan task block's acceptance criteria. Writing tests by reading
the implementation produces tests that pass because they mirror the bug.

### Slop review — mandatory pass after writing tests

Reject and rewrite any test that:

- passes when the implementation body is deleted or returns a constant
- asserts on a mock's call rather than on a real outcome
- has no assertion, or asserts only "did not throw"
- is snapshot-only for logic that has a checkable value
- asserts implementation detail (private method calls, internal ordering)
  rather than observable behavior
- duplicates an existing test with different inputs and no new branch covered

State the outcome of this pass in the report if anything was rewritten.
`gate.sh` catches the mechanical cases (`expect(true)`, `.skip(`, `it.todo`,
empty bodies). It cannot catch the semantic ones. That is your job.

### Never edit a failing old test to make it green

A pre-existing test that fails after your change is **a bug in your change**
until proven otherwise. Fix the code.

Single exception: the feature's contract genuinely changed. Then all three:
1. Change the test, do not delete it.
2. Record old contract → new contract in `change-summary.md`.
3. Flag it explicitly in the report under "Fine or not".

Never weaken an assertion, widen a matcher, add a skip, or delete a case to get
green.

## 3. No fake completion

These are blockers, not evidence of progress:

- `TODO` / `FIXME` placeholders left in the changed lines
- `test.skip`, `test.only`, `it.todo`, `xit`, `describe.only`
- stub tests, empty test bodies
- unimplemented branches that `throw new Error("not implemented")`
- a function that returns a hardcoded value the tests happen to expect

Found any in your own diff? Implement it or report it as a blocker. Never ship
it as done.

## 4. Security — OWASP Top 10:2025

Note the 2025 ordering, not the 2021 list.

A01 Broken Access Control (SSRF now lives here) · A02 Security Misconfiguration ·
A03 Software Supply Chain Failures · A04 Cryptographic Failures · A05 Injection ·
A06 Insecure Design · A07 Authentication Failures ·
A08 Software/Data Integrity Failures · A09 Security Logging & Alerting Failures ·
A10 Mishandling of Exceptional Conditions

Two reflexes on every diff:

- **Trust boundary:** every request crossing a trust boundary gets an IDOR
  check. Ownership check on every resource accessed by id. No exceptions for
  "internal" endpoints.
- **Taint:** trace untrusted input to its sink. Unsanitized input reaching a
  query, a shell, a template, or a log line is a probable data exposure. Flag
  it even if it is outside the task scope — write it into `change-summary.md`,
  do not fix it silently.

Never simplify away: input validation at trust boundaries, error handling that
prevents data loss, security measures, accessibility basics.

## 5. Performance

- List endpoints **must** paginate. Default limit 20, max 100. No exceptions.
- **No query inside a loop.** Detect it (query in a loop, lazy relation access
  per item) and fix with joins / `include`, `WHERE id IN (...)` batching, or a
  dataloader. Never ship an N+1.
- **Bulk over loops.** Never create or update rows one at a time in a loop. Use
  `createMany`, `updateMany`, a single `UPDATE ... FROM (VALUES ...)`, or a
  CTE. One round-trip.
- No sync API on the request path: `*Sync`, `readFileSync`, `pbkdf2Sync`.
- Every column in a `WHERE` or `ORDER BY` is indexed, with the migration
  included in the same change.
- **Measure before judgment.** A performance claim needs p95/p99 numbers from a
  real load tool. "Faster" without numbers is not a claim, it is a guess.
- Handlers stay stateless. Anything per-request must be safe under parallel
  load. No race-prone read-modify-write — use atomic updates, upserts, or row
  locks.

## 6. API design

- Errors: RFC 9457 `application/problem+json`, the same shape everywhere.
- Pagination: cursor, not offset.
- Mutations: idempotency key.
- Money: never a float. Integer minor units, or decimal.
- Time: ISO-8601, UTC.
- Every outbound call: timeout + throttle + circuit breaker. All three.

## 7. Database

- **Transactions on every create and update path.** Multi-statement writes go
  in `prisma.$transaction` / `BEGIN..COMMIT`. Smallest correct scope, shortest
  possible duration.
- **Index check is mandatory, before and after query work:**
  1. Inspect existing indexes first (`\d table`, `pg_indexes`). Never duplicate.
  2. Run `EXPLAIN (ANALYZE, BUFFERS)` on the real query. Confirm the index is
     actually used.
  3. Column filtered together with others? Prefer one **composite** index
     matching the `WHERE` + `ORDER BY` column order over several single-column
     indexes.
  4. Never over-index. Every index costs writes and storage. An index that
     `pg_stat_user_indexes` shows unused gets flagged for removal, not joined
     by another one.
- Verify write-heavy changes against realistic row counts, not three-row toy
  data.

## 8. Efficiency and reuse

- Pick the most efficient implementation that stays simple. Measure in queries,
  allocations, and round-trips — not in cleverness.
- Reuse before writing. A helper, util, type, or pattern already in this
  codebase wins over a new one. Re-implementing what lives a few files over is
  the most common slop.
- No copy-paste variants of the same function. Extract the shared logic.
- Standard library before a dependency. Native platform feature before a
  library. Never add a dependency for what a few lines can do.

## 9. Breaking changes

**Critical.** Never ship a breaking change without Irfan's explicit acceptance.
Always solve with backward compatibility first. A breaking change discovered
mid-task stops the node and escalates — it is not an implementation detail.

**Rule A — old tests are a contract.** A pre-existing unit test failing under
new work is a backward-compat break by definition. The executor stops and
either restores compatibility or flags `INTENTIONAL BREAKING: <what>` — valid
only if the approved plan already declares that change. Neither executors nor
QA may edit an existing test to make new work pass.

**Checklist B.** The static breaking-change checklist lives in
`breaking-changes.md` beside this file. Executors walk it before
`change-summary.md`; qa-challenger walks it against the plan; Lead treats an
undeclared hit as a blocker, never a footnote.

## 10. Environment

- Docker port bindings are localhost only: `-p 127.0.0.1:PORT:PORT`. Never
  `0.0.0.0`.
- Local Postgres is local. Never point a dev task at a cloud database.
- **Never set `ANTHROPIC_API_KEY`** anywhere — env, launch agents, shell
  profiles.

---

## Enforcement

Every executor repeats these constraints when it hands off. Every review pass
checks each section against the diff. A violation is a FAIL and returns to the
executor with the section number named.
