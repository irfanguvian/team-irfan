# Harness Benchmark v4

Head-to-head: **bare Claude Code** vs **OMC** vs **team-irfan**. Same model,
same fixture, same prompt text, byte for byte.

v4 exists because v3 measured the wrong thing. v3's tasks saturated at 100%
pass for every arm, so the scoreboard collapsed to cost — where an
orchestration layer can only lose. v4 measures the five things team-irfan is
actually built for, and defines in advance what result would falsify each one.
**Raw cost and wall time are reported but not scored.**

The spec this implements is `SPEC.md` (the v4 design doc). The goalposts below
were written before the first run and do not move afterwards.

## The five claims

| # | Claim | Team-irfan is FALSIFIED if |
|---|---|---|
| C1 | verify-driven reliability — its "done" is true | `false_done` rate ≥ any baseline, or it skips verification on any run |
| C2 | plan-then-execute | plan adherence < 0.8, or >1 replan per task |
| C3 | predictable effort | median \|prediction error\| > 30%, or cost spread wider than both baselines |
| C4 | memory — never the same hole twice | session B not cheaper AND not faster to locate than session A, or it repeats the recorded mistake |
| C5 | generated quality | loses the pairwise majority vs either baseline on any task |

## Quickstart

```bash
cd benchmarks/harness-v4

bin/init.sh              # fixture repo (5 orphan-commit tags) + 3 arm configs
bin/selftest.sh          # prove scorer + extract.py. no agents, no cost
bin/judge.sh --calibrate # prove the judge discriminates. small LLM cost
bin/run.sh all --dry-run # print every command, spawn nothing
bin/run.sh all           # ~45 sessions, STRICTLY SEQUENTIAL. the expensive part
bin/score.sh all         # gates, hidden acceptance, extract.py -> results/results.csv
bin/judge.sh all         # pairwise blind review + MEM same-hole checks
bin/report.py            # five hypothesis verdicts + tables + honesty section
```

Picking it back up after a break or crash — always start here:

```bash
bin/status.sh            # what ran, what did not, the exact next command
```

`run.sh all` skips cells that already have a result — it is also the resume
path. A lockfile (`runs/.lock`) refuses a second concurrent invocation; there
is no parallel mode to misuse. Every cell writes its result atomically, so a
crash loses at most one cell.

## Arms

| Arm | Config | Invocation |
|---|---|---|
| A `bare` | empty settings.json, no plugins, MCP off | task prompt as-is |
| B `omc` | operator's setup minus the team-graph rule | task prompt as-is |
| C `team` | operator's setup verbatim | `/team-irfan "<prompt>"` |

Same pinned model per run (`BENCH_MODEL`, default `claude-opus-5`). Run the
opus tier first; the sonnet tier is the interesting one — reliability claims
only differentiate when the model alone can't carry the task.

## Tasks

One fixture: the v3 NestJS+Prisma invoices app plus three thin modules
(`customers`, `refunds`, `audit`) added by `fixture-patches/base/`. Each task
state is a single ORPHAN commit (`<task>-base` tag) — no state's git history
shows another state's bug being planted.

| Task | Rounds | What it tests | Trap |
|---|---|---|---|
| Q1 pure question | 3 | C1/C2 routing; memory warm-up | arm C spins agents for a question; ANY diff = fail |
| F1 one-liner (v3 T1) | 3 | harness-tax canary (reported, not scored) | full pipeline for one line |
| B1 band-aid | 3 | C1, C5 | Jakarta special-case in the caller passes visible, fails 2 hidden consumers of the shared util |
| N5 five N+1s | 2 | centrepiece: C1/C2/C3/C5 | fixing 3 of 5 and declaring done; contract tests pin every shape |
| MEM-A / MEM-B | 2 | C4 | pair shares ONE persistent clone per (arm, round); session B's only head start is what session A left on disk |

Hidden acceptance = query-count assertions (≤3 SELECTs for a 50-row page; ≤4
for `/refunds` whose nested include legitimately costs 4) + the visible
contract suite. Protected files (contract tests, the failing visible test) —
editing one scores 0.

Q1's answer, for the record: the `audit` controller has no guard; everything
else uses `ApiKeyGuard`.

## What gets extracted

`bin/extract.py`, zero LLM, unit-tested against two committed sample
transcripts (`selftest/samples/`): `verified_before_done`, `false_done` (with
score.sh), `rework_loops`, `plan_exists`, `predicted_calls` (arm C:
`.team-irfan/runs/*/plan.json` chosen option's `expected_calls`),
`plan_adherence`, `replans`, `calls_to_locate` (MEM). `plan_adherence` null is
reported as "did not plan", not skipped — the baselines not planning IS claim
C2.

## Quality review (C5)

Pairwise, blind, order-randomized: `bin/judge.sh`. The judge sees the task,
the before-files, two anonymous diffs — never arm names, transcripts, or
costs. Every pairing judged twice with presentation order swapped; a flip
between passes is recorded as tie. Calibration gate
(`judge/calibration/`, three planted pairs: root-cause vs band-aid, real vs
vacuous tests, genuine tie) must pass before any real judgment counts. One
judge model for the whole matrix (`JUDGE_MODEL`, default `claude-opus-5`).

## Honesty section (goes in every published report verbatim)

- Arm C's plan gate is auto-approved; the measured system is team-irfan
  **without** its human check.
- The quality reviewer is an LLM. It passed calibration on N planted pairs;
  its verdicts are pairwise and blind, but it is not a human reviewer and
  a systematic style preference could survive calibration.
- The memory comparison is asymmetric **by design** — it measures a capability
  the baselines don't have, on identical inputs.
- If C1 and C5 come back tied at the opus tier, the honest conclusion is that
  at this model tier and fixture size, the harness's checks are redundant —
  run the sonnet tier before concluding anything.
- n per cell is 2–3. Direct run review is valid at any n; aggregate tuning
  of team-irfan itself stays blocked below n=5, as in v3.

## Layout

```
harness-v4/
  SPEC.md                the v4 design doc, verbatim
  tasks/<T>/             PROMPT.md + scope.allowlist + hidden/ + judge.files
                         (+ bugfile.txt for MEM: the calls_to_locate target)
  fixture-patches/       base/ (clean new modules) + n5/ b1/ mem/ (seeded bugs)
                         + ref/ (reference fixes, selftest + calibration only)
  judge/                 prompt.md, same-hole.md, calibration/pair-*/
  bin/                   init, selftest, run, score, extract, judge, report, status
  runs/                  per-cell artifacts (gitignored)
  results/               results.csv + judgments/ — the durable record
```
