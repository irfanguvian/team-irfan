## Results

| Task | Arm | pass (med) | $ (med) | wall (med) | oos files | spread |
|------|-----|-----------|---------|-----------|-----------|--------|
| T1 | A bare | 100% | $0.090 | 52s | 0 | 1.23x |
| T1 | B omc | 100% | $0.123 | 57s | 0 | 1.23x |
| T1 | C team-irfan | 100% | $0.208 | 101s | 0 | 6.58x |
| T2 | A bare | 100% | $0.470 | 257s | 1 | 4.87x |
| T2 | B omc | 100% | $0.463 | 253s | 0 | 2.58x |
| T2 | C team-irfan | 12% | $0.135 | 56s | 0 | 30.67x |
| T3 | A bare | 100% | $0.084 | 56s | 0 | 1.51x |
| T3 | B omc | 100% | $0.095 | 46s | 0 | 1.12x |
| T3 | C team-irfan | 0% | $0.085 | 26s | 0 | 1.22x |
| T4 | A bare | 100% | $0.106 | 66s | 0 | 1.22x |
| T4 | B omc | 100% | $0.137 | 76s | 0 | 1.46x |
| T4 | C team-irfan | 100% | $0.196 | 97s | 0 | 1.36x |

### Winner per task

- **T1**: A bare (pass 100%)
- **T2**: B omc (pass 100%)
- **T3**: A bare (pass 100%)
- **T4**: A bare (pass 100%)

### Hypotheses

- H1 correctness: FAIL — lost on ['T2', 'T3']; strictly ahead on traps: False
- H2 harness tax: FAIL — T1 costs 2.30x the cheapest baseline (kill above 1.5x)
- H3 containment: PASS — team 0 out-of-scope files vs bare 1
- H4 predictability: FAIL — team median spread 3.97x vs baselines 1.35x

### Decision

- team-irfan wins or ties 0/4 tasks (needs >= 3 of 4)
- complexity is earned only if that holds AND H2 holds AND H3 holds

### Correctness — the per-cell quality verdict

Deterministic label per cell (`correct` · `correct-sloppy` = correct but
out-of-scope edits · `partial` · `broken` = red regression/build ·
`declined` = empty diff, nothing generated · `cheated` = edited a protected
test). The generated diff behind every label is in
`runs/<T>/<arm>/<r>/diff.txt`.

| Task | A bare | B omc | C team-irfan |
|---|---|---|---|
| T1 | correct ×3 | correct ×3 | declined, correct ×2 |
| T2 | broken, correct-sloppy, correct | partial, correct ×2 | partial ×3 |
| T3 | declined, correct ×2 | correct ×3 | declined ×3 |
| T4 | correct ×3 | correct ×3 | correct ×3 |

Totals: **bare 10/12 correct** (1 broken, 1 declined) · **omc 11/12
correct** (1 partial) · **team-irfan 5/12 correct** (3 partial, 4 declined).
Nobody cheated: 0 protected-test edits in 36 cells.

What the diffs actually show (quality review):

- **T3 (N+1 + contract trap):** omc's fix is textbook — `include:
  { customer: ... }` replacing the per-row `findUnique`, DTO shape
  preserved, contract test green. bare matched it in 2 of 3 rounds; its
  third round diagnosed the N+1 correctly in prose and shipped **no code**.
  Nobody flattened the DTO — the trap caught no one, it was refusals that
  cost points.
- **T4 (root cause):** all nine cells fixed the real bug
  (`Intl.DateTimeFormat` with the target `timeZone`), no `+7` hardcodes, no
  test edits. On haiku, the trap the task was built around simply didn't
  bite.
- **T2 (feature):** bare/1 shipped 8/8 hidden acceptance but its own new
  visible tests were red (`broken` — it didn't run its suite before
  finishing). team-irfan never got to executors (below).

### Where team-irfan lost

Not on code quality — on **orchestrator persistence in headless mode**:

1. **T2 (all 3 rounds): the FULL pipeline never reached an executor.** The
   haiku orchestrator routed FULL, planned (in later attempts: wrote the
   plan, ran the challenger round, passed both plan hooks) — and then ended
   its turn at the approval gate, even with `TEAM_IRFAN_AUTO_APPROVE=1`
   honored in the prompt. In `-p` mode an ended turn is an ended session.
   The 1/8 acceptance passes are the fixture's pre-existing behavior, not
   work. First-pass rounds stalled the same way for a second reason (the
   auto-approve env var wasn't wired into the router at all — fixed during
   this run and the cells re-run).
2. **T3 (all 3 rounds): HAND-BACK by design.** "The invoice list is slow.
   Make it faster" tripped the router's ambiguity rule
   (`no acceptance criterion`) and it refused to run — one line, empty
   diff. Defensible interactively (the operator would answer and re-run);
   in a headless benchmark it scores 0 while the baselines just went and
   fixed the N+1.
3. **T1 round 1: same early-stop** after routing FULL (a mis-triage of a
   one-liner; rounds 2–3 routed FAST and were correct at ~2× bare's cost).

The pattern: team-irfan's FAST path works on haiku (5/5 correct where it
ran to completion via FAST). The FULL path requires the main-thread model
to keep driving for 30+ sequential turns, and haiku reliably stops at or
before the gate. bare/omc are single-loop and never expose that surface.
On this model, the harness's correctness machinery (gates, challengers, QA)
was never reached — so it could not pay for its planning overhead.

### Actions

1. **(H1) Headless FULL needs a driver.** Either the orchestrator honors
   auto-approve *and continues in the same turn* (prompt: "do not end the
   turn at the gate in benchmark mode"), or benchmark arm C runs FULL under
   a loop that re-invokes until the summary exists. Until then, headless
   results measure haiku's turn discipline, not the pipeline.
2. **(H1/T3) HAND-BACK vs clarifications:** when a task ships a
   `clarifications.md`, the router should consume it before refusing —
   refusal-on-ambiguity is a feature interactively and a forfeit headless.
3. **(H2) T1 mis-triage:** 1 of 3 trivial rounds routed FULL. Tighten the
   FAST rubric's "one file, known pattern" test — a wrongly-FULL one-liner
   is the whole harness tax with none of the benefit.

**Caveat on scope:** this matrix ran on `TG_BENCH_MODEL=haiku` only —
deliberately the cheapest, weakest orchestrator. It answers "does the
harness rescue a weak model?" (no — it needs a minimum orchestrator) and
not "does the harness add value on the production model?" (`opus`, where
the model matrix normally runs it; unmeasured here). `bench_model=haiku` is
stamped in every metrics row so these numbers can never be read as
production.
