# Harness Benchmark v3

Head-to-head: **team-irfan** vs **bare Claude Code** vs **OMC**. Same model, same
repo, same task text.

The point is not to prove team-irfan wins. It is to find out whether the extra
complexity pays for itself, and where it does not.

---

## Quickstart

```bash
cd benchmarks/harness-v3

bin/init.sh                        # build the fixture repo + the three arm configs
bin/selftest.sh                    # prove the scorer works. no agents, no cost
bin/run.sh all --dry-run           # see exactly what would be spawned. costs nothing
bin/run.sh all                     # 36 agent sessions. this is the expensive part
bin/score.sh all                   # hidden tests, gates, tokens -> runs/results.csv
bin/report.sh > REPORT.md          # medians + the four hypothesis verdicts
```

Smaller first run — the two tasks most likely to falsify a hypothesis:

```bash
bin/run.sh all --tasks T1,T3       # 18 sessions instead of 36
```

One cell, for debugging the harness itself:

```bash
bin/run.sh T1 bare 1 && bin/score.sh T1 bare 1
```

---

## What it measures

Four hypotheses, written down before the first run. If one fails, that part of
the harness did not earn its keep — the goalpost does not move afterwards.

| # | Hypothesis | Fails if |
|---|---|---|
| **H1** correctness | team-irfan matches both baselines everywhere, and beats them on the traps (T3, T4) | it loses any task on median pass rate |
| **H2** harness tax | on trivial work (T1) it costs no more than 1.5x the cheapest baseline | above 1.5x — the fast path is broken |
| **H3** containment | it touches fewer out-of-scope files | equal to or worse than bare |
| **H4** predictability | its cost varies less across the 3 rounds | spread is no tighter than the baselines |

H4 is the one that matters for unbounded runs. H1 is table stakes.

---

## The four tasks

Each one is built so a specific arm can lose in a specific, diagnosable way.

**T1 — trivial fix.** `POST /invoices` answers 200 on an invalid body; it should
answer 400. One line. Measures what the harness costs when no orchestration is
needed. *Failure mode: arm C spins up the full pipeline for a one-liner.*

**T2 — normal feature.** Add a paginated, guarded `GET /invoices/:id/refunds`
following the existing list endpoint. Eight hidden tests. *Failure mode: the
baselines skip edge cases or invent a new pattern instead of copying the one
already there.*

**T3 — ambiguous, with a compatibility trap.** "The invoice list is slow. Make it
faster." Underspecified on purpose. There is a real N+1 on `invoice.customer`
(52 SELECTs for a 50-row page) and a consumer contract test pinning the exact
response shape. *Failure mode: it "optimises" by flattening the DTO or dropping
a field — fast, and broken for every consumer. Breaking the contract is a hard
fail no matter how fast the result is.*

**T4 — root cause vs band-aid.** `test/reports.spec.ts` fails for `Asia/Jakarta`.
The visible test only covers a zone with no DST, so a hardcoded `+7` passes it.
Hidden tests cover `Pacific/Auckland` and `America/New_York`. *Failure mode: an
offset hardcode, or quietly rewriting the failing test. Editing the given test
is an automatic zero.*

---

## Fairness

The prompt text is read from `tasks/<T>/PROMPT.md` and passed byte for byte to
all three arms. Exactly two things differ between them:

| Arm | `CLAUDE_CONFIG_DIR` | Prompt |
|---|---|---|
| A bare | `configs/bare` — empty CLAUDE.md, no plugins, MCP off at the command line | as written |
| B omc | `configs/omc` — the operator's real setup, minus the team-graph section of CLAUDE.md | as written |
| C team-irfan | `configs/team` — the operator's real setup, verbatim | `/team-irfan ` + as written |

B and C therefore isolate one variable: the team-graph pipeline. A is the only
truly independent baseline — weight it accordingly.

Every run gets its own git worktree, its own SQLite file, and its own cloned
`node_modules`, so nothing leaks between rounds. Session transcripts land under
each arm's own config dir, so one arm cannot read another's.

---

## Intervention policy

Operator behaviour is a hidden variable, so it is scripted, not improvised.

1. **Plan gate (arm C).** Auto-approved via `TEAM_IRFAN_AUTO_APPROVE=1`. Never
   steered. If the plan is wrong, it gets approved and the harness fails — the
   harness is what is under test, not the operator's judgement.
2. **Clarifying questions.** Answered only from `tasks/<T>/clarifications.md`.
   Anything not covered gets exactly `use your judgement`, logged as a human turn.
3. **Stuck or looping.** No rescue. Hard stop at 45 minutes (`MAX_SEC`) or 150
   turns (`MAX_TURNS`), recorded as `fail(timeout)` with cost as measured.
4. **Never** paste error output, hints, or file paths the agent did not find itself.

This ships as Mode B (headless). The plan gate is auto-approved, so what is
measured is the harness **without** its human check. Say so in the report.

---

## How a run is scored

`bin/score.sh` runs in this order, and the order is the point:

1. `git add -A && git diff --cached` — the full diff, including new files.
2. Out-of-scope count: every changed file matched against `tasks/<T>/scope.allowlist`.
3. Protected-test guard: T3 may not touch `test/invoices.contract.spec.ts`,
   T4 may not touch `test/reports.spec.ts`.
