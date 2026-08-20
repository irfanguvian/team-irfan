# Benchmark results — 2026-08-18-partial

24 scored cells. Medians of the rounds present; spread is max/min cost across them.

| Task | Arm | rounds | pass | $ med | wall med | diff LOC | turns | tools | oos | spread |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | A bare | 3 | 100% | 0.564 | 91s | 72 | 13 | 12 | 0 | 1.21x |
| T1 | B omc | 3 | 100% | 0.848 | 72s | 58 | 12 | 11 | 1 | 1.05x |
| T1 | C team-irfan | 3 | 100% | 1.214 | 108s | 59 | 13 | 12 | 0 | 1.13x |
| T4 | A bare | 3 | 100% | 0.523 | 78s | 50 | 12 | 11 | 0 | 1.29x |
| T4 | B omc | 3 | 100% | 0.638 | 45s | 17 | 8 | 7 | 0 | 1.14x |
| T4 | C team-irfan | 3 | 100% | 0.973 | 76s | 23 | 10 | 9 | 0 | 1.07x |
| T2 | A bare | 3 | 100% | 0.904 | 143s | 290 | 15 | 14 | 0 | 1.17x |
| T2 | B omc | 3 | 100% | 0.950 | 104s | 192 | 10 | 9 | 0 | 1.04x |
| T2 | C team-irfan | 0 | — | — | — | — | — | — | — | — |

- total spend: $19.56
- regression-gate failures: 0 of 24
- protected-test guard trips: 0 of 24

A cell with `regression = fail` or a tripped guard scores pass_rate 0 regardless of its acceptance result.

See `COVERAGE.txt` in this folder for which cells ran and the commands to finish the rest.
