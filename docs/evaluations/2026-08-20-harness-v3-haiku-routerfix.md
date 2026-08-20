# 2026-08-20 — harness×model matrix, haiku, after the router fix

Second full 36-cell run on `TG_BENCH_MODEL=haiku`, same tasks, same scorer
(selftest green), one variable changed: commit 86949df — router consumes
`clarifications.md` before refusing, FAST rubric covers stated-behavior
bugfixes, auto-approve paragraph says "do not end the turn".
Published: `benchmarks/harness-v3/results/2026-08-20-haiku-v3-routerfix/`.

## Verdict

team-irfan wins or ties **0/4** tasks. All four hypotheses FAIL
(H1 lost T2 · H2 T1 tax 3.14x vs 1.5x kill · H3 2 oos files · H4 spread
3.84x vs 1.29x). But correctness moved: **7/12 correct cells, up from
5/12** — the fix bought exactly what it aimed at and nothing else.

## What the fix bought

- **T3 unblocked.** 08-19: HAND-BACK ×3, 0%. Now: 2/3 shipped a correct
  N+1 fix (`include` batching, contract preserved). The clarifications
  file is consumed as designed.
- **T1 triage fixed.** No FULL mis-route of the one-liner; all 3 rounds
  executed (2 correct, 1 lint-broken).

## What still fails — one mechanism, two flavors

**The orchestrator ends its turn where the auto-approve design mandates
continuation: 4 of 12 cells.**

- *Zero-spawn stop* (T2 r1+r2, T4 r2): correct triage, then "Proceeding to
  Product planning" / "Delegating to solo executor" — and turn-end with no
  Task call. No subagent ever ran. T2 r1 invented an approval stop before
  STEP 1, a gate the design does not place there.
- *Blocking question at the real gate* (T3 r2): plan phase completed
  ($3.48), gates passed, then "Q4 (BLOCKING): confirm gate commands?"
  under TEAM_IRFAN_AUTO_APPROVE=1 (verifiably exported by run.sh).

Two prompt fixes in two runs (0b087cc, 86949df) have not closed it.
Conclusion: on haiku, turn persistence must be a **deterministic hook**,
not prose — the hook slots (Stop/SubagentStop) already exist.

Secondary, each 1–2 cells:

- **gate.sh runs no lint** — T1 r1 printed GATE PASS, bench failed on one
  unused import. The guardrails skill ranks "types, lint" as layer 1; the
  harness's own gate contradicts its own guardrails.
- **The 2 oos files are the guardrails working, not slop.** T3 r1/r3 added
  a query-count-invariance regression test (limit=5 queries == limit=100
  queries) — a real assertion no baseline arm shipped. T3's allowlist
  (`src/invoices/**`) counts that mandated test as out-of-scope: H3's FAIL
  is a scope-accounting conflict between bench and guardrails.
- **FULL tier for a one-file fix** — $2.30 med / 729 s vs bare $0.12/81 s.
  Honest caveat: the plan phase surfaced one real insight no baseline
  found (missing orderBy tiebreaker), but the task's actual trap (response
  contract) is already protected deterministically by the visible contract
  spec the gate's test step runs.

## Harness observations from this run

- `wall_sec=900` rows are the runner's poll cap, not agent time
  (result.json duration 41 s on T3 r2). Label them in the CSV.
- T3/omc/3 `broken` is a 30 s vitest hookTimeout in the contract test at
  228 s suite duration — parallel-scoring flakiness, not a regression the
  agent caused. Consider serializing scoring or one retry.
- `cost_usd` (CLI-reported, used in the CSV) and `cost_recomputed_usd`
  diverge up to 10x on team cells. Pick one authoritative and document it.

## Actions (traceable)

1. H1 → deterministic headless driver in the existing Stop/SubagentStop
   hook slots: under TEAM_IRFAN_AUTO_APPROVE=1, block turn-end until the
   run's final summary exists (budget-capped), forbid BLOCKING questions —
   answer from clarifications/defaults and log the assumption. Prompt
   fixes are exhausted; FUNDAMENTALS' deterministic-over-probabilistic
   rule applied to the harness itself.
2. H2 → the correct T3 fix meets the FAST rubric's letter (1 file, known
   pattern, no contract change); codify that contract *risk* with a
   visible contract test does not force FULL, and run challengers only
   when the plan flags risk the suite cannot check deterministically.
3. H3 → add lint to gate.sh (aligns gate with guardrails layer 1); put the
   task allowlist in the executor handover's hard-constraints field; make
   bench scope and the tests-with-every-change rule stop contradicting.

## Scope caveat

Still haiku-only. This run measures "can the harness rescue the cheapest
orchestrator" — answer so far: only with a deterministic driver. The
production-model (opus) matrix remains unmeasured, and every baseline still
scores 100%, so the task set cannot show upside, only tax — harder tasks
are needed before any pro-harness conclusion is possible.
