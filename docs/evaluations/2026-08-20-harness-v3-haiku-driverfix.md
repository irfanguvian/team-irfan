# 2026-08-20 — harness×model matrix, haiku, after the Stop-hook driver (plugin 3.1.2)

Third full run on `TG_BENCH_MODEL=haiku`, same tasks, same scorer (selftest
green at 14:27), one variable changed: commit ef65da6 — deterministic
Stop-hook driver (`hooks/headless-driver.sh`), `gate.sh` runs lint,
challengers conditional, T3 allowlist admits `test/**`.
Published: `benchmarks/harness-v3/results/2026-08-20-haiku-v3-driverfix/`.
Coverage: 35 of 36 cells. T2/team/1 timed out at the 45 min cap, was
auto-retried, and the retry was aborted by the operator at 342 s — the cell is
missing, not failed, and is excluded from every median below.

## Verdict

team-irfan wins or ties **0/4** tasks. All four hypotheses FAIL again
(H1 lost T2 · H2 T1 tax 3.34x vs 1.5x kill · H3 1 oos file · H4 spread 8.4x
vs 1.5x). Correctness: **9/11 scored team cells correct or correct-sloppy**
(was 7/12 on 08-20 routerfix, 5/12 on 08-19). The driver closed most of the
turn-persistence hole — but the run is **not a clean haiku measurement**: 6 of
12 team cells spent most of their money on opus or sonnet subagents. Read the
cost columns for arm C as "haiku orchestrator + whatever it spawned".

## Per-cell correctness

| Task | A bare | B omc | C team-irfan |
|---|---|---|---|
| T1 | correct ×2, broken (lint: unused import) | correct ×3 | correct ×3 |
| T2 | correct ×3 | correct, broken ×2 (own e2e tests red, hidden 8/8 green) | correct, partial (zero-spawn stop), **missing** (aborted) |
| T3 | correct, declined ×2 ("Shall I proceed?") | correct ×3 | correct ×2, correct-sloppy (`.gitignore`) |
| T4 | correct ×3 | correct ×3 | correct ×2, declined (zero-spawn stop) |

Two things the baselines did this time that they did not do on 08-20 morning:

- **bare declined T3 twice** — wrote a plan and ended with "Shall I proceed?".
  Ambiguous prompt + headless = a blocking question, in the arm with no
  harness at all. The median for T3/bare is therefore 0 %.
- **omc broke T2 twice** — hidden acceptance 8/8, but the e2e tests it wrote
  itself fail in the regression run. Scored `broken` by the rule "regression
  red = broken", which is the right call: the arm shipped a red suite.

Neither moves the verdict: team-irfan still loses T2 on median pass rate and
still costs 3.3x on T1.

## What the driver bought

- **T1 FAST ×3, all correct.** First run where every T1 team cell ships. Lint
  in `gate.sh` caught nothing here; the 08-20 lint-only failure did not recur.
- **T3 correct ×3** (was 2/3). T3/team/3 ran the FULL pipeline to completion —
  executor, QA, challenger, lead review, merge — 1683 s, driver blocked 11
  times and each time the orchestrator picked the next node up.
- **T2/team/2 correct** end-to-end on FULL (driver blocked twice).

## What still fails

**1. Driver race — the Stop hook reads a transcript that does not yet contain
the message that ended the turn. 2 cells (T2/team/3, T4/team/1).**

T2/team/3: 3 turns, 31 s. Router triaged `ROUTE: FULL`, wrote "Proceeding to
open the run and start STEP 1 — PLAN.", ended. Driver exit 0, no block. The
final text message is timestamped 09:00:57.047Z, the Stop hooks 09:00:57.260Z.
Replaying the driver against the finished transcript exits 2 with the correct
marching orders — logic is right, the input was stale. T4/team/1 is the same
shape on FAST: driver blocked once, the orchestrator wrote "Proceeding with
fix.", ended again, second Stop did not block (count file = 1).

Fix (deterministic, one place): Claude Code 2.1.237 passes
`last_assistant_message` in the Stop hook input. Scan it together with the
transcript for `ROUTE:` and `Verdict:`. Also tighten the FAST terminal check —
`grep -q 'Verdict:'` on the last 40 lines matches the router quoting the
report format, not only the report itself; require it as a line prefix.

**2. `TG_BENCH_MODEL` is not honoured by subagents. 6 of 12 team cells.**

router.md says "spawn EVERY node with that model". The orchestrator cannot see
an environment variable from prose; it passed `model: opus` on `Agent` calls
in T1/3, T3/1, T3/2, T3/3, T4/3 (and the aborted T2/1: 9 + 3 opus spawns) and
`inherit` → sonnet in T2/2. From `result.json` `modelUsage`:

