# Harness Benchmark v4 — spec + implementation prompt

Head-to-head: **bare Claude Code** vs **OMC** vs **team-irfan**. Same model, same
fixture, same prompt text, byte for byte. This document is paste-able into
Claude Code as the implementation prompt for `benchmarks/harness-v4/`.

v4 exists because v3 measured the wrong thing. v3's tasks saturated at 100%
pass for every arm, so the scoreboard collapsed to cost — where an
orchestration layer can only lose. v4 measures the five things team-irfan is
actually built for, and defines in advance what result would falsify each one.

**Ground rules carried from v3, changed where noted:**

- Mode B headless, plan gate auto-approved for arm C (say so in every report).
- Prompt text read from `tasks/<T>/PROMPT.md`, passed identically to all arms.
- **Sequential within an arm; arms may run as parallel lanes** — one lane per
  arm, own worktree, own lockfile, own results dir; never two cells in one arm
  concurrently; MEM session A must complete and write its retro before session B
  starts in that lane. Cross-lane `wall_s` is marked concurrent-load in the
  report. [^lanes]
- Resumable: `bin/status.sh` prints what ran and the exact next command.
  Every cell writes its result atomically before the next cell starts, so a
  crash loses at most one cell.
- Reuse the v3 fixture (NestJS + Prisma invoices app). v4 adds modules to it;
  it does not add a second repo.

[^lanes]: (amended 2026-08-21 — codifies the per-arm lane topology that ran the
    MEM cells on 2026-08-20). The original rule read "Sequential only. One cell
    at a time, always." v3's parallel *rounds within one arm* are the thing that
    kept failing; one lane per arm is not that, and it is what actually ran. A
    lockfile per lane (`runs/<tier>/.lock-<lane>`) still refuses a second
    concurrent invocation of the same lane.

---

## 1. The five claims, as falsifiable hypotheses

Written down before the first run. The goalposts do not move afterwards.

| # | Claim ("what team-irfan is for") | Metric | Team-irfan is FALSIFIED if |
|---|---|---|---|
| **C1 verify-driven reliability** | It verifies before declaring done, and its "done" is true. Not "AI finished it / made it pass". | `verified_before_done` (bool, from transcript) · hidden-test pass rate · `false_done` (declared done while hidden tests fail) | its `false_done` rate ≥ any baseline, or it skips verification on any run |
| **C2 plan-then-execute** | It routes A→B off a map instead of predicting the road. | `plan_exists` · `plan_adherence` = actions matching a declared plan step / total actions · `replans` count | adherence < 0.8, or it replans mid-run more than once per task |
| **C3 predictable effort** | Declared expected calls up front; actual lands near it. Small overrun fine; 10× not. | `predicted_calls` (from its own plan) vs `actual_calls` → `prediction_error` · cross-round cost spread | median \|error\| > 30%, or spread wider than both baselines |
| **C4 memory / never the same hole twice** | Second session in the same repo starts with the brain; a bug class fixed once is found and fixed faster the second time. | two-session protocol (§4): session-B cost/turns/locate-calls vs session-A · `same_hole` (bool, judge-checked) | session B is not cheaper AND not faster to locate than session A, or it repeats the exact mistake session A's retro recorded |
| **C5 generated quality** | The diff a reviewer would approve: root cause not band-aid, existing patterns, real tests, minimal, compat-safe. | blind pairwise LLM review (§5), win rate per pairing | it loses the pairwise majority against either baseline on any task |

Note what is *absent*: raw cost and wall time are **reported but not scored**.
v3 proved that on saturated tasks they are the only axis left and team-irfan
structurally loses it. In v4 they are context, not verdict. The one cost claim
that survives is C3 (predictability) and the C4 second-session discount.

---

## 2. Arms

| Arm | Config | Invocation |
|---|---|---|
| A `bare` | empty settings.json | task prompt as-is |
| B `omc` | OMC installed | task prompt as-is |
| C `team` | team-irfan plugin + commands | `/team-irfan "<task prompt>"` |

Same pinned model for all arms per run (`BENCH_MODEL`). Two model tiers per
full matrix eventually — `claude-opus-5` and `claude-sonnet-5` — because the
reliability claims only differentiate when the model alone can't carry the
task. Run opus first; sonnet is the interesting one.

---

## 3. Task set

Small, trap-based, sequential-friendly. Six tasks, one fixture. Each task names
which hypothesis it exists to test and how a specific arm loses it.

**Q1 — pure question.** "How does auth work in this repo, and which endpoints
skip the guard?" No code change allowed; the scorer fails any diff. Tests C1/C2
routing (team-irfan must take QUESTION, zero agents) and gives the memory
protocol its cheap session-A warm-up. *Trap: arm C spins agents for a
question.*

