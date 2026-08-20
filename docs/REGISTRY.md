# Registry

Context database for this project. Searched, not read whole.
Grep by tag: `FEAT:` `MOD:` `STATUS:` `DEC:`

## Index
| Feature | Modules | Latest | Status |
|---|---|---|---|
| harness-v3 benchmark | benchmarks/harness-v3, hooks | R-0001 | partial |

## Entries

### R-0001 · 2026-08-20 · [FEAT:harness-v3] [MOD:benchmarks/harness-v3,hooks] [STATUS:partial] [DEC:yes]

**Input**
Continue the haiku benchmark run for plugin 3.1.2 (Stop-hook driver): finish T2+T3 all arms, score, publish, analyse.

**Output**
- files: `results/2026-08-20-haiku-v3-driverfix/`, `docs/evaluations/2026-08-20-harness-v3-haiku-driverfix.md`, `bin/score.sh`, `bin/publish.sh`, `RESUME.md`
- change: 35/36 cells scored (T2/team/1 timed out, retry operator-aborted); 0/4 hypotheses hold; team 9/11 correct; 76% of team spend on opus/sonnet subagents despite TG_BENCH_MODEL=haiku.
- decision: plugin not touched mid-run (one variable per run); harness-only fixes landed (score.sh all rewrites CSV, publish.sh survives incomplete matrix). Driver `last_assistant_message` fix and PreToolUse model-pin hook deferred to next plugin version.
- tests: `bin/selftest.sh` green 14:27 (pre-run); bash -n on edited scripts.

**Verdict**
partial — run complete and published, but cost numbers for arm C are not haiku-comparable; re-run arm C after the model-pin hook.
