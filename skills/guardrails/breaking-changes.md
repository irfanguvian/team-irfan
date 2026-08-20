# Breaking-change checklist

Loaded by executor, QA, qa-challenger, Lead, and lead-challenger. Reviewed by
the executor BEFORE writing `change-summary.md`, and by qa-challenger against
the diff-touching categories of the plan. Any hit is either **fixed** (the
compatible path) or declared **`INTENTIONAL BREAKING: <what>`** — which is
only valid when the approved plan already declares that behavior change. Lead
treats an undeclared hit as a blocker, never a footnote.

## Request contract

- optional field → required
- new required field
- field removed or renamed
- type changed
- enum values removed or narrowed
- validation tightened (stricter length / regex / range)
- content-type or encoding changed

## Response contract

- field removed / renamed
- type or nullability changed
- status code changed
- error shape changed
- pagination / envelope shape changed
- ordering guarantees changed

## Endpoints / routes

- route removed or renamed
- HTTP method changed
- auth newly required, or scope raised
- rate limit tightened

## Code level

- exported function signature changed (params added-required, reordered,
  removed)
- return type changed
- thrown / rejected error types changed
- exported symbol removed
- default value changed

## Data layer

- column dropped / renamed
- NOT NULL or UNIQUE added to an existing column
- enum altered
- irreversible migration
- index removal changing ordering-dependent queries

## Events / queues / jobs

- payload shape changed
- topic / queue renamed
- cron semantics changed

## Frontend

- component prop removed / renamed or made required
- route path changed
- persisted client state schema changed (localStorage / cookies)
- layout breakage at declared responsive viewports

## Rule A — old tests are a contract

If a change makes a **pre-existing** unit test fail, that is a
backward-compat break **by definition**. The executor stops and either
restores compatibility or flags `INTENTIONAL BREAKING: <what>` — valid only
if the approved plan already declares the change. Neither executors nor QA
may edit an existing test to make new work pass; changing a regression test
requires a plan-approved line.
