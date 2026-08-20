# team-irfan

A multi-agent workflow for Claude Code. One command triages a task and either
hands it back to you, answers it, fixes it with one agent, or runs a full
review pipeline with real git worktrees and human approval gates.

**Stateless agents, artifact state, human gates.** No agent remembers anything —
all state lives in files. Kill any node mid-run and the next one picks up from
`<run>/run-state.json`, which records what finished and what was in flight —
and `hooks/reap.sh` clears the dead run's worktrees and markers before the next
one starts. Both are covered by checks, so that sentence is a property rather
than an intention.

The design goal is not "more agents". It is **spending fewer tool calls than
doing it yourself would cost**, and refusing to run at all when it wouldn't.

**New here?** [`docs/workflow.md`](docs/workflow.md) walks the whole graph
visually — the triage tree, the 7-step FULL pipeline and its single human gate
(the plan), where state lives, the context-loading decision, and the budget
model.
[`CHANGELOG.md`](CHANGELOG.md) is what changed and why;
[`docs/evaluations/`](docs/evaluations/) is the measured record each change came
from.

---

## Install

```bash
git clone https://github.com/irfanguvian/team-irfan.git ~/.claude/team-graph
```

**The clone location is load-bearing.** Every agent prompt references
`~/.claude/team-graph/...` by absolute path; installing anywhere else leaves
the graph pointing at nothing.

### Hooks via plugin (recommended)

Wire both hooks — the SubagentStop quality gate and the PostToolUse tool-call
ledger — in one step, no `settings.json` editing. In Claude Code:

```
/plugin marketplace add ~/.claude/team-graph
/plugin install team-irfan@team-irfan
```

