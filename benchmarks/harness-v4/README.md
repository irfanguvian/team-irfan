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

One command runs the whole matrix. You start it, then read files — you never
poll a model for status.

```bash
cd benchmarks/harness-v4

bin/init.sh                        # fixture repo (5 orphan-commit tags) + 3 arm configs
bin/selftest.sh                    # scorer + supervisor, against a fake claude. $0
BENCH_MODEL=claude-sonnet-5 BENCH_EFFORT=low bin/run.sh --matrix
```

`--matrix` is the supervisor. It preflights, spawns one lane per arm, waits,
then chains `score.sh all` → `judge.sh all` → `same-hole.sh` → `report.py`.
While it runs, three files tell you everything:

```bash
cat results/sonnet-low/PROGRESS.md        # rewritten after every cell: done/total, ETA
tail results/sonnet-low/notifications.log # push events, or set TEAM_IRFAN_NOTIFY_URL
cat results/sonnet-low/DONE               # exists at the end, names the report
bin/status.sh                             # what ran, what did not, the exact next command
```

`DONE` (report path) or `ABORTED` (reason) is how the run ends. **An abort
still scores and still reports** — a lane that dies takes the matrix's exit code
with it, but `score.sh`/`judge.sh`/`report.py` run anyway, so the cells that did
complete are on the record. `ABORTED` instead of `DONE` and a non-zero exit are
the signal; they do not mean the data was thrown away.

Re-running `--matrix` is the resume path: it skips any cell that already has a
result, and never silently reruns a cell that failed for infrastructure reasons.
To rerun those deliberately, once the cause is fixed:

```bash
bin/run.sh --matrix --redo-infra                 # every INFRA_FAIL cell
bin/run.sh --matrix --redo-infra=plugin          # only reasons matching "plugin"
```

The old cell directory is moved aside to `<cell>.infra-<timestamp>/` rather than
deleted, so the failed attempt stays auditable.

Useful flags and knobs:

```bash
bin/run.sh --matrix --tasks Q1,F1 --arms team --lanes 1   # a slice, strictly sequential
bin/run.sh --matrix --expect-sha $(git rev-parse HEAD)    # pin (this is the default)
bin/run.sh --matrix --dry-run                             # print every command, spawn nothing
bin/run.sh Q1 team 1                                      # one cell by hand

CELL_BUDGET_USD=3 MAX_SEC=1200 bin/run.sh --matrix        # per-cell guards
BENCH_TIER=... BENCH_MODEL=... BENCH_EFFORT=...           # which tier this writes to
CLAUDE_BIN=/path/to/claude bin/run.sh --matrix            # which binary is spawned
```

`CLAUDE_BIN` defaults to `claude` and is the single seam the selftest uses to
run the whole supervisor against `selftest/fake-claude` instead of a real,
paid session. `judge.sh` honours it too.

### Tiers

One tier = one `(model, effort)` pair — `sonnet-low`, `haiku-low` — derived from
`BENCH_MODEL` + `BENCH_EFFORT` or set outright with `BENCH_TIER`. Each tier owns
its own subtree, so two matrices can never contaminate each other:

```
runs/<tier>/<task>/<arm>/<round>/   per-cell artifacts (gitignored)
results/<tier>/results.csv          the durable record
results/<tier>/judgments/           C5 pairwise verdicts (LLM)
results/<tier>/same-hole/           C4 same-hole verdicts (script, zero LLM)
results/<tier>/{PROGRESS.md, ledger.jsonl, matrix.json, notifications.log,
                DONE | ABORTED, REPORT-<date>.md}
```

Run the sonnet tier first; it is the interesting one, because reliability claims
only differentiate when the model alone can't carry the task. The haiku tier is
the floor — it is **not** auto-chained, it is the next command.

### Three-state cells

A cell is `PASS`, `FAIL`, or `INFRA_FAIL`.

`INFRA_FAIL` means *the harness* broke, not the arm: the plugin never loaded,
the driver never ran, the budget watcher killed the process, the API rate-limited
us. Those cells are excluded from every C1–C5 computation and listed separately
with their reason. Everything else is the arm's own result — including
`capped(turns)`, which stays a scored cell because hitting the turn cap IS the
C3 result. Below the SPEC's round counts, a claim reads `INSUFFICIENT DATA`,
never `HOLDS` or `FALSIFIED`.

