# Finishing the benchmark later

The 2026-08-18 run covered 24 of 36 cells. This is how to pick it up without
re-spending on work that is already done, and without quietly changing what is
being measured.

Start here, always:

```bash
cd benchmarks/harness-v3
bin/status.sh
```

It prints the matrix, marks every cell `done` or `--`, and ends with the exact
commands for what is left. Everything below is the reasoning behind those
commands.

---

## What is missing, and why it matters

| Missing | Why it was missing | Cost of leaving it |
|---|---|---|
| **T3, all three arms** | never started — the run was stopped after T2 | **H1 and H3 are untested.** T3 is the only task with an ambiguous prompt and a consumer-contract trap, i.e. the case team-irfan exists for |
| **T2, arm C** | killed mid-flight when the run was stopped; discarded rather than reported | T2 has no three-way comparison, only bare vs omc |

T3 is the one that changes the conclusion. Run it first if you only run one thing.

---

## Before spending anything

Three preconditions. Skipping them is how a resumed run produces numbers that
cannot be compared to the old ones.

**1. Refresh the arm configs.**

```bash
bin/init.sh --configs      # token only; plain init.sh also rebuilds the fixture repo
```

**Only before a run, never between cells.** Both forms `rm -rf configs/`,
and `configs/*/projects/` is where every arm's session transcripts live.
Refreshing mid-matrix (done on 2026-08-20) zeroes `tokens_*`, `tool_calls`
and `cache_*` for every cell already run; `cost_usd`, wall and pass rate
survive because they come from `result.json`.

The OAuth token copied into `configs/*/.credentials.json` expires. A stale one
fails as `Not logged in` in 57 ms per cell, which looks exactly like a fast, free
run until you read `result.json`. `init.sh` also rebuilds the fixture repo and
its tags from `fixture/`, so any local edit to the fixture is discarded — that is
intended.

**2. Prove the scorer still grades correctly.**

```bash
bin/selftest.sh
```

Six canned patches, six expected grades, no agents, no cost. If this does not
print `selftest passed`, stop: the harness is measuring nothing and any run you
start is wasted money.

**3. Check the model is still the one the old rows used.**

The published rows were produced with `claude-opus-5`, pinned by `run.sh` via
`BENCH_MODEL`. If you resume on a different model, the new rows are **not**
comparable to the old ones — publish them under a new label rather than merging
them into the same CSV.

---

## Running only what is missing

`run.sh all` rebuilds a worktree and spawns an agent for **every** cell in its
task list, including cells that already have results. Scope it instead:

```bash
bin/run.sh all --tasks T2 --arms team     # the one aborted cell's arm
bin/run.sh all --tasks T3 --arms bare
bin/run.sh all --tasks T3 --arms omc
bin/run.sh all --tasks T3 --arms team
```

Arms are deliberately run one at a time, in that order, so rate limiting hits
every arm rather than only the unlucky one. Rounds inside an arm run in parallel.

Roughly $1-3 per cell at the rates seen on 2026-08-18, so the remaining 12 cells
are on the order of $15-30.

---

## Then score and publish

```bash
bin/score.sh all                 # re-scores every cell that still has a worktree
bin/publish.sh full              # -> results/full/
```

`score.sh all` is safe to re-run: it clears any previously copied acceptance
tests first, and rewrites `runs/results.csv` from scratch. It needs the
worktrees, so **do not delete `~/team-irfan-bench-wt/` until after scoring.**

`publish.sh <label>` freezes the CSV, a readable median table, and the coverage
report into `results/<label>/`. That folder is the durable artifact; `runs/` is
transcripts and absolute paths that go stale.

---

## Then update the evaluation

`docs/evaluations/2026-08-18-harness-v3-three-arm.md` records the partial run and
says plainly that T3 is untested. When T3 lands, write a **new** evaluation
rather than editing that one — the point of a dated evaluation is that it says
what was known at the time.

The four pre-registered hypotheses are in `README.md` and encoded in
`bin/report.py`. Do not restate them from memory and do not adjust them after
seeing the numbers. Only H2 was cleanly falsified on 2026-08-18; H1 and H3 are
open until T3 runs.

---

## What the 2026-08-18 run taught about the harness itself

Worth knowing before you trust a resumed run.

- **Every arm scored 100% on every task.** The traps did not bite at this model
  tier. If the completed T3 also comes back 100% across the board, the honest
  conclusion is that the task set is too easy, not that the arms are equivalent.
  The next action is harder tasks written by someone who did not write these.
- **`.omc/` state used to be counted as agent edits**, producing up to 30 phantom
  out-of-scope files. Fixed in `score.sh`. If you add another tool to an arm,
  check whether it writes state into the working directory and add it to the
  exclusion list, or containment will measure the tool's filing habits.
- **Allowlists exclude nothing a good engineer would do.** `test/**` is allowed
  on every task; the protected-test guard, not the allowlist, is what stops a
  trap being defused.

---

## Cleaning up

```bash
rm -rf ~/team-irfan-bench-wt        # worktrees — only after scoring
git -C ~/team-irfan-bench worktree prune
rm -rf configs/                     # deletes the plaintext token copies
```

`configs/` holds a mode-600 copy of your OAuth access and refresh tokens, because
a non-default `CLAUDE_CONFIG_DIR` cannot read the macOS Keychain. It is
gitignored and never committed, but it is real credential material — delete it
when you are done, and `bin/init.sh` will recreate it next time.
