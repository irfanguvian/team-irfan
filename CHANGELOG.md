# Changelog

Notable changes to the team-irfan workflow. Versions are the workflow's, not any
project's.

---

## 3.1.3 — 2026-08-21

The 2026-08-20 opus matrix produced a headline the addendum then contradicted:
the plugin silently failed to load in 6 of the FULL team cells, so those cells
measured a plain Claude session and scored as a team-graph result. Nothing on
disk disagreed with them, which is the actual defect — infra health was being
inferred from transcripts. It is now a file a script writes.

- **New `hooks/bench-sentinel.sh`, on SessionStart.** Auto-approve sessions
  only: writes `.tg-bench/plugin-loaded` (`{version, root, ts}`) in the session
  cwd, taken from the loaded plugin's own `plugin.json`. The harness compares it
  against the repo version and marks a disagreeing or missing cell
  `INFRA_FAIL reason=plugin-load-failed` instead of scoring it. Zero LLM, silent
  on stdout, always exits 0; interactive sessions leave no trace.
- **`hooks/headless-driver.sh` leaves a heartbeat** — `.tg-bench/driver-heartbeat`,
  touched once under auto-approve before any route parsing. A transcript that
  routed FULL/FAST with no heartbeat means the Stop hook never fired, which the
  scorer reads as `driver-absent` rather than as a persistence failure. All
  existing driver behaviour is unchanged.
- Part of the harness-v4 hardening pass: preflight, run pinning to a commit and
  plugin version, three-state cells (`PASS | FAIL | INFRA_FAIL`), and the
  never-stale supervisor land in the same commit — see
  `benchmarks/harness-v4/SPEC.md` and `.omc/plans/harness-v4-hardening.md`.
- Checks: section 36 pins both hooks, including functional tests that the proof
  files appear under `TEAM_IRFAN_AUTO_APPROVE=1` and only there.

---

## 3.1.2 — 2026-08-20

The 2026-08-20 haiku matrix (results/2026-08-20-haiku-v3-routerfix) showed the
3.1.1 prompt fixes bought T3 back (0 → 2/3 correct) but turn persistence still
lost 4 of 12 cells: three turn-ends with zero subagents spawned, one BLOCKING
question at an auto-approved gate. Prompt discipline is exhausted; these fixes
are deterministic.

- **`hooks/headless-driver.sh`, first on Stop.** Auto-approve sessions only:
  blocks turn-end while a routed run (ROUTE: FULL/FAST in the transcript) has
  no terminal artifact (FULL: a handoff file; FAST: a Verdict: line). Capped at
  25 blocks/session. Interactive sessions: hook exits 0, human gates intact.
- **Router: BLOCKING questions forbidden under auto-approve** — answered from
  clarifications.md → repo → stated default, logged as assumptions.
- **Router: named-pattern perf bugs are FAST** — the contract suite is the
  deterministic protection; FULL for a one-file N+1 cost 19x bare on T3.
- **Router: challenger round now conditional** on plan risk (≥3 tasks, schema/
  contract change, >1 phase, unsourced rule); low-risk plans skip it.
- **gate.sh runs lint** (guardrails layer 1) — a correct T1 fix died on one
  unused import the gate never saw.
- Bench: T3 allowlist admits `test/**` like every other task — the guardrails
  mandate tests with every change; the old scope counted them out-of-scope.
- Checks: section 35 pins all of the above, incl. 7 functional driver tests.

---

## v3.1.0 — 2026-08-19

The v3 redesign completed: role merge, challengers, budget-phased planning,
agent memory, backward-compat machinery, and the harness×model benchmark
matrix. Star topology, one human gate, hooks inert without `.tg-active`,
ledger over self-report, and deterministic-checks-never-in-prompts all
preserved — and now checked harder (306 checks, up from 205).

**Breaking — node roster, graph.json, templates:**

