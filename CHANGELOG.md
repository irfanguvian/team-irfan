# Changelog

Notable changes to the team-irfan workflow. Versions are the workflow's, not any
project's.

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
