# Benchmark results — 2026-08-19-haiku-v3

36 scored cells. Medians of the rounds present; spread is max/min cost across them.

| Task | Arm | rounds | pass | $ med | wall med | diff LOC | turns | tools | oos | spread |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | A bare | 3 | 100% | 0.090 | 52s | 4 | 12 | 11 | 0 | 1.23x |
| T1 | B omc | 3 | 100% | 0.123 | 57s | 5 | 15 | 14 | 0 | 1.23x |
| T1 | C team-irfan | 3 | 100% | 0.208 | 101s | 0 | 21 | 20 | 0 | 6.58x |
| T4 | A bare | 3 | 100% | 0.106 | 66s | 10 | 13 | 12 | 0 | 1.22x |
| T4 | B omc | 3 | 100% | 0.137 | 76s | 10 | 14 | 13 | 0 | 1.46x |
| T4 | C team-irfan | 3 | 100% | 0.196 | 97s | 10 | 18 | 17 | 0 | 1.36x |
| T2 | A bare | 3 | 100% | 0.470 | 257s | 109 | 54 | 53 | 1 | 4.87x |
| T2 | B omc | 3 | 100% | 0.463 | 253s | 131 | 49 | 48 | 0 | 2.58x |
| T2 | C team-irfan | 3 | 12% | 0.135 | 56s | 0 | 12 | 11 | 0 | 30.67x |
| T3 | A bare | 3 | 100% | 0.084 | 56s | 29 | 8 | 7 | 0 | 1.51x |
| T3 | B omc | 3 | 100% | 0.095 | 46s | 29 | 8 | 7 | 0 | 1.12x |
| T3 | C team-irfan | 3 | 0% | 0.085 | 26s | 0 | 3 | 2 | 0 | 1.22x |

- total spend: $8.14
- regression-gate failures: 1 of 36
- protected-test guard trips: 0 of 36

A cell with `regression = fail` or a tripped guard scores pass_rate 0 regardless of its acceptance result.

See `COVERAGE.txt` in this folder for which cells ran and the commands to finish the rest.