- **PM + PjM merged into `product`.** One node owns product, project, and
  business flow; no brief→tasks handover. `agents/pm.md` and `agents/pjm.md`
  deleted; `agents/product.md` added. `plan.md` is the one artifact set:
  business rules (each sourced — an inferred rule is a question, not a rule),
  SCOPE block, PHASES block, and per-task spec blocks. Templates `scope.md`
  and `task-spec.md` folded into `templates/plan.md` and deleted; executors
  receive their own `### Task T<id>` block, never the whole plan. Lead's
  `mode=options` removed — the challenger generates alternatives instead.
- **graph.json rewired**: `product` + three challenger nodes + `plan-check`,
  gate count still exactly 1.

**Challengers — parallel verification without breaking the star:**

- `product-challenger`, `qa-challenger`, `lead-challenger` — spawned by the
  orchestrator only (roles never spawn), debating via artifacts
  (`challenge.md`, `challenge-qa.md`, `challenge-lead.md`), ≤5 tool calls
  each, side_effect_free, FULL route only. One revision round; unresolved
  disagreement goes to Irfan with both positions. A user-specified solution
  path is verified, never second-guessed with alternatives. Lead vs
  lead-challenger verdict disagreement is an automatic blocker.

**Budget-phased planning:**

- Every plan carries a `## PHASES` block (`budget_cap: 60`,
  `projection_formula: 26 + 27*tasks` — up from the implicit 20+27 to price
  the challengers in). New `hooks/plan-check.sh` recomputes every projection
  from the task count and bounces any over-cap phase before the gate is
  shown. Multi-phase plans execute phase 1 only; each later phase is a fresh
  run. Design-time check; the pre-spawn ledger check stays as the runtime
  backstop.

**Agent memory — Product + Lead only (`docs/memory.md`):**

- `hooks/memory.sh`: SQLite + FTS5/BM25, per-repository, in
  `.team-irfan/memory/`. Ingest via SubagentStop/Stop hooks (artifacts, not
  transcripts; one Haiku call with a JSON-ops-only contract — Haiku
  proposes, the pipeline disposes; malformed JSON logged and dropped).
  Deterministic retrieval at spawn (stemming → MATCH → BM25 → top-12,
  `[maybe-stale]` on rows whose source files changed). Compiled always-load
  views; init seeding (Product by reading, Lead by RUNNING the detected
  commands); compact with a 500-row cap and optional REFLECT pass. Memory
  never blocks: every failure exits 0 after one `memory.log` line, and
  `/team-irfan-evaluation` reads that log for a health verdict. The
  mem0-style vector/entity/score-fusion design is rejected on record.

**Backward compatibility, first-of-mind:**

- **Rule A**: a failing pre-existing test IS a compat break; restore or
  declare `INTENTIONAL BREAKING` (valid only if the approved plan declares
  it). Nobody edits an old test to green new work.
- `skills/guardrails/breaking-changes.md`: the static checklist (request/
  response contracts, routes, code level, data, events, frontend), loaded by
  executor + QA + Lead + both reviewing challengers; an undeclared hit is a
  blocker.
- QA's persistent regression suite: `.team-irfan/qa/` +
  `regression.manifest`, executed whole every run by `hooks/qa-manifest.sh`
  (exit-code honest, loud on missing files); new cases appended on ship. The
  suite only grows.

**Benchmarks — workflow vs model:**

- Harness ∈ {bare, OMC, team-irfan} × model ∈ {haiku, sonnet} via
  `TG_BENCH_MODEL`, which overrides the production matrix uniformly and
  stamps `bench_model` into `metrics.json` — production keeps `haiku:
  never`. New `compat-trap` tester fixture (passes its own tests, breaks the
  pre-existing `checkout` endpoint); `run.sh --score` extended with measured
  dimensions (gate, regression, ledger tool calls vs labeled transcript
  counts, retries, wall time). Fixture gained the second endpoint.
## benchmarks: harness v4 — 2026-08-20

Not a workflow change — a measurement change. `benchmarks/harness-v3` is
**superseded for conclusions** (its four tasks saturated at 100% pass for every
arm, leaving only cost — an axis v4 deliberately reports but does not score);
its runs stay as the record. `benchmarks/harness-v4` scores the five claims
team-irfan is built on, each with a pre-registered falsifier:

