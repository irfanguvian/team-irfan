# 2026-08-19 — harness×model matrix, first full run (haiku)

The v3 "workflow vs model" claim, measured: harness ∈ {bare Claude Code, OMC,
team-irfan v3.1} × model = **haiku** (`TG_BENCH_MODEL=haiku` →
`claude-haiku-4-5-20251001` pinned on every arm, `bench_model` stamped in every
row). 4 tasks × 3 arms × 3 rounds = 36 cells, all completed, byte-identical
prompts per task, one worktree + db + node_modules clone per cell. Total cost
**$8.14** (bare $2.10 · omc $3.14 · team $2.90). Full data:
`benchmarks/harness-v3/results/2026-08-19-haiku-v3/` (REPORT.md, results.csv,
per-cell diffs under runs/).

## Verdict

**On haiku, the harness does not rescue the model — it needs a minimum
orchestrator.** team-irfan wins 0/4 tasks; H1 (correctness) FAIL, H2 (harness
tax ≤1.5×: measured 2.30×) FAIL, H3 (containment) PASS, H4 (predictability)
FAIL. bare and omc, single-loop, both near-sweep the board.

## Correctness (new metric, deterministic per cell)

| Task | A bare | B omc | C team-irfan |
|---|---|---|---|
| T1 trivial | correct ×3 | correct ×3 | declined, correct ×2 |
| T2 feature | broken, correct-sloppy, correct | partial, correct ×2 | partial ×3 |
| T3 N+1 + contract trap | declined, correct ×2 | correct ×3 | declined ×3 |
| T4 root cause | correct ×3 | correct ×3 | correct ×3 |

Totals: bare **10/12** · omc **11/12** · team **5/12**. Zero `cheated` in 36
cells — no arm edited a protected test. Diff review: omc's T3 fix is a
textbook `include` join with the DTO preserved; every T4 cell fixed the real
timezone bug (`Intl.DateTimeFormat`), no `+7` hardcode; bare/T2/1 shipped
green hidden acceptance with its own new tests red.

## Why team lost — three distinct mechanisms, none of them "worse code"

1. **Headless turn-ending at the plan gate (T2 ×3, T1/1).** The haiku
   orchestrator plans — in the best cell it wrote the plan, ran the
   product-challenger round, passed `plan-gate` + `plan-check` — then ends
   its turn at the approval gate. In `claude -p`, an ended turn is an ended
   session: executors never spawn, acceptance stays at the fixture baseline.
2. **HAND-BACK on ambiguity (T3 ×3).** "Make it faster" trips the router's
   designed refusal (`no acceptance criterion`). Correct interactively;
   a forfeit headless, while the baselines simply fixed the N+1.
3. **One FAST/FULL mis-triage (T1/1).** Where team routed FAST it went
   5/5 correct — at ~2× bare's wall/cost.

## Harness bugs found and fixed by this run (all committed)

- `run.sh` waited on a pid that plugin daemons keep alive → every finished
  omc/team cell burned the 45-min cap as `fail(timeout)` (measured: a 113s
  cell recorded 3230s). Now polls for the terminal result object, reaps the
  tree, labels `api_error`, and auto-retries failed cells once.
- `TEAM_IRFAN_AUTO_APPROVE=1` was documented but wired into **no prompt**
  since inception — arm C could never pass its gate headless. Now honored by
  the router, benchmark-mode only. (Haiku still ends its turn at the gate —
  see finding 1 — so wiring it was necessary, not sufficient.)
- Scorer counted `.team-irfan/` runtime state as out-of-scope edits while
  excusing `.omc/`; now excluded alike. New `correctness` column
  (`correct | correct-sloppy | partial | broken | declined | cheated`) and
  `declined` for empty-diff refusals.
- Plugin 3.1.0 manifest: `hooks` reference removed (the CLI now auto-loads
  `hooks/hooks.json`; the reference double-loaded and failed the plugin).

## Actions (traceable to failed hypotheses)

1. H1 — headless FULL needs a driver: orchestrator must not end the turn at
   an auto-approved gate, or bench arm C needs a re-invoke loop until the
   summary exists.
2. H1/T3 — router should consume a provided `clarifications.md` before
   refusing on ambiguity.
3. H2 — tighten the FAST rubric; a wrongly-FULL one-liner pays the whole tax.

## Scope caveat

n=3 per cell, one model, the cheapest one — this measures "can the harness
carry a weak orchestrator" (no), not "does the harness add value on opus"
(unmeasured; the production matrix pins opus and `haiku: never` stands).
The sonnet half of the matrix and an opus reference run remain open.