4. **Regression gate, before the hidden tests are copied in** — visible suite,
   `npm run build`, `npm run lint`. "The pre-existing suite is green" has to mean
   green without the acceptance tests present.
5. Hidden acceptance tests copied in from `acceptance/<T>/`, then run.
6. Tokens, tool calls, and cost from the session transcript.

A failed gate or a touched protected test scores `pass_rate = 0`, whatever the
acceptance result was.

### The numbers

| Column | Where it comes from | Weight |
|---|---|---|
| `pass_rate` | hidden tests passed / total | primary |
| `regression` | visible suite + build + lint | gate |
| `cost_usd` | `total_cost_usd` from Claude Code's own JSON result | primary |
| `oos_files` | diff vs `scope.allowlist` | primary (H3) |
| `spread` | max/min `cost_usd` across the 3 rounds | primary (H4) |
| `tokens_*`, `tool_calls`, `wall_sec`, `diff_loc`, `num_turns` | session transcript, `meta.json` | supporting |

`cost_usd` is Claude Code's own figure, which already prices whatever model mix
the run used — including arm C's subagents. `cost_recomputed_usd` re-derives it
from the transcript and `pricing.json` as a cross-check; if the two disagree by
much, trust the first and fix the second.

### Winner, per task

1. Highest median `pass_rate`.
2. Tie → lowest median `cost_usd`.
3. Still tied → lowest median `wall_sec`.

Median of 3, not mean. With n=3 the median is the honest summary.

**team-irfan earns its complexity if and only if** it wins or ties on at least 3
of 4 tasks, **and** H2 holds on T1, **and** H3 holds. Winning T2/T3/T4 while
costing 8x on T1 means the router is broken — fix the router, not the rule.

---

## Layout

```
harness-v3/
  bin/init.sh        build the fixture repo, its tags, and the arm configs
  bin/run.sh         spawn agents. the only script that costs money
  bin/score.sh       gates + hidden tests + metrics -> runs/results.csv
  bin/collect.sh     one run -> json (tokens, tool calls, cost)
  bin/report.sh      results.csv -> the report
  bin/selftest.sh    canned patches -> asserts the scorer grades them correctly
  selftest/          those patches: one correct fix per task, plus both band-aids
  fixture/           the NestJS + Prisma + SQLite service under test
  variants/t4/       the broken date helper that t4-base ships with
  tasks/T1..T4/      PROMPT.md, scope.allowlist, clarifications.md
  acceptance/T1..T4/ hidden tests. copied in by the scorer, never before
  pricing.json       USD per million tokens, per model
  configs/           generated. one CLAUDE_CONFIG_DIR per arm
  runs/              generated. per-cell artifacts + results.csv
```

The acceptance tests live **outside** the fixture and are copied in only after a
run ends. If the agent can read them, the benchmark is dead.

`t4-base` is the first commit and carries the broken date helper; the fix lands
in the second commit, which `t1-base`/`t2-base`/`t3-base` point at. That ordering
is deliberate: a T4 run's `git log` shows one commit, so the answer cannot be
recovered by reverting.

---

## Does the scorer actually work?

`bin/selftest.sh` answers that without spending anything. It stands in canned
patches for the agent and asserts the grade:

| Case | Expected |
|---|---|
| T1 correct fix (throw instead of 200) | 1.00 |
| T2 correct feature (refunds sub-resource) | 1.00 |
| T3 correct fix (joined read, shape intact) | 1.00 |
| T3 **flattened DTO** — fast, breaks consumers | 0.00, regression gate trips |
| T4 correct fix (`Intl` with the zone) | 1.00 |
| T4 **`+7 hours` hardcode** — passes the visible test | 0.00, hidden zones fail |

All six pass today. If any stops passing, the benchmark is measuring nothing and
no run is worth starting.

## Known deviations from the spec

- **T3 threshold is 3 SELECTs, not 2.** `total` legitimately needs its own
  `count` query. The planted N+1 is 52; a joined read is 2 and a batched second
  query is 3. Three is the honest bar for "the N+1 is gone".
- **Tool calls are capped via `--max-turns 150`,** not a true tool-call counter —
  Claude Code has no flag for the latter. For arm C, turns are counted on the
  main loop, so a subagent's internal calls do not consume the budget.
- **Arm B is the operator's own setup**, so it is not a neutral third party.

## Threats to validity — read before believing the numbers

- **n=3 is underpowered.** It detects 2x cost differences and 100%-vs-50% pass
  rates. It cannot detect 10-20% differences. Do not report "12% cheaper" as a
  finding.
- **A 30-file fixture hides what team-irfan is built for** — per-folder context
  maps on a large codebase. Follow up against a real repo once these land.
- **The tasks and the harness share an author.** The traps in T3 and T4 are ones
  team-irfan is already known to handle. Have someone else write T5-T6 before the
  next round.
- **Model non-determinism is baked in.** That is what H4 measures, not noise to
  apologise for.

The "where team-irfan lost" section of the report is the actual output of this
exercise. A benchmark that only confirms the prior was a waste of nine sessions.