The manifest is `.claude-plugin/plugin.json` → `hooks/hooks.json`. It wires
the SubagentStop quality gate, the PostToolUse ledger, the Stop-side
headless driver (`hooks/headless-driver.sh` — auto-approve sessions only:
blocks turn-end until the routed run's terminal artifact exists), and the
memory hooks
(`hooks/memory.sh` on SubagentStop/Stop for ingest, SessionStart for the
compiled-view load). Every hook stays **inert without a `.tg-active` marker**
in the working directory, exactly as in the manual install below — installing
the plugin changes nothing for any other workflow.

Register the slash commands — create `~/.claude/commands/team-irfan.md`:

```markdown
---
description: team-irfan agent graph — router triages the task
argument-hint: <task>
---

Read `~/.claude/team-graph/agents/router.md` and follow it exactly for this
turn. It is your system prompt; this message is your input.

TASK: $ARGUMENTS

- Triage first. Print the route before any other output.
- HAND-BACK means stop.
```

And `~/.claude/commands/team-irfan-evaluation.md`:

```markdown
---
description: Aggregate run metrics, find routing errors, propose prompt diffs
---

Read `~/.claude/team-graph/agents/evaluation.md` and follow it exactly.
Counts come from `runs/*/metrics.json` only, never from prose.
```

### Manual install (fallback)

Skip this section if you installed the plugin above — it wires the same two
hooks to the same two scripts.

Optional — enforce the quality gate on subagent exit. Add to
`~/.claude/settings.json` (additive; nothing else changes):

```json
"hooks": {
  "SubagentStop": [
    { "hooks": [ { "type": "command",
        "command": "bash ~/.claude/team-graph/hooks/subagent-gate.sh" } ] }
  ]
}
```

This hook is **inert** unless a `.tg-active` marker file exists in the working
directory, which only a full run creates. No marker, no effect — your other
workflows are untouched.

Required for honest budget numbers — the tool-call ledger. Same file, same
additive shape:

```json
"hooks": {
  "PostToolUse": [
    { "hooks": [ { "type": "command",
        "command": "bash ~/.claude/team-graph/hooks/ledger.sh hook" } ] }
  ]
}
```

Gated on `.tg-active` exactly like the gate hook: no marker, no counting, no
effect on any other workflow. **Without it the orchestrator has no source for
`tool_calls` but its own arithmetic**, and every budget and routing conclusion
downstream rests on the measured party reporting its own measurement.
`metrics.sh` falls back to the passed number when `ledger.log` is absent, so an
unwired install still runs — it just produces a number nobody should trust.

Verify the install:

```bash
cd ~/.claude/team-graph/tests/fixture && npm install
bash ~/.claude/team-graph/tests/run-checks.sh     # expect: 306 passed, CHECKS PASS
bash ~/.claude/team-graph/hooks/doctor.sh         # expect: DOCTOR PASS
```

`doctor.sh` checks install health — hooks registered, fixture deps, a live
ledger wiring probe, hook inertness without `.tg-active` — one PASS/FAIL line
per item. Plugin install? Point it at the manifest instead:
`bash ~/.claude/team-graph/hooks/doctor.sh ~/.claude/team-graph/hooks/hooks.json`.

---

## Usage

### `/team-irfan <task>`

Triages, then acts. Four outcomes:

| Route | When | What happens | Budget |
|---|---|---|---|
| **HAND-BACK** | under ~5 min by hand, or too ambiguous to triage | one line: `faster manually: <reason>`, then stops | — |
| **QUESTION** | asks something rather than changing something | answered directly, zero agents | — |
| **FAST** | ≤2 files, known pattern, no schema/contract change | one executor → quality gate → report | ≤15 calls |
| **FULL** | everything else | the 7-step pipeline below | ≤60 to plan approval, then the plan's `run_cap` |

```bash
/team-irfan "fix the off-by-one in the bulk discount threshold"
# ROUTE: FAST — 2 files, existing pattern, no contract change

/team-irfan "rename this variable"
# HAND-BACK — faster manually: one rename, under five minutes by hand

/team-irfan "add tiered discounts with per-customer overrides and an admin endpoint"
# ROUTE: FULL — 3+ files, schema change, API contract change
```

**HAND-BACK is a feature, not a failure.** Running a five-agent pipeline on a
typo is the most expensive thing this system can do. The router is instructed
to prefer handing back when it's unsure.

### `/team-irfan init`

Run once per project. Writes `.team-irfan/config.md`:

- package manager, test runner, linter, ORM — **detected**, not guessed
- the exact `typecheck` / `test` / `coverage` / `lint` / `build` commands, copied
  verbatim from `package.json`. A script that doesn't exist is written as `none`.
- conventions **extracted from your actual code** — folder layout, file naming,
  layering, how existing tests are written. Including the inconsistencies: a repo
  that mixes `payment_info.service.ts` with `sales-executive.service.ts` has two
  conventions, and agents need to know which one wins where.
- a per-project model matrix you can override

It also creates `docs/REGISTRY.md` if missing, and adds `.team-irfan/` to
`.gitignore` — context is local, never committed.

### `/team-irfan init <folder>`

Writes one context map, `.team-irfan/context/<folder-slug>.md`, capped at 80
lines:

```markdown
---
folder: src/app/vendor
last_commit: 232b9bef12fb74a1e2b86a24f6d28fddff9f7ca8
updated: 2026-08-15
---
## Purpose            (2-3 lines)
## Key files          (file → one-liner; the ones that explain the rest)
## Entry points       (routes, exports, cron jobs)
## Conventions        (only where this folder differs from config.md)
## Depends on / used by
## Registry tags      (FEAT/MOD/DEC ids to grep before reading code)
```

**Whole-repo indexing is banned.** Maps are per-folder and lazy — generated when
you name a folder, or on the first task that touches one. A repo with 40 folders
and 3 active ones ends up with 3 maps. That's correct, not incomplete.

### `/team-irfan-evaluation`

On-demand. Reads every `.team-irfan/runs/*/metrics.json` in the project (plus
the legacy `~/.claude/team-graph/runs/` pre-2026-08-18), aggregates, and finds
where the routing rubric is wrong:

- FAST runs that blew their budget → should have been FULL, or HAND-BACK
- FULL runs that were trivial → the rubric is too timid
- a hand-back rate near zero → the router isn't handing back, which is the most
  expensive failure mode because every run still *looks* successful

Each finding becomes a **concrete diff to an agent prompt file**, shown one at a
time, applied only on your `y`. It never edits itself, your `CLAUDE.md`, your
skills, or your settings.

---

## How context loading works

This is the part that makes repeat runs cheap. **Agents read context maps, not
folders.**

1. Resolve the folders in scope (Product writes `Folders in scope` into each
   task block of `plan.md`, so executors inherit scope mechanically).
2. Load `config.md` + the maps for **those folders only**.
3. Freshness check — one command per folder:
   ```bash
   git diff --name-only <last_commit> -- <folder>
   ```
   - **Empty** → the map is current. Trust it. **Do not re-read the folder.**
   - **Non-empty** → re-read **only the files it named** (≤10 tool calls),
     update `last_commit`.
4. No map → **the orchestrator** generates that one folder's map before any
   executor spawns. Not the node that noticed: every node is a leaf and cannot
   spawn `init`, so a map left to "whoever touches it first" is a map that never
   gets written.
5. Reading outside the in-scope folders is a **forbidden action**. Grep
   `docs/REGISTRY.md` for the `FEAT:`/`MOD:` tags instead, or read the
   neighbouring folder's map.

The failure this prevents is silent: an agent reads a stale map, writes code
against a convention that moved three commits ago, and the tests pass because it
compiles. One `git diff` per folder is cheaper than being wrong once.

---

## The FULL pipeline — 7 steps, one human gate

**Topology is a star, not a chain.** The orchestrator runs in the main thread;
every other node is a **leaf subagent** — one artifact in, one artifact out,
spawns nothing.

That isn't a style choice. The orchestrator is the only context with a channel
to you, and this pipeline has exactly ONE hard human gate — the plan approval.
A subagent cannot stop and ask — so a gate held by a subagent silently degrades
into an assumption with a checkbox. The gate lives in the main thread, and
therefore nothing nests.

```
ORCHESTRATOR (main thread)
  │  owns: the sequence · the budget ledger · every git operation
  │        · the challenger refereeing · the one conversation with you
  │
  │  STEP 1 — PLAN
  ├─ memory.sh retrieve --agent product ──► ## MEMORY block into the prompt
  ├─ PRODUCT ─────────────► plan.draft.md + plan.json
  │    ONE node owns product, project and business flow — no brief→tasks
  │    handover. Business rules (each sourced: file:line, R-id, confirmed
  │    by user, or "ask user"), SCOPE block, PHASES block, per-task spec
  │    blocks. Open questions at the TOP of the plan.
  │    run_cap = min(round(chosen expected_calls × 1.3), 60).
  ├─ PRODUCT-CHALLENGER ──► challenge.md · ACCEPT / REVISE:<items>
  │    The user's prompt named a path → verify it only (feasibility,
  │    unsourced claims, projection, compat risks). Goal without a path →
  │    ≥2 alternatives with call projections. ACCEPT → draft becomes
  │    plan.md. REVISE → Product addresses or rejects each item, once;
  │    unresolved → both positions printed for you.
  ├─ hooks/plan-gate.sh ──► plan.json schema + run_cap arithmetic
  ├─ hooks/plan-check.sh ─► PHASES parsed, every projection RECOMPUTED
  │    (26 + 27×tasks), any phase over cap → bounced to Product.
  │    Emits "PLAN OK: n phases, max projection X/60" — pasted above the
  │    question.
  │     ⏸ YOU APPROVE THE PLAN ⏸   plan.md printed in chat in FULL first;
  │                                open questions answered in the same
  │                                exchange. Silence is not approval.
  │                                The ONLY human gate.
  │    Multi-phase plans execute PHASE 1 ONLY — each later phase is a
  │    fresh run with its own ledger, gates, and approval.
  │
  │  STEP 2 — EXECUTE + TEST-CASE GEN, in parallel
  ├─ git worktree add ../tg-<slug>-<id> -b <type>/<slug>-<id>
  ├─ EXECUTOR ×N ─────────► change-summary-<id>.md + GATE PASS
  │    Each gets its own Task block from plan.md, never the whole plan.
  │    Rule A: a pre-existing test failing = compat break, stop or declare
  │    INTENTIONAL BREAKING (only valid if the plan declares it). Walks
  │    skills/guardrails/breaking-changes.md before the summary.
  ├─ QA (phase=cases) ────► test-cases.md — from plan.json ONLY, blind to
  │    every diff and worktree.
  ├─ QA-CHALLENGER ───────► challenge-qa.md — coverage gaps + missing
  │    backward-compat cases from the checklist, BEFORE anything executes.
  │
  │  STEP 3 — QA RUNS (per finished task)
  ├─ QA (phase=run) ──────► test-report-<id>.md — each case PASS/FAIL with
  │    pasted output, then the FULL regression manifest
  │    (hooks/qa-manifest.sh) — any manifest failure is a compat break and
  │    a blocker, regardless of the new feature's own tests.
  │
  │  STEP 4 — FIX LOOP, HARD-CAPPED
  │    FAIL → only the failing cases + evidence, SAME executor, SAME
  │    worktree. retry-guard.sh: max 2 retries. 3rd failure → the run STOPS,
  │    BLOCKED written to blocked.log by the hook. No "continue?" loop.
  │
  │  STEP 5 — MERGE + LEAD REVIEW (machine gate, no human)
  ├─ git merge --squash · commit · worktree remove   (one commit per task,
  │    registry entry staged with the last one)
  ├─ memory.sh retrieve --agent lead ──► ## MEMORY block into the prompt
  ├─ LEAD ────────────────► report.md · verdict PASS | BLOCKED
  │    Merged diff only. Walks the breaking-change checklist — an
  │    undeclared hit is BLOCKED, never a footnote.
  ├─ LEAD-CHALLENGER ─────► challenge-lead.md · PASS | BLOCKED
  │    Blind re-review of the same diff (never reads report.md). Verdict
  │    disagreement = automatic blocker, both positions to you.
  │
  │  STEP 6 — SUMMARY (+ retro maintenance)
  ├─ .team-irfan/handoffs/<date>-<slug>.md — one line per node, diff --stat,
  │    case counts, paste-able test commands, breaking changes, lessons,
  │    verdict. Multi-phase → ends with "NEXT PHASE: <goal>". QA's new
  │    cases appended to the regression manifest. memory.sh compact.
  │    metrics.json from the ledger.
  │
  └─ STEP 7 — END. The session terminates. Nothing else runs.
     (SubagentStop/Stop hooks ingested plan.md, the review report, and the
      ship block into .team-irfan/memory/ along the way — one Haiku call
      per artifact, ops-only contract, never blocking.)