- **C1 verify-driven reliability** — `false_done` + `verified_before_done`
  from the transcript, against hidden acceptance.
- **C2 plan-then-execute** — `plan_exists` / `plan_adherence` / `replans`;
  baselines' null adherence is reported as "did not plan", which is the claim.
- **C3 predictable effort** — plan's `expected_calls` vs actual, cross-round
  cost spread; capped runs are scored, not discarded.
- **C4 memory** — MEM-A/MEM-B two-session protocol on one persistent clone;
  within-arm discount plus a judged `same_hole` check.
- **C5 generated quality** — pairwise blind order-swapped LLM review, gated by
  a 3-pair calibration (`judge.sh --calibrate`) that must pass first.

New tasks: Q1 (pure question — any diff fails), F1 (v3's T1, the harness-tax
canary), N5 (five seeded N+1s across five modules, contract-pinned), B1
(shared-util band-aid trap with two hidden consumers), MEM pair. Fixture gains
`customers`, `refunds`, `audit` modules; each task state is a single orphan
commit so `git log` leaks nothing. Runner is strictly sequential (lockfile),
resumable (`status.sh`, `run.sh all` skips finished cells), atomic per cell.
Scorer proven by `bin/selftest.sh` (8 graded cases incl. the band-aid and
3-of-5 traps); `extract.py` unit-tested against committed sample transcripts.

---

## v3.0.0 — 2026-08-18

The FULL path restructured to a 7-step harness. Triage tiers (HAND-BACK,
QUESTION, FAST) untouched; star topology, ledger, gate.sh, retry-guard,
worktree-per-task, run-state resume, and the forbidden-actions block all
preserved.

**Breaking — the flow itself:**

- **One human gate instead of three.** The plan approval is the only stop.
  PM's open questions fold into the plan and are answered there; the ship
  sign-off is replaced by Lead's machine review gate (verdict PASS | BLOCKED,
  evidence pasted, a breaking change is always BLOCKED).
- **PjM is the FULL entry node** and the bridge to Irfan: restates the task as
  a verifiable work list, folds in PM's sourced scope (`scope.md`) and Lead's
  1–3 options (`options.md`, one recommended), and writes `plan.md` (printed
  in chat in full before the question) + `plan.json` (machine-readable, with
  `run_cap = min(round(chosen expected_calls × 1.3), 60)`).
- **`hooks/plan-gate.sh`** — deterministic, zero LLM: required fields, 1–3
  options, chosen id exists, numeric expected_calls, run_cap arithmetic,
  non-empty scope_folders. Named reason on failure; PjM regenerates (max 2,
  then HAND-BACK). Output pasted before the approval question.
- **`run_cap` replaces the static 60** once approved: `ledger.sh cap <run>`
  reads it from plan.json, fallback 60; the pre-spawn check uses it.
- **QA (tester renamed)** writes test cases from plan.json ONLY, in parallel
  with the executors, blind to any diff or worktree. Backend: executable curl
  cases with status+body assertions; frontend: `chrome-devtools-axi` steps or
  a declared manual checklist — never faked browser output. `gate.sh` now
  scans `test-cases.md` and fails assertion-free cases.
- **Fix loop hard-capped as before** (2 retries), but the 3rd failure now
  writes a hook-owned `BLOCKED` verdict to `<run>/blocked.log` and stops the
  run — failing cases + evidence go into the summary.
- **Summary replaces retro + ship block + stakeholder report.**
  `.team-irfan/handoffs/<date>-<slug>.md` from `templates/summary.md`: one
  line per node, `diff --stat`, case counts, paste-able test commands,
  breaking changes, lessons (max 3 lines), a mermaid of what ran, one-line
  verdict. Printed in chat; the session ends after it.
- `agents/retro.md` deleted; `templates/brief.md` → `templates/scope.md`;
  `templates/report.md` is now Lead's evidence review; new
  `templates/plan.md`, `templates/plan.json`, `templates/test-cases.md`,
  `templates/summary.md`.
