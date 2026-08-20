## Results

| Task | Arm | pass (med) | $ (med) | wall (med) | oos files | spread |
|------|-----|-----------|---------|-----------|-----------|--------|
| T1 | A bare | 100% | $0.079 | 46s | 0 | 1.10x |
| T1 | B omc | 100% | $0.104 | 46s | 0 | 1.24x |
| T1 | C team-irfan | 100% | $0.248 | 96s | 0 | 1.83x |
| T2 | A bare | 100% | $0.644 | 373s | 0 | 2.39x |
| T2 | B omc | 100% | $0.430 | 243s | 0 | 6.90x |
| T2 | C team-irfan | 12% | $0.157 | 71s | 0 | 3.55x |
| T3 | A bare | 100% | $0.116 | 81s | 0 | 1.31x |
| T3 | B omc | 100% | $0.120 | 56s | 0 | 1.64x |
| T3 | C team-irfan | 100% | $2.300 | 729s | 2 | 14.05x |
| T4 | A bare | 100% | $0.094 | 56s | 0 | 1.28x |
| T4 | B omc | 100% | $0.128 | 66s | 0 | 1.14x |
| T4 | C team-irfan | 100% | $0.258 | 167s | 0 | 4.13x |

### Winner per task

- **T1**: A bare (pass 100%)
- **T2**: B omc (pass 100%)
- **T3**: A bare (pass 100%)
- **T4**: A bare (pass 100%)

### Hypotheses

- H1 correctness: FAIL — lost on ['T2']; strictly ahead on traps: False
- H2 harness tax: FAIL — T1 costs 3.14x the cheapest baseline (kill above 1.5x)
- H3 containment: FAIL — team 2 out-of-scope files vs bare 0
- H4 predictability: FAIL — team median spread 3.84x vs baselines 1.29x

### Decision

- team-irfan wins or ties 0/4 tasks (needs >= 3 of 4)
- complexity is earned only if that holds AND H2 holds AND H3 holds

### Where team-irfan lost

Per-cell correctness (from results.csv):

| Task | C team-irfan cells |
|---|---|
| T1 | broken (lint only), correct ×2 |
| T2 | stalled ×2, correct |
| T3 | correct-sloppy ×2, declined |
| T4 | correct ×2, declined |

Correct(+sloppy): **7/12** (was 5/12 on 2026-08-19). The router fix bought
what it aimed at: T3 is no longer refused (HAND-BACK ×3 → 2 of 3 shipped a
correct N+1 fix), and T1 routed FAST in all 3 rounds (verified: every T1
final message is the solo-executor 4-question report).

**One failure mechanism dominates — the orchestrator ends its turn where
the auto-approve design mandates continuation.** 4 of 12 cells, two
flavors, all verified against result.json:

1. **Zero-spawn stop (T2 r1, T2 r2, T4 r2).** The router triages
   correctly, narrates the next step — "Ready to proceed to STEP 1 when
   you approve the plan" / "Proceeding to Product planning phase" /
   "Delegating to solo executor" — and ends the turn without one Task
   call. No subagent ever ran. T2 r1 even invented an approval stop
   before STEP 1, a gate the design does not have there.
2. **Blocking question at the real gate (T3 r2).** Plan phase ran
   ($3.48, 37 tool calls), plan gates passed, then the orchestrator asked
   "Q4 (BLOCKING): confirm gate commands?" under TEAM_IRFAN_AUTO_APPROVE=1
   — which run.sh verifiably exports — and ended the turn. Empty diff.

Two consecutive prompt-level fixes (0b087cc, 86949df — the paragraph now
literally says "do not end the turn") have not closed this on haiku.

Secondary findings:

- **gate.sh runs no lint (T1 r1).** Verified: gate.sh does typecheck,
  tests, coverage, stub-scan — no lint step. The executor printed GATE
  PASS; the bench regression gate failed on one `no-unused-vars` in the
  new test. The guardrails skill itself ranks "Static — types, lint" as
  layer 1, so the harness's own gate contradicts its own guardrails.
- **The 2 oos files are not sloppiness — they are the guardrails
  working.** T3 r1/r3 each added a query-count-invariance test to
  `test/invoices.list.spec.ts` (real assertion: queries at limit=5 equal
  queries at limit=100). No existing test was touched or weakened.
  team-irfan was the only arm to leave an anti-N+1 regression test;
  T3's allowlist (`src/invoices/**`) makes that mandated test count as
  out-of-scope. H3's FAIL is a scope-accounting artifact, not a quality
  defect — but it does mean bench scope and guardrails contradict.
- **FULL is the wrong tier for T3 on cost, with a real quality caveat.**
  $2.30 med / 729 s vs bare $0.12 / 81 s. The plan phase did surface one
  genuine insight no baseline found (missing `orderBy` tiebreaker →
  pagination rows can repeat/vanish) — but the trap this task protects
  (response contract) is already enforced deterministically by the
  visible contract spec that gate.sh's test step runs. The challenger
  debate re-checks probabilistically what the suite checks
  deterministically.

When the pipeline runs to the end it delivers: T2 r3 shipped the full
refund endpoint, 8/8 hidden acceptance, $0.45 — under bare's median
($0.64). The losses are orchestration persistence, not code quality.

### Actions

1. **(H1) Deterministic headless driver, in the existing hook slots.**
   hooks.json already registers Stop and SubagentStop gates
   (subagent-gate.sh, plan-gate.sh precedents). Add a driver hook that —
   only when TEAM_IRFAN_AUTO_APPROVE=1 — blocks turn-end while the run
   dir has no final summary/handoff, and re-injects "continue: next node
   per the plan". Same rule under auto-approve: BLOCKING questions are
   forbidden; answer from clarifications/defaults, log the assumption.
   This is FUNDAMENTALS' own rule (deterministic gates never delegated to
   the prompt) applied to the harness itself. Prompt fixes are exhausted.
2. **(H2) FAST for single-file known-pattern perf fixes.** The correct
   T3 fix changes no contract, touches one file — it meets the FAST
   rubric's letter already; the router read "perf + consumers exist" as
   FULL. Codify: contract *risk* alone does not force FULL when a visible
   contract test exists (deterministic protection); challengers run only
   when the plan flags risk the suite cannot check.
3. **(H3) Close the gate and scope gaps.** Add `npm run lint` to gate.sh
   (aligns gate with guardrails layer 1). Pass the task allowlist into
   the executor handover's hard-constraints field; where the allowlist
   forbids `test/**`, the bench task must say where mandated tests go —
   bench and guardrails must stop contradicting each other.
