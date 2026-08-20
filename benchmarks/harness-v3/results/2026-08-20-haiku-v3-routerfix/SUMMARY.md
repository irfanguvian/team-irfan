# Benchmark results — 2026-08-20-haiku-v3-routerfix

36 scored cells. Medians of the rounds present; spread is max/min cost across them.

| Task | Arm | rounds | pass | $ med | wall med | diff LOC | turns | tools | oos | spread |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | A bare | 3 | 100% | 0.079 | 46s | 5 | 10 | 9 | 0 | 1.10x |
| T1 | B omc | 3 | 100% | 0.104 | 46s | 5 | 9 | 8 | 0 | 1.24x |
| T1 | C team-irfan | 3 | 100% | 0.248 | 96s | 28 | 23 | 22 | 0 | 1.83x |
| T4 | A bare | 3 | 100% | 0.094 | 56s | 10 | 12 | 11 | 0 | 1.28x |
| T4 | B omc | 3 | 100% | 0.128 | 66s | 10 | 13 | 12 | 0 | 1.14x |
| T4 | C team-irfan | 3 | 100% | 0.258 | 167s | 5 | 2 | 11 | 0 | 4.13x |
| T2 | A bare | 3 | 100% | 0.644 | 373s | 127 | 71 | 70 | 0 | 2.39x |
| T2 | B omc | 3 | 100% | 0.430 | 243s | 127 | 45 | 44 | 0 | 6.90x |
| T2 | C team-irfan | 3 | 12% | 0.157 | 71s | 0 | 16 | 15 | 0 | 3.55x |
| T3 | A bare | 3 | 100% | 0.116 | 81s | 48 | 9 | 9 | 0 | 1.31x |
| T3 | B omc | 3 | 100% | 0.120 | 56s | 29 | 7 | 8 | 0 | 1.64x |
| T3 | C team-irfan | 3 | 100% | 2.300 | 729s | 43 | 10 | 37 | 2 | 14.05x |

- total spend: $14.15
- regression-gate failures: 3 of 36
- protected-test guard trips: 0 of 36

A cell with `regression = fail` or a tripped guard scores pass_rate 0 regardless of its acceptance result.

See `COVERAGE.txt` in this folder for which cells ran and the commands to finish the rest.