- `graph.json` v3: acyclic, all-leaf, **exactly one** human-approval node;
  nodes may carry `prompt` when a prompt file is shared (lead runs twice:
  options, review). Checks updated: plan-gate field-by-field, one-gate
  invariant, cap fallback, BLOCKED on 3rd attempt, assertion-free case scan,
  new template headings.

## v2.4.0 — 2026-08-18

Implements all seven diffs of
[`docs/evaluations/2026-08-18-fanible-msg91.md`](docs/evaluations/2026-08-18-fanible-msg91.md)
(n=3, direct run review — msg91 runs blew the cap 10×, lead lost its report
twice, scope approval was unreadable at the gate).

- `agents/router.md` — plan printed in chat before any approval question, at
  every human gate; the question itself carries no plan content.
- `agents/router.md` — mechanical cap: `ledger.sh read` before every spawn,
  ≥cap → stop. Cap moves only on an explicit number (`cap-raised:<n>`).
- `agents/router.md` — run state moves into the project:
  `.team-irfan/runs/<id>/` plus a session ledger `.team-irfan/runs/LEDGER.md`
  (one line per run, verdict flipped at close-out). `.tg-active` stays at repo
  root — the hooks read it there; hooks were verified path-agnostic.
- `agents/evaluation.md` — reads `.team-irfan/runs/*/metrics.json`, plus the
  legacy `~/.claude/team-graph/runs/` for pre-move history.
- `agents/lead.md` — evidence-not-testimony report (pasted diff --stat, gate
  line, per-task verdicts, file:line quotes) and a WRITE-DENIED fallback: the
  full report content returns in the final message for the orchestrator to
  write.
- `agents/router.md` — ship block goes to `.team-irfan/handoffs/` (session
  state, never pushed); a stakeholder report goes to `docs/reports/` —
  written, never committed, Irfan reviews and commits it himself — with
  copy-pasteable curl per changed endpoint for FE consumers.
- `agents/pjm.md` — SCOPE block draws the execution path (parallel lanes,
  merge points) and names one rejected alternative before approval.

---

## v2.3.0 — 2026-08-17

Implements the APPROVED LIST (D, F, I) of
[`docs/evaluations/review-20260817.md`](docs/evaluations/review-20260817.md).
No agent prompt changed; zero effect on per-route tool-call budgets. Checks go
174 → 183, zero failed.

### Added

