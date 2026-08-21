# Benchmarks

Three families, one question each:

| dir | question | status |
|---|---|---|
| `tester/` + `run.sh` + `baselines/` | does a prompt diff to the QA agent help? — with a number | active |
| `harness-v3/` | three-arm head-to-head (bare vs OMC vs team-irfan) on pass rate + cost | **superseded for conclusions** — kept as the record |
| `harness-v4/` | the five falsifiable claims team-irfan is built on (verify, plan, predict, memory, quality) | current |

## Why v3 is superseded

v3's tasks saturated: every arm passed 100% of hidden acceptance at the opus
tier, so the only axis left was cost — where an orchestration layer
structurally loses. Its numbers (`harness-v3/results/`) remain the record of
that finding; no conclusion about team-irfan's value should be drawn from them
beyond "these four tasks don't separate the arms".

v4 (`harness-v4/`) scores what team-irfan is actually for and states, in
advance, what result falsifies each claim. Raw cost and wall time are reported
but not scored. Start at `harness-v4/README.md`; the design doc is
`harness-v4/SPEC.md`.