**F1 — one-liner.** v3's T1 (validation 400). Kept as the harness-tax canary:
reported, not scored, against the 1.5× line. *Trap: full pipeline for one
line.*

**N5 — five N+1 queries, five modules.** The centrepiece. Seed one N+1 each in
`invoices`, `reports`, `customers`, `refunds`, `audit` (v4 adds the missing
modules — thin, ~60 LOC each). Contract tests pin every response shape. Prompt:
"List endpoints across the app are slow under load. Find and fix the cause.
Don't break any consumer." Hidden acceptance: query-count assertions per
endpoint (≤3 queries for a 50-row page) + the contract suite.
*Traps, one per arm-failure-mode:* fixing 3 of 5 and declaring done (C1);
wandering module to module re-reading code instead of planning the sweep (C2);
flattening a DTO to go fast (C5); a plan that says 40 calls and spends 200
(C3).

**B1 — band-aid trap.** A failing test whose *tempting* fix is to special-case
the failing input in the caller; the *correct* fix is one line in the shared
util that three modules import. Hidden tests exercise the other two modules
with the same edge case — the band-aid passes the visible test and fails
hidden. Tests C1 (is "done" true?) and C5 (root cause). Reuse v3's T4 timezone
bug as the template; add the two extra consumers.

**MEM-A / MEM-B — the memory pair.** §4. Same bug class (an N+1 with the same
shape as N5's), planted in two different modules, fixed in two *separate
sessions* on the same repo clone.

Round count: **3 rounds** per cell for Q1/F1/B1, **2 rounds** for N5 and the
MEM pair (they're long; sequential wall time is the budget). Total ≈ 40
sessions per model tier. Fastest tasks first, so a crash early costs little.

---

## 4. Memory protocol (C4)

The only benchmark where arms are *supposed* to be unequal — bare and OMC have
no cross-session memory. That asymmetry is the claim, so the protocol just has
to be fair on inputs, not on capabilities.

```
per arm, per round, on ONE persistent repo clone (not a fresh worktree per session):

  session A:  MEM-A prompt — "GET /reports/daily is slow, fix it"   (seeded N+1)
              arm runs to completion. For arm C this includes retro + memory write.
              record: cost, turns, calls-to-locate (first read of the buggy file)
  <kill the session. new session, same clone, same arm>
  session B:  MEM-B prompt — "GET /customers/:id/activity is slow, fix it"
              (same bug class, different module)
              record: same metrics + same_hole check
```

- `calls_to_locate` = tool-call index of the first read of the file containing
  the seeded bug. This is the "did the brain help you find it" number.
- `same_hole`: MEM-A's seeded fix has a known wrong-first-attempt (the band-aid
  from B1's family). The judge checks session B's transcript: did the arm try
  the known-wrong path at all? For arm C, whose session-A retro explicitly
  recorded it, trying it again = fail.
- Fairness: identical prompts across arms; no arm gets extra text. Arm C's
  advantage must come from `.team-irfan/` state it wrote itself in session A —
  that's the feature under test.
- Scored comparison is **within-arm** (B vs A) first: does memory produce a
  discount? Then across arms: is C's discount bigger than the baselines'
  (whose only "memory" is a warm cache — which is why sessions must actually be
  separate processes, minutes apart, not resumed conversations).

---

## 5. Quality review (C5)

Not lint, not tests-passed — a reviewer. But an LLM judge scoring 1–10 in the
open is noise, so the protocol is what makes the number worth anything:

**Pairwise, blind, order-randomized.**

- Unit of judgment: one task, two diffs (e.g. N5: arm A's diff vs arm C's
  diff), presented as `DIFF-1` / `DIFF-2` with arm identity stripped and
  presentation order randomized per judgment.
- Judge input: the task prompt, the relevant fixture files *before* the change,
  the two diffs, and each diff's new/changed tests. Never the transcript, never
  cost, never arm names.
- Judge output (forced JSON): `winner: 1|2|tie`, plus one line each on: root
  cause vs band-aid · pattern reuse vs invention · test quality (does any test
  assert an outcome, or only mocks?) · minimality · compat risk. The one-liners
  exist so a human can audit the verdict; the winner is what's counted.
- Every pairing judged **twice with the presentation order swapped**. The two
  verdicts must name the same winner; a flip = recorded as `tie`. This kills
  position bias, the biggest known judge failure.
- Judge model: strongest available, and **never the model that generated the
  diffs' arm configs' tier** — opus-tier diffs get judged by opus is fine;
  sonnet-tier diffs also judged by opus. One judge model for the whole matrix.
- **Calibration gate before any real judgment**: `judge/calibration/` holds
  three planted pairs with known answers — (good fix vs band-aid), (real tests
  vs vacuous mock-only tests), (two genuinely equivalent fixes → must say tie).
  `bin/judge.sh --calibrate` runs them; a judge that misses any is not used
  and the config (prompt/model) gets fixed first. Same idea as v3's tester
  ground truth: a reviewer that can't discriminate in both directions measures
  nothing.
- Score: per task, per pairing, win/tie/loss. Report per-task and overall win
  rate. No averaging of invented point scales.

---

## 6. What gets extracted from a transcript

All from Claude Code's JSON output; one `bin/extract.py`, zero LLM:

| field | how |
|---|---|
| `actual_calls`, `turns`, `cost_usd`, `wall_sec` | as v3 |
| `verified_before_done` | after the **last** file edit, does the transcript contain a verification command (test runner / curl against the running app / `gate.sh`) *before* the final assistant message? |
| `false_done` | arm's final message claims completion AND hidden acceptance fails |
| `rework_loops` | count of (edit file X → run tests → fail → edit file X) cycles |
| `plan_exists` | a numbered/step plan appears before the first file edit |
| `predicted_calls` | parsed from arm C's plan (its SCOPE block states it); null for A/B unless they volunteer one |
| `plan_adherence` | each file-touching action mapped to a plan step by path; matched/total. null if no plan — and **null is reported as "did not plan", not skipped** |
| `replans` | occurrences of a new plan superseding the previous one mid-run |
| `calls_to_locate` | MEM tasks only, §4 |

`plan_adherence` for arms A/B being mostly null **is a finding, not a gap** —
"the baselines do not plan" is claim C2 itself, stated by the data.

---

## 7. Runner contract

```
benchmarks/harness-v4/
  tasks/{Q1,F1,N5,B1,MEM-A,MEM-B}/PROMPT.md + hidden/ + scope.allowlist
                          (+ MEM-B/bandaid.markers — the same-hole grep patterns)
  fixture-patches/        additive modules for N5/B1/MEM on top of v3 fixture
  judge/{prompt.md, calibration/}
  bin/{init.sh, lib.sh, preflight.sh, run.sh, extract.py, score.sh,
       same-hole.sh, judge.sh, report.py, progress.sh, notify.sh, status.sh}
  selftest/fake-claude    the shim bin/selftest.sh runs instead of a real claude
  runs/<tier>/  results/<tier>/
```

**Tiers.** One tier = one `(model, effort)` pair — `sonnet-low`, `haiku-low`.
Each tier owns `runs/<tier>/` and `results/<tier>/` so two matrices never
collide. `BENCH_TIER` (or `BENCH_MODEL` + `BENCH_EFFORT`) selects it; the
pre-tier opus files stay where they are and are read as `--tier opus-legacy`.

- `run.sh <task> <arm> <round>` still runs exactly one cell.
- **`run.sh --matrix [--lanes N] [--tasks ..] [--arms ..] [--expect-sha ..]`**
  is the supervised entry point: it runs preflight, writes
  `results/<tier>/matrix.json`, spawns **one detached lane per arm** (default
  `--lanes 3`; `--lanes 1` = strict sequential), waits on the lanes, then chains
  `score.sh all` → `judge.sh all` → `same-hole.sh` → `report.py` and writes
  `results/<tier>/DONE` (naming the report) or `ABORTED` (with a reason).
  Each lane holds its own `runs/<tier>/.lock-<lane>` and logs to
  `runs/<tier>/lane-<lane>.log`; `--lanes N` splits the arms round-robin.
- **Crash-resume via the ledger.** Every cell end appends one line to
  `results/<tier>/ledger.jsonl` `{ts,task,arm,round,status,reason,cost_usd,wall_sec}`.
  Re-running `--matrix` skips any cell that has a `result.json` **or** an
  `INFRA_FAIL` meta — an infra cell is never silently rerun, it is reported.
  `--redo-infra[=<reason-substring>]` is the deliberate override: it reruns
  those cells once the cause is fixed, moving each old cell dir aside to
  `<cell>.infra-<ts>/` so the failed attempt stays auditable.
- **An abort still scores and still reports.** A lane that dies ends the matrix
  with `ABORTED` and a non-zero exit, but `score.sh` → `judge.sh` →
  `same-hole.sh` → `report.py` run regardless: cells that completed stay on the
  record. Aborting is a signal about the run, never a reason to discard data.
- **Preflight**, before cell 1 and (for the team arm) again after each cell
  exits: `hooks/doctor.sh` must PASS · a one-turn `--effort` smoke call per arm
  config must return valid JSON · `judge.sh --calibrate` must be all-correct ·
  the team arm's worktree must contain a `.tg-bench/plugin-loaded` sentinel
  whose `version` equals the repo's `plugin.json` version. Failure of the
  post-cell sentinel check is `INFRA_FAIL reason=plugin-load-failed`, and the
  rest of that lane's team cells are written `lane-aborted:plugin-load-failed`
  with `cost_usd=0` and no process spawned — symmetric counts, zero spend.
  Selftest-only escapes: `BENCH_SKIP_PIN` / `BENCH_SKIP_CALIBRATE` / `BENCH_SKIP_SMOKE`.
- **Pin what is measured.** `--expect-sha <sha>` (default `git rev-parse HEAD`).
  The matrix refuses to start if the tree is dirty (ignoring `runs/**` and
  `results/**`), if HEAD ≠ expect-sha, or if the *installed* plugin's
  `gitCommitSha`/`version` disagree with the repo. It refuses **before** any
  `runs/<task>` directory is created. `meta.json` and every CSV row carry
  `git_sha, plugin_version, model, effort, tier, session_id` so a row can never
  be traced to the wrong build, plus `cost_source` ∈ `result|watch` — whether
  that row's cost is the session's own authoritative total or the budget
  watcher's approximation, which is all a killed cell leaves behind.
- **Driver heartbeat.** The team arm's Stop hook touches
  `.tg-bench/driver-heartbeat` on its first fire. A transcript containing
  `ROUTE: FULL|FAST` with no heartbeat file means the plugin's driver never ran:
  `validity=infra reason=driver-absent`, `false_done` forced `false`.
- **Three-state cells: `PASS | FAIL | INFRA_FAIL`.** `INFRA_FAIL` means the
  harness broke, not the arm — plugin never loaded, driver absent, budget kill,
  auth/rate-limit. INFRA cells are **excluded from every C1–C5 computation** and
  listed separately with their reason. `PASS` iff `pass_rate == 1`; everything
  else the arm did is `FAIL`.
- **Budget guard.** `CELL_BUDGET_USD` and `MAX_SEC` per cell; a watcher prices
  the live transcript against `pricing.json` and `kill -TERM`s an overrun →
  `INFRA_FAIL reason=budget` (wall overrun: `budget(wall)`). This is the one
  place a spend cap and a *result* are deliberately separated: `MAX_TURNS=150`
  is **not** infra — a cell that hits the turn cap is scored `capped(turns)`,
  because hitting the turn cap IS the C3 result.
- **Same-hole is deterministic, not judged.** `bin/same-hole.sh <arm> <round>`
  greps `tasks/MEM-B/bandaid.markers` over MEM-B's `diff.txt` and every
  `Edit`/`Write` tool input in its transcript, and writes
  `results/<tier>/same-hole/<arm>-r<round>.json {same_hole,hits,retro_recorded}`.
  Zero LLM. The judge keeps only the blind pairwise C5 review.
- MEM cells are the one exception to fresh-worktree-per-cell: the pair shares
  one clone per (arm, round), created by `run.sh` for MEM-A and reused by
  MEM-B, then destroyed.
- **Never poll a model.** `results/<tier>/PROGRESS.md` is rewritten after every
  cell (`bin/progress.sh`) and `bin/notify.sh` pushes to `TEAM_IRFAN_NOTIFY_URL`
  (or appends to `notifications.log` when unset). The operator starts one
  process and reads files.
- `report.py --tier <tier>` prints a per-arm `valid | infra | total` header and
  the infra cells with reasons, then the five hypotheses with verdicts
  (`holds / falsified / INSUFFICIENT DATA`), the per-task table, and the
  pairwise-review win matrix, and writes `results/<tier>/REPORT-<date>.md`.
  Cost and wall appear in the table footer, unscored, with one line of context —
  and marked concurrent-load when the matrix ran with `--lanes > 1`.

---

## 8. Honesty section (goes in every published report verbatim)

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

---

## 9. Implementation order (for the Claude Code run that builds this)

1. `fixture-patches/` — the three new thin modules + seeded N+1s + contract
   tests + hidden query-count acceptance. Verify by hand: `npm test` green,
   hidden suite red on the seeded code, green on a reference fix.
2. `bin/extract.py` + unit tests against two committed sample transcripts
   (one that verified before done, one that didn't).
3. `judge/` — prompt, the three calibration pairs, `judge.sh --calibrate`
   passing.
4. `bin/run.sh` sequential runner + lockfile + `status.sh` resume. Dry-run
   prints every command.
5. `report.py`.
6. Update `benchmarks/README` and the repo README/CHANGELOG to describe v4 and
   mark v3 results as superseded-for-conclusions (kept as the record).
