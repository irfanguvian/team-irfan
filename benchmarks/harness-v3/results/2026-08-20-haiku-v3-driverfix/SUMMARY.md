# Benchmark results — 2026-08-20-haiku-v3-driverfix

41 scored cells. Medians of the rounds present; spread is max/min cost across them.

| Task | Arm | rounds | pass | $ med | wall med | diff LOC | turns | tools | oos | spread |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | A bare | 3 | 100% | 0.119 | 72s | 5 | 16 | 0 | 0 | 1.57x |
| T1 | B omc | 3 | 100% | 0.151 | 92s | 5 | 15 | 0 | 0 | 1.58x |
| T1 | C team-irfan | 3 | 100% | 0.398 | 207s | 52 | 29 | 0 | 0 | 5.16x |
| T4 | A bare | 3 | 100% | 0.099 | 72s | 10 | 13 | 0 | 0 | 1.46x |
| T4 | B omc | 3 | 100% | 0.133 | 82s | 5 | 13 | 0 | 0 | 1.23x |
| T4 | C team-irfan | 3 | 100% | 0.199 | 112s | 10 | 10 | 0 | 0 | 8.16x |
| T2 | A bare | 3 | 100% | 0.523 | 338s | 136 | 63 | 62 | 0 | 1.72x |
| T2 | B omc | 3 | 0% | 0.230 | 111s | 199 | 27 | 26 | 0 | 3.68x |
| T2 | C team-irfan | 2 | 56% | 0.482 | 98s | 54 | 18 | 15 | 0 | 9.33x |
| T3 | A bare | 3 | 0% | 0.075 | 51s | 0 | 8 | 7 | 0 | 1.35x |
| T3 | B omc | 3 | 100% | 0.126 | 81s | 31 | 14 | 13 | 0 | 1.09x |
| T3 | C team-irfan | 3 | 100% | 1.235 | 267s | 77 | 1 | 21 | 1 | 8.57x |

- total spend: $22.57
- regression-gate failures: 5 of 41
- protected-test guard trips: 0 of 41

A cell with `regression = fail` or a tripped guard scores pass_rate 0 regardless of its acceptance result.

See `COVERAGE.txt` in this folder for which cells ran and the commands to finish the rest.