- **Item D — plugin packaging.** `.claude-plugin/plugin.json` +
  `.claude-plugin/marketplace.json` + `hooks/hooks.json` wire the SubagentStop
  gate and the PostToolUse ledger on `/plugin install`, replacing the manual
  `settings.json` edit the README called "required for honest budget numbers".
  Both hooks stay `.tg-active`-gated; the repo stays at `~/.claude/team-graph`
  because agent prompts reference it by absolute path. Covered by check 23:
  exactly two events, `${CLAUDE_PLUGIN_ROOT}` commands, scripts exist and match
  the ones README names. Effect: removes the unwired-ledger install (the source
  of v2.1's self-counted 150) rather than any runtime call.
- **Item F — `hooks/doctor.sh`.** One command verifying install health:
  hook registration (in whatever JSON file it is handed — settings.json or
  hooks.json, hermetic by argument), fixture deps, a live ledger wiring probe,
  subagent-gate inertness without the marker, and the run-checks verdict
  (skippable via `TG_DOCTOR_FAST=1`). PASS/FAIL per item, non-zero exit on any
  FAIL. Covered by check 24: healthy synthetic install → all PASS + exit 0;
  registration file missing the ledger entry → FAIL line naming the ledger
  hook + non-zero exit. Effect: zero runtime calls; broken installs get caught
  before a run produces untrustworthy numbers.
- **Item I — subagent-gate.sh test coverage.** The hook had zero coverage while
  item D began auto-wiring it. Check 22 now asserts its three invariants: inert
  without `.tg-active` (exit 0, silent), exit 2 with the `GATE FAIL` reason
  under a marker and a red gate, and exit 0 on `stop_hook_active` (the loop
  trap). Effect: reliability only — the isolation other workflows depend on is
  now a failing check instead of a comment.

---

## v2.2.0 — 2026-08-15

**The numbers behind v2.1's headline were produced by an LLM counting its own
tool calls.** This release moves every measurement that governs a decision out of
the prompts and into scripts, then tests the claims the README was already
making. Checks go 74 → 174, zero failed.

### Fixed

- **The budget ledger was self-reported.** `metrics.sh` already refused agent
  self-assessment for `retries` and `over_budget`, but `tool_calls` came from a
  ledger the orchestrator kept by hand — the measured party reporting the
  measurement. New `hooks/ledger.sh` counts from a PostToolUse hook into an
  append-only `<run>/ledger.log`; `metrics.sh` reads it and ignores whatever was
  passed. Every "150/60" conclusion downstream now rests on a script.
  **Needs one additive `settings.json` entry — see the README install section.**
- **Concurrent testers lost retry counts.** `retry-guard.sh` did a
  read-modify-write behind an atomic rename, which fixes torn reads and does
  nothing for lost writes. Measured: 10 concurrent writers, 8 keys survived. Now
  serialised through `with_lock` in the new `lib/atomic.sh`; 10 of 10 survive.
- **A killed run left the gate armed for every unrelated session.** A stale
  `.tg-active` inverts the isolation guarantee into a global side effect, and
  "never leave one behind" was a prompt rule that cannot execute in the one case
  that matters. New `hooks/reap.sh` runs at the *start* of every FULL run.
  It removes orphan `tg-*` worktrees and stale markers, and **reports branches
  rather than deleting them** — see Rejected.
- **The coverage baseline was copied with a plain `cp`.** A resumed run
  re-recording it while executors read against it yields a torn read, which
  fails as `coverage dropped` — a wrong verdict, not a crash. Now an atomic
  replace, and a gate run inside a `tg-*` worktree records to its own file.

### Added

- **`graph.json`** — the FULL pipeline as data instead of an ASCII diagram.
  Checked for: every edge endpoint real, acyclic, every agent node a leaf, three
  `human-approval` nodes, a prompt file per node, no prompt file missing from the
  graph, and `effect_policy` agreeing with each file's frontmatter. F4 in
  evaluation 001 was a topology violation that survived because no artifact
  described the topology; that class is now a failing check.
- **Node contracts** — `timeout_ms`, `max_attempts`, `effect_policy` in every
  agent's frontmatter. The merge sequence is `reconcile` and `router.md` now
  carries the check that goes with it: three non-atomic steps behind a retry
  policy was the highest-severity latent bug in the repo.
- **`hooks/run-state.sh`** — `{completed, current}` after every node. "Kill any
  node mid-run and the next one picks up from disk" was a load-bearing claim with
  no test; resume is now a read rather than an inference from which artifacts
  happen to exist.
- **Quality metrics** — `gate_caught` (gate failures naming real code defects,
  derived from the stage, not asserted), `review_rounds`, `post_ship_fix`. Every
  previous field measured cost. An optimiser fed only cost tunes toward
  cheapness forever while the table keeps improving.
- **`route_outcome` + `human_minutes`** — the rubric's only falsifier. A
  HAND-BACK that should have run is invisible in every other number, because
  nothing ran and nothing overspent. Irfan answers; an invalid value is recorded
  as `null`, never stored.
- **Mutation smoke** in `gate.sh` (`TG_MUTATE=1`, Tester only). Stub detection is
  syntactic and catches a test that *looks* empty; this catches the one that
  looks fine and survives the deletion of the code it covers.
- **`benchmarks/`** — fixtures + ground truth + committed baseline for the
  Tester prompt, including a clean case that must produce zero findings. The
  baseline says `measured: false` and its nulls are not zeros: the set and the
  scorer exist, no agent has been run against them yet.
- **Evaluation authority split** — findings from direct run review are allowed at
  any n; findings derived from aggregated metrics are blocked below 5 runs with
  `INSUFFICIENT DATA — n=<k>, need 5`. Evaluation 001 applied eight sound diffs at
  n=1, all from run review and none from the numbers. The guard is structural
  now, not a disclaimer under a table that got printed anyway.
- **A line-count ceiling on every prompt file** — 560 for the orchestrator, 230
  for leaves. Growth becomes a failing check instead of invisible drift.

### Rejected

- **Splitting `router.md` into `triage.md` + `orchestrator.md`.** The finding is
  real — it is the largest file and every evaluation appends to it — but the
  remedy is priced in the wrong currency. Reading a file costs one tool call
  regardless of length, and tool calls are what this system budgets; the split
  adds a read to the FULL path to save context, which nothing here measures. It
  also divides the one context that holds the star topology together, and the
  failure the repo has actually experienced (a leaf told to spawn) is a coherence
  failure. Ceiling instead of split.
- **Deleting merged orphan branches in `reap.sh`.** A worktree branch is created
  at HEAD, so it reads as *already merged* the moment it exists — "delete merged
  orphans" would eat the branch of a run that crashed before its first commit.
  Reported, never deleted.

---

## v2.1.0 — 2026-08-15

**First release driven by a real run.** v2.0 was built and unit-checked but had
never executed a FULL pipeline end to end. It has now — a five-folder backend
feature — and this release is what that run exposed. Full record:
[`docs/evaluations/2026-08-15-user-block-unblock.md`](docs/evaluations/2026-08-15-user-block-unblock.md).

Headline: the run spent **150 tool calls against a 60-call design budget**, wrote
**zero context maps**, and reported **nothing** back to the operator.

### Fixed

- **Context maps were unwritable by design.** Every node was told "no map →
  generate it via `agents/init.md`", and every node was simultaneously declared a
  leaf that spawns nothing. `init` is a node, so the instruction could never
  execute in any context that carried it. Result: no map was ever written and
  every node re-read every in-scope folder cold. Map generation now belongs to
  the orchestrator, as new **step 3b**, before any executor spawns.
  (`agents/router.md`, `agents/pjm.md`)
- **`metrics.json` could report maps that do not exist.** The run recorded
  `maps_refreshed: src-home` while `.team-irfan/context/` was empty. The
  orchestrator must now `ls` the directory before passing `context_maps_used` or
  `maps_refreshed`. A false positive here is worse than an absent metric — the
  evaluation node reads it as evidence the memory layer worked.
  (`agents/router.md`)
- **Tool output could land in a committable path.** graphify was read from
  `graphify-out/graph.json` at the project root, which no `.gitignore` covers.
  Now `.team-irfan/graphify/graph.json`, with a blanket rule: every tool the
  graph runs writes inside `.team-irfan/`, and a tool that cannot be pointed
  there does not get run. (`agents/executor.md`)

### Changed

- **`opus` is now the default model for every node.** Downgrading to `sonnet`
  requires all three of: the node reads a spec it does not have to interpret,
  ≤2 files in scope, and no schema/contract/auth/security surface — and the
  reason gets printed in the ledger. `fable` is the fallback **for opus** when
  the account is at its cap, not a cheaper tier. `haiku` is never used: a node
  that cheap is a bash command. (`agents/router.md`, `agents/pjm.md`, README
  matrix)
- **Commit messages are specified.** Worktree commits are Conventional Commits,
  imperative, one line, ≤72 chars. Task ids (`T1`, `wip`, `changes`) are
  rejected — the previous run left a reflog reading `T1` … `T7`. **No
  `Co-Authored-By`, no `Generated with`, no AI attribution trailer**, on worktree
  commits and merge commits alike. (`agents/executor.md`, `agents/router.md`)
- **Every goal gets its own branch**, named `<type>/<slug>` where `<type>` is
  `feat` (new feature), `fix` (fixing broken behavior) or `chore` (docs, config,
  tooling) — e.g. `feat/block-unblock-user`. Branched off the default branch,
  never off the previous run's branch. Task branches inherit the goal's type; the
  `tg-` prefix stays on the worktree *directory* and is gone from branch names.
  (`agents/router.md`)
- **The merge is one commit per task, not one per run.** `--squash` collapses a
  single worktree's own in-progress commits, which are noise. It is not a way to
  fold separate tasks together — separate work stays a separate commit. The
  `docs/REGISTRY.md` entry is staged with the last task's commit.
  (`agents/router.md`)
- **PjM sizes the breakdown against the budget before writing it.** A tasks →
  projected-calls table (`20 + 27 × tasks`), and an explicit rule that more tasks
  is more fixed overhead, not more parallelism: each task buys a worktree, an
  executor, a tester and a merge. The SCOPE block now carries the projection, so
  raising the cap is a decision made with the number visible rather than
  discovered at call 150. (`agents/pjm.md`)

### Added

- **Progress reporting.** One line per node as it returns —
  `[3/10] pjm done · 5 tasks · budget 12/60`. Node, one fact, budget.
  (`agents/router.md`)
- **A ship block that reaches the operator.** `report.md` lives in the run
  directory outside the project and nobody reads it there. The orchestrator now
  prints — and writes to `docs/handoff/<date>-<slug>.md` — **What landed · How to
  run · How to test · Proof · Not done · Verdict**. "How to test" is the literal
  paste-able command; "Proof" is pasted `gate.sh` output, never a summary of it.
  (`agents/router.md`)
- **Wall clock is measured.** Executors stamp start and end and report elapsed
  minutes; over 15 requires a one-line reason. Deliberately *not* a cap: an agent
  cannot watch a clock while a tool call is in flight, so a prompt-level timeout
  is theatre. The number exists so scope can be told from thrash.
  (`agents/executor.md`)
- **[`docs/workflow.md`](docs/workflow.md)** — a visual walkthrough of the graph:
  the triage tree, the FULL pipeline with its three human gates, where state
  lives, the context-loading decision, the retry state machine, the budget model,
  and the safety boundary.
- **[`docs/evaluations/`](docs/evaluations/)** — evaluation records are now kept
  in the repository, so each release can be compared against the run that
  motivated it.

### Known stale

Out of the evaluation node's reach (it may edit `agents/` prompt files only), and
carried forward deliberately:

- `hooks/init-scaffold.sh` still detects `graphify-out` at the project root, so
  `/team-irfan init` reports `graphify index: none` for an index that now lives
  under `.team-irfan/`. A false negative, not a data risk.
- `templates/config.md` still describes `src/graphify-out`.
- `hooks/metrics.sh` has no field for per-node wall clock, so elapsed time
  reaches `change-summary` and the EXEC line but not `metrics.json`.
- A project-level `.team-irfan/config.md` written before this release still
  carries the old `sonnet` matrix. `agents/router.md` overrides it, so it is
  misleading rather than harmful — re-run `/team-irfan init` to refresh.

### Verification

`bash tests/run-checks.sh` → **74 passed, 0 failed, CHECKS PASS**.

---

## v2.0.0 — 2026-08-15

Star topology and the artifact-state model.

- Orchestrator moved into the main thread; every other node became a leaf that
  spawns nothing. The three human gates — PM's open questions, PjM's scope
  approval, the ship sign-off — live where a channel to the operator exists,
  because a subagent cannot stop and ask.
- Map-first context loading in all agents: per-folder context maps with a
  `last_commit` freshness anchor, and a ban on whole-repo indexing.
- `init` agent plus `config.md` / `context-map.md` templates, split rigid from
  probabilistic: `hooks/init-scaffold.sh` detects package manager, runner and
  commands; the agent fills only what requires reading code.
- Universal forbidden-actions block in every node, the model matrix, and metrics
  + evaluation wiring.
- Registry upkeep folded into the merge commit.
- Verification harness: 74 deterministic checks, zero agents, over a fixture with
  a seeded off-by-one bug and a toggleable stub test.