```

One progress line reaches you as each node returns —
`[1/7] product done · 2 tasks · budget 12/39`. Node, one fact, budget.

## Quality gate

`hooks/gate.sh` — deterministic, zero LLM, run from a project root:

1. Detects package manager (pnpm/yarn/bun/npm) and runner (vitest/jest)
2. Typecheck → fail = exit 1
3. Unit tests → fail = exit 1
4. Coverage diff — per-file, on changed files only, against a recorded baseline
5. **Stub detection** — `expect(true)`, `assert.ok(true)`, `.skip(`, `.only(`,
   `it.todo`, `xit(`, and multi-line empty test bodies. Any hit fails with
   `file:line`.
5b. **Assertion-free test cases** — with `TG_RUN` set, `<run>/test-cases.md`
   is scanned: a CASE with no non-empty `expect_body`/`expect_effect`, or an
   `expect(true)`-style line, fails with the case named.
6. **Mutation smoke** (opt-in, `TG_MUTATE=1`) — replaces each changed
   implementation with throwing stubs and re-runs that file's tests. A suite
   still green without the code it covers is asserting nothing:
   `GATE FAIL: tests survive mutation`. QA runs it; executors do not,
   because it re-runs the suite once per changed file.
7. `GATE PASS` or `GATE FAIL: <reason>`

Every executor must run it and paste the output. A report without gate output is
not a report.

```bash
bash hooks/gate.sh                    # from a project root
TG_SCAN=all bash hooks/gate.sh        # scan every test file, not just changed
TG_MUTATE=1 bash hooks/gate.sh        # + mutation smoke (slow, QA only)
```

> **If you use RTK:** `gate.sh` deliberately calls `tsc`/`vitest` raw. Measured:
> `rtk test bash -c 'exit 1'` returns **0** — it swallows the child exit code, so
> a green-looking `rtk` run can be a red suite. The RTK PreToolUse hook rewrites
> an agent's `npx vitest run` into `rtk vitest run`, which is why `gate.sh` is the
> only test result any node is allowed to cite.

---

## Safety

Every agent carries an identical forbidden-actions block:

- **No `git push`** in any form — no force, no tags, no releases
- **No deploys** — vercel, fly, kubectl apply, terraform apply, docker push
- **No CI triggers or bypasses** — no `workflow_dispatch`, no `[skip ci]`, no
  editing a workflow to make a check pass. **CI stays the final gate.** A green
  `gate.sh` is a local signal, not permission to skip CI.
- **No reading or writing `.env*`, secrets, credentials, keys**
- **No destructive migrations** — `DROP`, `TRUNCATE`, `migrate reset`,
  `--accept-data-loss`. Proposed with a rollback plan for you to run.
- **No package publishing**
- **No editing outside declared scope**

> **The workflow's terminus is a local merge commit. You push. You deploy.**

---

## Efficiency contract

- **FAST ≤15 tool calls. FULL: ≤60 until the plan is approved, then the
  plan's own `run_cap`** — `min(round(chosen option's expected_calls × 1.3),
  60)`, computed by Product and verified by `plan-gate.sh`. A PostToolUse hook
  keeps the ledger — `hooks/ledger.sh`, appending one line per tool call to
  `<run>/ledger.log` — and the orchestrator reads it. It does not count. A
  number the measured party types is not a measurement. At the cap the run
  stops with a partial summary rather than overrunning silently.
- **Every plan is written against the cap, or split until it is.** The
  projection formula is **`26 + 27×tasks`** per phase (challenger spawns
  priced in), recomputed — never trusted — by `hooks/plan-check.sh` before
  the gate. A phase over 60 bounces the plan back to Product; multi-phase
  plans execute phase 1 only, and each later phase is a fresh run. plan-check
  is design-time; the ledger is runtime. Both.
- **Challenger calls count in the same ledger.** No side budget: each
  challenger is capped at 5 tool calls and reads artifacts + context maps
  only, never trees.
- **The cap is checked mechanically, before every spawn.** `ledger.sh read`
  and `ledger.sh cap` (plan.json `run_cap`, fallback 60) run before each
  node; at or over the cap, nothing spawns. The cap moves only when you state
  a new number in chat (`cap-raised:<n>` in the metrics) — "keep going" is
  not a number. A second raise on one run is a plan-sizing failure, and the
  orchestrator says so when it asks.
- Per-node budgets are **ceilings, not allowances**, and deliberately don't
  sum to the cap. The projection is in the plan itself — each option's
  `expected_calls` — so the cap is set with the number visible, at the plan
  gate, not discovered at call 150.
- **Agents never read whole trees.** Context maps first, then `docs/REGISTRY.md`
  by tag (`head -40`, `grep -n "FEAT:"`, `sed -n` the hits — never `cat`), then
  targeted files.
- **More tasks is more overhead, not more parallelism.** Each task buys a
  worktree, an executor, a QA run and a merge. Splitting is for work that
  genuinely cannot share a file — never for work that merely can be described in
  more sentences. Product prints the projection in the SCOPE and PHASES blocks so the cap is
  raised with the number visible, not discovered at call 150.
- **Retry limit 2, then the run stops.** The 3rd failure writes a hook-owned
  `BLOCKED` to `<run>/blocked.log`; the failing cases and evidence go into
  the summary. No silent loops, no in-chat "continue?".
- **Wall clock is measured, not capped.** Executors report elapsed minutes and
  must justify anything over 15. There is no hard abort: an agent cannot watch a
  clock while a tool call is in flight, so a prompt-level timeout is theatre. The
  number exists to tell scope from thrash.
- FAST reports are four questions — Done / Fine or not / Blockers / Next —
  plus a verdict line. FULL ends with the summary: one line per node, pasted
  `diff --stat`, case counts, paste-able test commands, breaking changes,
  lessons (max 3 lines), a verdict.

---

## Rigid vs probabilistic

A deterministic check is never handed to a prompt. A prompt never replaces a
deterministic check.

| Rigid (hooks, zero LLM) | Probabilistic (prompts) |
|---|---|
| typecheck, unit tests, coverage diff | problem solving |
| stub-test detection, mutation smoke | test-case design |
| retry limit / escalation | convention extraction |
| worktree isolation, crash reaping | documentation |
| package manager + command detection | lessons in the summary |
| the tool-call ledger | scope and sizing |
| the resume point | why a run went wrong |

That's why `/team-irfan init` is split in two: `hooks/init-scaffold.sh` detects
the package manager and copies the commands (facts in a file), and the agent
fills only Conventions, Purpose, and Key files (things that need reading code).

---

## Model matrix

Default, overridable per-project in `.team-irfan/config.md`:

**`opus` is the default for every node.** It does not need a reason; a downgrade
does.

| | model | when |
|---|---|---|
| every node | `opus` | default |
| any node | `sonnet` | only when **all three** hold: it reads a spec it does not have to interpret · ≤2 files in scope · no schema, contract, auth or security surface. The reason gets printed in the ledger. |
| any node | `fable` | the account is at its Opus cap. This is the fallback **for** opus, not a cheaper tier — say so: `exec-3 fable (opus capped)` |
| any node | `haiku` | never. A node that cheap is a bash command, not an agent. (One exception that is not a node: memory ingestion makes a single `claude -p --model haiku` extraction call — ops-only contract, never blocking.) |

**Benchmarks override the matrix uniformly**: `TG_BENCH_MODEL=haiku|sonnet`
pins every node to that model and stamps `bench_model` into `metrics.json`, so
a benchmark number can never be mistaken for a production run. The production
rule (`haiku: never`) is untouched.

Overridable per-project in `.team-irfan/config.md`, but `agents/router.md` wins
over any matrix. The orchestrator passes `model` explicitly on each spawn — the
`model:` line in a role file is documentation, since these files aren't
registered subagents and nothing parses their frontmatter.

---

## Layout

```
graph.json   the FULL pipeline as data — nodes, edges, the one human gate,
             effect policies. Validated by the checks: acyclic, every agent
             node a leaf, exactly one human-approval node, and every policy
             matching the prompt file's frontmatter.
agents/      router · product · product-challenger · lead · lead-challenger
             executor · qa · qa-challenger · solo-executor · init · evaluation
hooks/       gate.sh · plan-gate.sh · plan-check.sh · retry-guard.sh
             subagent-gate.sh · ledger.sh · memory.sh · qa-manifest.sh
             reap.sh · run-state.sh · metrics.sh · init-scaffold.sh · doctor.sh
lib/         atomic.sh   shared write primitives (atomic replace, lock)
benchmarks/  run.sh + tester/{fixtures,ground-truth} + baselines/  — plus
             harness-v3/, the three-arm harness×model matrix (see below)
skills/      guardrails/   engineering rules every node obeys, plus
                           breaking-changes.md — the compat checklist
             context-loading/   the map-first rule
templates/   plan (md+json — the one Product artifact: rules, SCOPE, PHASES,
             task blocks) · change-summary · test-cases · test-report
             report · summary · config · context-map · metrics.json
runs/        legacy pre-2026-08-18 run state. Current runs live in the
             project: .team-irfan/runs/<yyyymmdd-slug>/ (gitignored), with
             .team-irfan/runs/LEDGER.md — one line per run, latest last —
             as the session ledger any later session resumes from
tests/       fixture/ · run-checks.sh · cases.md
docs/        workflow.md   the visual walkthrough
             memory.md     the agent-memory design + mem0 decision record
             evaluations/  what past runs measured, and what changed because of it
CHANGELOG.md what changed in each version of the workflow
```

A run directory holds `plan.draft.md`, `challenge.md`, `plan.md`,
`plan.json`, `test-cases.md`, `challenge-qa.md`, `change-summary-<id>.md`,
`test-report-<id>.md`, `retries.json`, `blocked.log`, `run-state.json`,
`ledger.log`, `ledger.json`, `report.md`, `challenge-lead.md`,
`metrics.json`. The project additionally keeps `.team-irfan/memory/`
(Product + Lead memory) and `.team-irfan/qa/` (the persistent regression
suite) across runs.

### Memory — Product and Lead remember, deterministically

Design and decision record: [`docs/memory.md`](docs/memory.md). SQLite +
FTS5/BM25, per-repository, gated on `.tg-active`, and **never blocking** — a
memory failure logs one line and exits 0. The orchestrator retrieves top-12
facts before spawning Product or Lead and pastes them as a read-only
`## MEMORY` block; SubagentStop/Stop hooks ingest the plan, the review
report, and the ship block (one Haiku call each, JSON-ops-only contract —
Haiku proposes, the pipeline disposes). Every operation appends one line to
`.team-irfan/memory/memory.log`:

```
<ts> <op:ingest|retrieve|compile|compact> <agent> <ok|error> adds=<n> updates=<n> retires=<n> hits=<n> stale=<n> ms=<n> [err=<msg>]
```

That log is the only health signal memory has — `/team-irfan-evaluation`
reads it and reports ingest error rate, malformed-JSON rate, hit counts,
stale-flag frequency, and a plain verdict.

### QA persistence + backward compatibility

QA keeps no memory db — what persists is the **regression suite**:
`.team-irfan/qa/{collections,curl,browser}/` plus `regression.manifest`,
executed whole every run (`hooks/qa-manifest.sh`, exit-code honest). Any
manifest failure is a compat break and a blocker. On ship the new cases are
appended; the suite only grows.

Two more mechanisms, both mandatory: **rule A** (a pre-existing test failing
under new work is a compat break by definition — restore compatibility or
declare `INTENTIONAL BREAKING`, valid only if the approved plan declares it)
and the **static breaking-change checklist**
([`skills/guardrails/breaking-changes.md`](skills/guardrails/breaking-changes.md)),
walked by the executor before its summary, by qa-challenger against the
cases, and by Lead — where an undeclared hit is a blocker, never a footnote.

### Node contracts

Every `agents/*.md` declares `timeout_ms`, `max_attempts` and `effect_policy`.
The last one is what changes behaviour on a retry:

| policy | means | on retry |
|---|---|---|
| `side_effect_free` | writes nothing but its own artifact | re-spawn freely |
| `idempotent` | its own worktree, or overwrites its own file | re-spawn freely |
| `reconcile` | shared state — merges, commits, counters | check whether the effect already landed, then skip or finish |

The merge is `reconcile` and this is not theoretical: `git merge --squash` →
`git commit` → `git worktree remove` is one logical effect in three non-atomic
steps, and a retry after a partial merge either duplicates the commit or drops
the task, with nothing in `metrics.json` able to tell you which.

### Benchmarks

```bash
bash benchmarks/run.sh --dry-run                 # validate the set, zero agents
bash benchmarks/run.sh --prompt off-by-one       # print the prompt to run
bash benchmarks/run.sh --score off-by-one r.md   # score against ground truth
bash benchmarks/run.sh --save-baseline           # commit the new numbers
```

Four cases for QA: a seeded off-by-one under a green suite, a suite that
asserts on a mock and never on an outcome, a **clean** one that must produce
zero findings, and a **compat trap** — a change that passes its own new tests
while breaking a pre-existing endpoint (the `checkout` contract); a tester
that trusts the new tests alone, or edits the old test to green it, scores
zero. The clean case is the false-positive guard; the trap is the rule-A
guard. The committed baseline currently says `measured: false`; nulls in it
are not zeros — replace them only with real run numbers.

`--score` also records measured dimensions when handed the artifacts:
`TG_SCORE_GATE` (gate output → PASS/FAIL), `TG_SCORE_REGRESSION`
(qa-manifest output), `TG_SCORE_RUN` (ledger.log → tool calls, source:
ledger; retries.json → retries), `TG_SCORE_TRANSCRIPT` (turn count for
non-team arms, labeled as a transcript count, never passed off as a ledger),
`TG_SCORE_WALL`, and `TG_BENCH_MODEL` → `bench_model`.

The **workflow-vs-model** claim — correctness comes from the harness, not the
model — runs in [`benchmarks/harness-v3/`](benchmarks/harness-v3/README.md):
harness ∈ {bare Claude Code, OMC, team-irfan} × model ∈ {haiku, sonnet} via
`TG_BENCH_MODEL`, 3 rounds each, same model across arms within a round, with
feature tasks scored against ground-truth diffs and a backward-compat trap
(T3) that fails hard no matter how fast the result is.

---

## Tests

```bash
bash tests/run-checks.sh        # 306 deterministic checks, zero agents
```

Covers: stub rejection with `file:line` · clean-fixture pass · typecheck failure
· unit-test failure · retry escalation on the 3rd attempt, writing `BLOCKED` to
`blocked.log` · plan-gate field-by-field (a valid plan passes, every missing or
malformed field fails by name, run_cap arithmetic verified) · the one-human-gate
invariant · `ledger.sh cap` reading run_cap with a 60 fallback · assertion-free
test-case rejection in `test-cases.md` · per-task-id counters
· template field headings · agent contracts (budget, model, forbidden block,
leaf clause, timeout/attempts/effect policy) · init scaffold command detection ·
context-map headings and the 80-line cap · staleness detection in **both**
directions · metrics schema with derived fields · that `Agent(` appears in no
agent file except the orchestrator's · the ledger outranking any passed
tool-call number, including under 20 concurrent writers · crash reaping that
never deletes a branch · resume from `run-state.json` alone · `graph.json`
acyclic, exactly one human gate, and agreeing with the prompt files · quality fields derived from gate
stages · route outcome validated against its enum · 10 concurrent retry-guard
writers losing no keys · mutation smoke catching a vacuous test and
false-positiving on none · the benchmark scorer discriminating in both
directions · a line-count ceiling on every prompt file · plan-check's
pass/fail matrix (good fixture, missing PHASES block, wrong projection,
over-cap phase) · challenger contracts (≤5 calls, side_effect_free, verdict
vocabulary, blindness rules, FAST untouched) · memory round-trip, hash
dedup, never-blocks on a corrupted db, the memory.log line format, and
`[maybe-stale]` flagging · the Haiku infer path dropping malformed JSON and
compact enforcing the row cap · the breaking-change checklist present and
loaded by the right agents, rule A stated · qa-manifest.sh exit-code honest
in both directions, loud on a shrunken suite · the compat-trap fixture
scored in both directions · and `TG_BENCH_MODEL` stamping `bench_model`
into benchmark metrics while production metrics stay unstamped.

The fixture is a small TypeScript package with a seeded off-by-one bug, a
second endpoint (`checkout`) whose contract test enables the compat trap,
and a toggleable stub test. The harness restores it on exit.

---

## Requirements

Claude Code · `git` · `node` · `bash`. Projects are assumed to be Node/TypeScript
with `vitest` (never jest) — the gate degrades gracefully elsewhere but the
guardrails are written for that stack.

## Status

**v3.1.0 — the v3 redesign completed.** One **Product** node owns product,
project and business flow (PM + PjM merged; no brief→tasks handover), with
per-task spec blocks inside the single `plan.md`. **Challenger siblings**
(product / qa / lead) verify without breaking the star — spawned by the
orchestrator, debating via artifacts, one revision round, disagreement
surfaced to you. **Budget-phased planning**: every plan carries a PHASES
block, `plan-check.sh` recomputes `26 + 27×tasks` per phase, and multi-phase
plans execute phase 1 only. **Agent memory** for Product and Lead
(SQLite + FTS5, deterministic, never blocking — `docs/memory.md`), seeded by
init, ingested by hooks, retrieved at spawn. **Backward compatibility
first-of-mind**: rule A, the breaking-change checklist, and QA's persistent
regression manifest. Benchmarks gained the harness×model matrix
(`TG_BENCH_MODEL`) and the compat-trap case.

**v3.0.0 — the 7-step FULL harness.** Human gates went from three to one: the
plan approval, fed by a deterministic `plan-gate.sh` and priced by the plan's
own `run_cap`. QA writes its cases blind, from the approved plan only; Lead's
evidence review is the machine ship gate; the summary replaces the retro. The
triage tiers and every trust mechanism from v2.2–v2.4 (ledger, retry lock,
derived metrics, run-state resume) are unchanged.

**v2.2.0.** One end-to-end FULL run has been exercised — a five-folder backend
feature. It shipped, and it cost 150 tool calls against a 60-call design budget
while writing zero context maps and reporting nothing back. Everything that run
exposed was fixed in v2.1.0; the measured record is
[`docs/evaluations/2026-08-15-user-block-unblock.md`](docs/evaluations/2026-08-15-user-block-unblock.md)
and the changes are in [`CHANGELOG.md`](CHANGELOG.md).

That "150" was typed by the orchestrator counting its own tool calls. v2.2 moves
every number that governs a decision into a script: the ledger is a hook, the
retry count is a locked counter, `gate_caught` and `review_rounds` are derived,
and the only field a human supplies is the one only a human can answer —
`route_outcome`. The next FULL run produces numbers worth believing.

**v2.4 — three runs measured, trust is the theme.** The two msg91 runs
(2026-08-17) blew the 60-call cap 10× (658 and 590), the lead failed to write
its report twice, and the scope approval arrived as a dialog with no readable
plan. The 2026-08-18 evaluation (n=3, direct run review — the aggregate stays
blocked below n=5) landed seven prompt diffs: plan printed in chat before any
approval question · a mechanical pre-spawn ledger check on the cap · run state
moved into the project at `.team-irfan/runs/` with a session `LEDGER.md` ·
handoffs into `.team-irfan/handoffs/` (never pushed) · an evidence-not-testimony
lead report with a write-denied fallback · a stakeholder report under
`docs/reports/` (written, never committed — you commit it) with curl tests per
changed endpoint · and the plan's SCOPE block drawing the execution path with a
rejected alternative. Record:
[`docs/evaluations/2026-08-18-fanible-msg91.md`](docs/evaluations/2026-08-18-fanible-msg91.md).

n=3 — the routing rubric still has thin evidence behind it, and the evaluation
node **refuses** to tune it from aggregates below five runs. Keep running
`/team-irfan-evaluation` after runs; direct run review works at any n.

Nested subagent spawning is unverified in this harness; the star topology means
it doesn't matter.
