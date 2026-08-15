# Task 1 — ship notification

## Goal

Notify a user their order shipped. A missing email address must not throw.

## Files in scope

`notifier.ts`, `notifier.test.ts`

## Acceptance criteria

- With an address: the mail is sent and the function returns `true`.
- **With a null address: nothing is sent and the function returns `false`.**

## Out of scope

Retries, templating, delivery receipts.
