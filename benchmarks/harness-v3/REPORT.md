## Results

| Task | Arm | pass (med) | $ (med) | wall (med) | oos files | spread |
|------|-----|-----------|---------|-----------|-----------|--------|
| T1 | A bare | 100% | $0.119 | 72s | 0 | 1.57x |
| T1 | B omc | 100% | $0.151 | 92s | 0 | 1.58x |
| T1 | C team-irfan | 100% | $0.398 | 207s | 0 | 5.16x |
| T2 | A bare | 100% | $0.523 | 338s | 0 | 1.72x |
| T2 | B omc | 0% | $0.230 | 111s | 0 | 3.68x |
| T2 | C team-irfan | 56% | $0.482 | 98s | 0 | 9.33x |
| T3 | A bare | 0% | $0.075 | 51s | 0 | 1.35x |
| T3 | B omc | 100% | $0.126 | 81s | 0 | 1.09x |
| T3 | C team-irfan | 100% | $1.235 | 267s | 1 | 8.57x |
| T4 | A bare | 100% | $0.099 | 72s | 0 | 1.46x |
| T4 | B omc | 100% | $0.133 | 82s | 0 | 1.23x |
| T4 | C team-irfan | 100% | $0.199 | 112s | 0 | 8.16x |

### Winner per task

- **T1**: A bare (pass 100%)
- **T2**: A bare (pass 100%)
- **T3**: B omc (pass 100%)
- **T4**: A bare (pass 100%)

### Hypotheses

- H1 correctness: FAIL — lost on ['T2']; strictly ahead on traps: False
- H2 harness tax: FAIL — T1 costs 3.34x the cheapest baseline (kill above 1.5x)
- H3 containment: FAIL — team 1 out-of-scope files vs bare 0
- H4 predictability: FAIL — team median spread 8.36x vs baselines 1.51x

### Decision

- team-irfan wins or ties 0/4 tasks (needs >= 3 of 4)
- complexity is earned only if that holds AND H2 holds AND H3 holds

### Where team-irfan lost

Scored 11/12 team cells (T2/team/1 missing: 45 min timeout, retry aborted by operator).
9/11 correct or correct-sloppy. The two losses are both zero-spawn stops where the
Stop-hook driver read a transcript that did not yet contain the turn-ending message
(T2/team/3 FULL, T4/team/1 FAST). Cost columns for arm C are contaminated: 6 of 12
cells spawned opus/sonnet subagents despite TG_BENCH_MODEL=haiku — 76% of the arm's
spend. Full analysis: docs/evaluations/2026-08-20-harness-v3-haiku-driverfix.md

### Actions

1. H1/H4 — driver reads `last_assistant_message`; FAST terminal check anchored to a `Verdict:` line.
2. H2/H4 — PreToolUse hook rewrites Agent.model when TG_BENCH_MODEL is set; re-run arm C.
3. Harness — score.sh snapshots transcripts; run.sh keeps result.attempt1.json; report.py prints n.