This is the v4 hardening in one sentence: **no LLM decides whether a cell is
valid.** Every validity bit comes from a file on disk written by a script or a
hook.

### Preflight, pin, heartbeat

Three checks stand between "start the matrix" and "spend money", and one runs
after every team cell:

- **Preflight** — `hooks/doctor.sh` PASSes, a one-turn `--effort` smoke call per
  arm config returns valid JSON, and `judge.sh --calibrate` is all-correct.
  Any failure refuses the matrix.
- **Pin** — the matrix refuses to start if the tree is dirty (ignoring `runs/**`
  and `results/**`), if HEAD ≠ `--expect-sha`, or if the *installed* plugin's
  `gitCommitSha`/`version` disagree with the repo. It refuses before creating any
  cell directory, and the message prints the fix. Every CSV row then carries
  `git_sha, plugin_version, model, effort, session_id` — a row can never be
  traced to the wrong build. `cost_source` records where that row's `cost_usd`
  came from: `result` (authoritative, from the session's own `result.json`) or
  `watch` (the budget watcher's approximation, all a killed cell leaves behind).
- **Plugin-load sentinel** — a `SessionStart` hook writes
  `.tg-bench/plugin-loaded` in the worktree. After each team cell, its `version`
  must equal the repo's. If it doesn't, the cell is `INFRA_FAIL
  reason=plugin-load-failed` and the **rest of that lane's team cells are
  aborted** (`lane-aborted:plugin-load-failed`, `cost_usd=0`, no process
  spawned) — symmetric counts, zero further spend. The bare and omc lanes are
  untouched. This is the exact failure that silently invalidated six opus cells
  on 2026-08-20.
- **Driver heartbeat** — the Stop hook touches `.tg-bench/driver-heartbeat` on
  its first fire. A transcript that says `ROUTE: FULL` or `ROUTE: FAST` with no
  heartbeat file means the plugin's driver never ran: `validity=infra
  reason=driver-absent`, `false_done` forced `false`.

### Lanes

The default is one detached lane per arm — three, for the full matrix. Each
lane owns its worktrees, its `runs/<tier>/.lock-<lane>`, and its log at
`runs/<tier>/lane-<lane>.log`; `--lanes N` splits the arms round-robin across N
lanes instead. Within an arm it is strictly sequential — never two cells in one arm at once,
and MEM-A must write its commit before MEM-B starts in that lane. `--lanes 1` is
the old strict-sequential behaviour. Wall time from a multi-lane matrix is
marked **concurrent-load** in the report, because the three lanes share one
machine and one rate limit.

### Notifications

`bin/notify.sh` batches `cell-done` events (flushing when the last send is ≥600 s
old) and flushes `matrix-done` / `matrix-abort` / `lane-abort` immediately.
Set `TEAM_IRFAN_NOTIFY_URL` and each event is `POST`ed as one line of JSON;
leave it unset and events append to `results/<tier>/notifications.log`.
`TEAM_IRFAN_NOTIFY_MIN_GAP` overrides the batching window. Notification failures
are always swallowed — the transport can never change a run's exit code.

### Selftest

```bash
bin/selftest.sh
```

Zero cost, no real `claude` ever. Eight scorer cases prove the grader still
grades the traps correctly (band-aid → 0, three-of-five → 0.6, any Q1 diff → 0),
`test_extract.py` covers the transcript parser, and a supervisor suite drives
`run.sh --matrix` against `selftest/fake-claude` — a shim that fakes transcripts,
sentinels, heartbeats, spend, and crashes on demand. It proves plugin-load abort,
lane isolation, missing heartbeat, SHA refusal, budget kill, same-hole hit/miss,
`INSUFFICIENT DATA`, and that `PROGRESS.md`/`DONE` are actually written. It runs
under `BENCH_TIER=selftest`, so it writes to `runs/selftest/` and
`results/selftest/` and cleans up after itself — it never touches a real tier's
CSV. If this fails, the benchmark measures nothing and no run is worth starting.

## Arms

| Arm | Config | Invocation |
|---|---|---|
| A `bare` | empty settings.json, no plugins, MCP off | task prompt as-is |
| B `omc` | operator's setup minus the team-graph rule | task prompt as-is |
| C `team` | operator's setup verbatim | `/team-irfan "<prompt>"` |

Same pinned model *and effort* per tier, identical flags across all three arms.

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

## Quality review (C5) and same-hole (C4)

**C5 is judged; C4 is not.**

C5: pairwise, blind, order-randomized — `bin/judge.sh`. The judge sees the task,
the before-files, two anonymous diffs — never arm names, transcripts, or
costs. Every pairing judged twice with presentation order swapped; a flip
between passes is recorded as tie. Calibration gate
(`judge/calibration/`, three planted pairs: root-cause vs band-aid, real vs
vacuous tests, genuine tie) must pass before any real judgment counts. One
judge model for the whole matrix (`JUDGE_MODEL`, default `claude-opus-5`).

C4: `bin/same-hole.sh <arm> <round>` greps `tasks/MEM-B/bandaid.markers` over
MEM-B's `diff.txt` and every `Edit`/`Write` tool input in its transcript
(intermediate attempts count), and writes
`results/<tier>/same-hole/<arm>-r<round>.json {same_hole, hits, retro_recorded}`.
Zero LLM — it used to be a judge call, and a judge call is the wrong tool for
"does this diff contain the pattern the retro said not to write".

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
- INFRA_FAIL cells are excluded from every verdict and listed with reason; a
  verdict is INSUFFICIENT DATA below the SPEC round counts.

## Legacy opus tier

The 2026-08-20 opus matrix predates tiers and predates every check above. Its
files stay exactly where they are and are byte-frozen: `results/results.csv`,
`results/REPORT-20260820.md`, `results/judgments/`. Read them with
`bin/report.py --tier opus-legacy`.

Six of its FULL team cells are **infrastructure-invalid** — the plugin manifest
in the installed 3.0.0 build carried no hooks reference, so team-irfan's driver
never loaded and those cells measured bare Claude Code wearing a team-irfan
label. They are listed in `results/opus-legacy.infra.json`, and `--tier
opus-legacy` prints them in its validity header rather than scoring them.

The opus tier is **deprioritized** going forward. The thesis v4 is now testing
is the cheap-model one — an orchestration layer should pay for itself where the
model alone can't carry the task — and re-running opus at ≈$60 a matrix buys no
evidence for it.

## Layout

```
harness-v4/
  SPEC.md                the v4 design doc, verbatim (§1 goalposts frozen)
  tasks/<T>/             PROMPT.md + scope.allowlist + hidden/ + judge.files
                         (+ bugfile.txt for MEM: the calls_to_locate target;
                          MEM-B/bandaid.markers: the same-hole grep patterns)
  fixture-patches/       base/ (clean new modules) + n5/ b1/ mem/ (seeded bugs)
                         + ref/ (reference fixes, selftest + calibration only)
  judge/                 prompt.md, calibration/pair-*/  (C5 only — C4 is same-hole.sh)
  selftest/              samples/ (extract.py fixtures) + fake-claude (the shim)
  bin/
    lib.sh               shared vocabulary: tiers, paths, statuses. sourced by all
    init.sh              fixture repo + arm configs
    preflight.sh         doctor + plugin-load sentinel + smoke, per cell
    run.sh               one cell, or --matrix (supervisor, lanes, resume)
    progress.sh          rewrites results/<tier>/PROGRESS.md
    notify.sh            batched push to TEAM_IRFAN_NOTIFY_URL, else a log file
    status.sh            what ran, what did not, the exact next command
    score.sh             gates, hidden acceptance, extract.py -> results.csv
    extract.py           transcript -> metrics, zero LLM
    same-hole.sh         C4 marker grep, zero LLM
    judge.sh             C5 blind pairwise review + --calibrate
    report.py            validity header, five verdicts, tables, REPORT-<date>.md
    selftest.sh          scorer cases + supervisor suite against fake-claude
  runs/<tier>/           per-cell artifacts (gitignored)
  results/<tier>/        results.csv + judgments/ + same-hole/ — the durable record
```