| cell | total $ | haiku $ | opus/sonnet $ |
|---|---|---|---|
| T1/team/3 | 1.60 | 0.44 | 1.17 |
| T2/team/2 | 0.87 | 0.36 | 0.51 (sonnet) |
| T3/team/1 | 1.24 | 0.23 | 1.00 |
| T3/team/2 | 1.23 | 0.28 | 0.95 |
| T3/team/3 | 10.51 | 1.54 | 8.97 |
| T4/team/3 | 1.00 | 0.28 | 0.72 |

$13.3 of the arm's $17.6 (76 %) was not spent on haiku. Haiku-only medians
would be T1 $0.40, T3 $0.28, T4 $0.20 — H2 still fails on T1 (3.3x), but the
T3 "$1.24 vs $0.13" headline is mostly the model, not the harness. Every
correct T3 team cell had an opus executor; whether haiku alone would have
shipped the N+1 fix under the driver is **unmeasured**.

Fix (deterministic, one place): a `PreToolUse` hook on `Agent`/`Task` that,
when `TG_BENCH_MODEL` is set, rewrites `input.model` via `updatedInput`. The
prose rule stays as documentation. Same FUNDAMENTALS line as the driver:
deterministic checks are never handed to the prompt.

**3. FULL tier cost and time are unbounded on haiku.** T2/team/1 hit the 45 min
cap on its first attempt (executor → QA → challenger → QA revise → QA run →
executor retry, all opus). T3/team/3 took 28 min and $10.51 for a one-file
N+1 fix. H4 spread 8.4x is this: FAST cells finish in 2–4 min, FULL cells in
4–45. The router's FAST/FULL boundary ("new endpoint = contract change =
FULL") is doing what it was told; whether it should is a design question the
benchmark answers with "not at this model tier".

## Harness lessons from this run (fix before the next one)

- **`bin/init.sh --configs` deletes `configs/`, including every session
  transcript under `configs/*/projects/`.** Run mid-matrix at 15:46 to refresh
  the OAuth token, it wiped the T1 and T4 transcripts for all three arms:
  `tokens_*`, `tool_calls`, `cache_*` are 0 for those 18 cells. `cost_usd`,
  `wall_sec`, pass rate and correctness come from `result.json` and the
  worktree and are intact. Fix: `score.sh` should copy the session transcript
  into `runs/<cell>/transcript.jsonl` at score time; `init.sh --configs` must
  not `rm -rf` the projects directory.
- **`score.sh all` appended to the existing CSV** instead of rewriting it,
  contrary to RESUME.md. The first report of this run was computed on 90
  rows (morning run + this run) and read "T2 team 12 %" and "T3 team 42x
  spread" — both artefacts. Fixed in `score.sh` (header written at start of
  `all`); the mixed CSV is kept as `runs/results.mixed-20260820.csv`.
- **`publish.sh` died before writing SUMMARY.md** because `status.sh` exits 1
  on an incomplete matrix under `set -e`. Fixed (`|| true`).
- **`run.sh`'s retry truncates the first attempt's `result.json`** (`>` on
  re-run) and `setup_worktree` deletes the first attempt's worktree. A cell
  that times out and is then interrupted leaves nothing scorable. Keep
  `result.json` as `result.attempt1.json` before retrying.
- **A `grep` for `"claude-[a-z0-9-]*":{` misses `claude-opus-5[1m]`.** The
  model key carries the context-window suffix; anything parsing `modelUsage`
  must allow `[`. `collect.sh` reads the transcript per model and is fine.
- **Medians on 2 or 3 cells.** T2/team has two scored cells; "56 %" is the
  mean of 100 % and 12.5 %. Report.py should print n per cell group.

## Actions (max 3, each traceable)

1. **H1/H4 — driver race:** read `last_assistant_message` in
   `headless-driver.sh`; FAST terminal check anchored to a `Verdict:` line.
2. **H2/H4 — model pin:** `PreToolUse` hook rewrites `Agent.model` when
   `TG_BENCH_MODEL` is set. Re-run arm C only (`--arms team`) and compare
   haiku-only cost against this run's haiku-only column.
3. **Harness:** transcript snapshot in `score.sh`, `result.attempt1.json` in
   `run.sh`, n-per-group in `report.py`. None of these change a number that
   was measured correctly; all of them stop the next run from lying.

Not an action: the FAST/FULL boundary. It is the question the benchmark
exists to answer, and the answer today is that FULL is not earned at haiku.
