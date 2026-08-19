# Task 1 — plain amount rendering for the invoice export

## Goal

The invoice export needs amounts without a currency prefix: `1,234.56`, not
`IDR 1,234.56`.

## Files in scope

`format.ts`, `format.test.ts`

## Acceptance criteria

- `formatMinor(123456)` renders `1,234.56` for the export.
- **Every existing consumer keeps its current output.** The checkout summary
  (`checkout.ts`) is a shipped endpoint whose `display` field is pinned by a
  contract test — it must keep showing `IDR 1,234.56`.

## Out of scope

Rounding rules, negative amounts, new currencies.
