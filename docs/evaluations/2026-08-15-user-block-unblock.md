# Evaluation 001 — 2026-08-15

First `/team-irfan-evaluation` pass. Run under review:
`runs/20260815-user-block-unblock/` — a FULL route on a Node/TypeScript
serverless backend, adding user block/unblock across five domain folders.

**Sample size: 1 run.** Nothing here that is derived from metrics is a
conclusion — it is a single observation. The aggregate is recorded so evaluation
002 has a baseline. Every change applied below originates from the operator's
direct review of the run, not from the metrics.

---

## Aggregate

| | |
|---|---|
| runs | 1 |
| routes | HAND-BACK 0 · QUESTION 0 · FAST 0 · FULL 1 |
| tool calls vs budget | **150 / 110** — and 110 was itself raised from the designed 60 |
| over-budget rate | FULL 100% (1/1) |
| gate fails | `integration: mock-collision`, `fix-b: lint-truncation-misread` |
| retry rate | 0% |
| escalation rate | 0% |
| context maps used | `none` |
| maps refreshed | `src-home` |
| human overrides | 3 — `cap-raised`, `b2-scope-added`, `round3-waived` |
| shipped | true |
| folders | 5 |

**The metrics contradict themselves.** `context_maps_used: none` alongside
`maps_refreshed: src-home`, while `.team-irfan/context/` was empty on disk. No
map was ever written, so nothing could have been refreshed — the run reported an
action that did not happen.

**Routing accuracy: not assessable at n=1.** Hand-back rate is 0/1, which means
nothing yet, but it is the number the design says is most likely to be silently
wrong, so it is the one to watch in 002.

---

## Findings

Each was verified against the repository and the run directory before being
recorded.

### F1 · Tool output landed in a committable path

`agents/executor.md` pointed graphify at `graphify-out/graph.json`, which
resolves to the project root. The project's `.gitignore` covers `.team-irfan/`
but not `graphify-out/`. Latent, not realised — no such directory existed — but
any tool the graph runs must write inside `.team-irfan/`.

### F2 · Bounded work was running on the cheaper tier

Executors, PjM, tester and retro all spawned `sonnet`. One run, 150 calls, three
unplanned fix rounds. The cheap tier was not saving anything.

### F3 · Worktree commits were task ids

Confirmed in the reflog: `T1` … `T7` as literal commit messages.
`agents/executor.md` said only "small, honest messages", which permits it. The
squashed commits that landed were well-formed and carried no AI attribution
trailer — but nothing in the prompts kept it that way.

### F4 · The memory layer never materialised — and could not have

Root cause, and the most consequential finding of this evaluation.

Every node's context-loading rule said: *"No map → generate that one folder's map
via `agents/init.md`, then proceed."* Every node is also declared a **leaf that
spawns nothing**. `init` is a node. A leaf therefore cannot generate a map, and
the instruction was unexecutable in every context that carried it.

Consequence: no map was written, all five folders were re-read cold by every
node, and the run paid full context cost at every step.

### F5 · 150 calls for a feature that adds one table and one filter

2.5× the designed budget. Contributing causes, in order of size: no context maps
(F4); seven tasks for work that was not file-contended; three fix rounds that
`metrics.json` does not count as retries because they were not tester-driven.

`agents/router.md` already carried the projection formula `20 + 27 × tasks`.
Seven tasks projects to ~209 calls against a 60 cap. Nobody ran the arithmetic —
the cap was raised to 110 instead, and the run spent 150.

### F6 · Nothing was reported back

`report.md` existed but lived in the run directory, outside the project, at 24KB.
The sequence printed nothing between node spawns. From the operator's side the
run ended with commits appearing and no statement of what was done, how to run
it, how to test it, or evidence that it had been tested — forcing a full manual
re-verification of work that had, in fact, been verified.

### F7 · Wall clock was never measured

Every budget in the graph is denominated in tool calls. Nodes took upwards of 20
minutes with no record, so neither operator nor graph could tell deliberate depth
from thrash.

---

## Applied

Eight diffs across four prompt files. Each was shown against the real current
text with its motivating finding, and applied only on an explicit `y`. None
declined.

| # | file | change | finding |
|---|---|---|---|
| 1 | `agents/executor.md` | graphify reads `.team-irfan/graphify/graph.json`; blanket rule that every tool writes inside `.team-irfan/` | F1 |
| 2 | `agents/router.md` | `opus` is the default for every node; three-condition downgrade to `sonnet`; `fable` as the opus-capped fallback; never `haiku` | F2 |
| 3 | `agents/executor.md` | Conventional Commits, imperative, ≤72 chars; `T1`/`wip`/`changes` rejected; no `Co-Authored-By` or AI attribution trailer | F3 |
| 3b | `agents/router.md` | goal branch `<type>/<slug>` per run; task branches inherit the type; one commit per task; `--squash` scoped to collapsing one worktree's own commits | F3 |
| 4 | `agents/router.md` | new step 3b — the orchestrator spawns `init` per unmapped folder before any executor; metrics may only name maps that exist on disk | F4 |
| 5 | `agents/router.md` | one progress line per node; ship block (what landed / how to run / how to test / pasted proof / verdict) printed and written to `docs/handoff/` | F6 |
| 6 | `agents/executor.md` | wall clock stamped and reported; over 15 minutes requires a stated reason | F7 |
| 7 | `agents/pjm.md` | tasks-vs-budget table; "more tasks is not more parallelism"; map generation reassigned to the orchestrator; model `opus` | F5, F4, F2 |

Verified after applying: `bash tests/run-checks.sh` → **74 passed, 0 failed**.

---

## Not expressible as a prompt diff

**"OMC and the bare harness are faster and more parallel than this."** Accurate,
and not fixable by editing a prompt. Those fan out inside a single context;
team-irfan pays a full spawn — worktree, artifact file, gate run, tester — per
unit of work. That overhead *is* the design, and it only earns its cost when
tasks genuinely contend for the same files.

Change 7 makes the cost visible before the run starts. It does not remove it. If
a later run shows the arithmetic being stated and the cap being raised anyway,
the conclusion is that FULL is the wrong route for features of that size, and the
fix belongs in the router's rubric rather than in PjM's sizing.

---

## Left stale — outside the evaluation node's allow-list

The evaluation node may edit prompt files under `agents/` only. These were found
inconsistent and deliberately not touched:

| file | what is stale |
|---|---|
| `hooks/init-scaffold.sh` | detects `graphify-out` at the project root |
| `templates/config.md` | describes `src/graphify-out` |
| `hooks/metrics.sh` | has no field for per-node wall clock, so duration cannot reach `metrics.json` |

`README.md`'s model matrix and any project-level `.team-irfan/config.md` matrix
also still read `sonnet` for the bounded nodes. `agents/router.md` now wins over
both, so they are misleading rather than harmful. The README matrix is corrected
in the same release as this evaluation; project-level configs are not, and are
each their own decision.

---

## Baseline for evaluation 002

| measure | this run | target |
|---|---|---|
| tool calls (FULL) | 150 | under 60 without a cap raise |
| context maps written | 0 | one per in-scope folder |
| human overrides | 3 | 0–1 |
| closing verdict delivered | no | yes |
| per-node wall clock recorded | no | yes |
