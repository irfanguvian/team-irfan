# team-irfan

A multi-agent workflow for Claude Code. One command triages a task and either
hands it back to you, answers it, fixes it with one agent, or runs a full
review pipeline with real git worktrees and human approval gates.

**Stateless agents, artifact state, human gates.** No agent remembers anything —
all state lives in files. Kill any node mid-run and the next one picks up from
disk.

The design goal is not "more agents". It is **spending fewer tool calls than
doing it yourself would cost**, and refusing to run at all when it wouldn't.

---

## Install

```bash
git clone https://github.com/irfanguvian/team-irfan.git ~/.claude/team-graph
```

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

Verify the install:

```bash
cd ~/.claude/team-graph/tests/fixture && npm install
bash ~/.claude/team-graph/tests/run-checks.sh     # expect: 74 passed, CHECKS PASS
```

---

## Usage

### `/team-irfan <task>`

Triages, then acts. Four outcomes:

| Route | When | What happens | Budget |
|---|---|---|---|
| **HAND-BACK** | under ~5 min by hand, or too ambiguous to triage | one line: `faster manually: <reason>`, then stops | — |
| **QUESTION** | asks something rather than changing something | answered directly, zero agents | — |
| **FAST** | ≤2 files, known pattern, no schema/contract change | one executor → quality gate → report | ≤15 calls |
| **FULL** | everything else | the full pipeline below | ≤60 calls |

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

On-demand. Reads every `runs/*/metrics.json`, aggregates, and finds where the
routing rubric is wrong:

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

1. Resolve the folders in scope (the project manager writes `folders in scope`
   into each task spec, so executors inherit scope mechanically).
2. Load `config.md` + the maps for **those folders only**.
3. Freshness check — one command per folder:
   ```bash
   git diff --name-only <last_commit> -- <folder>
   ```
   - **Empty** → the map is current. Trust it. **Do not re-read the folder.**
   - **Non-empty** → re-read **only the files it named** (≤10 tool calls),
     update `last_commit`.
4. No map → generate that one folder's map, then proceed.
5. Reading outside the in-scope folders is a **forbidden action**. Grep
   `docs/REGISTRY.md` for the `FEAT:`/`MOD:` tags instead, or read the
   neighbouring folder's map.

The failure this prevents is silent: an agent reads a stale map, writes code
against a convention that moved three commits ago, and the tests pass because it
compiles. One `git diff` per folder is cheaper than being wrong once.

---

## The FULL pipeline

**Topology is a star, not a chain.** The orchestrator runs in the main thread;
every other node is a **leaf subagent** — one artifact in, one artifact out,
spawns nothing.

That isn't a style choice. The orchestrator is the only context with a channel
to you, and this pipeline has three hard human gates. A subagent cannot stop and
ask — so a gate held by a subagent silently degrades into an assumption with a
checkbox. The gates live in the main thread, and therefore nothing nests.

It also means the pipeline doesn't depend on whether nested subagent spawning
works in your harness. Every node is a leaf, so the question never arises.

```
ORCHESTRATOR (main thread)
  │  owns: the sequence · the budget ledger · every git operation
  │        · every conversation with you
  │
  ├─ PM ──────────────────► brief.md
  │    Every business rule carries a source: a file:line, a registry id, or
  │    "confirmed by you". A rule it inferred is not a rule — it's a question.
  │     ⏸ YOU ANSWER ⏸
  │
  ├─ PjM ─────────────────► tasks.md + one task-spec per task
  │    Executor count comes from the breakdown. Backend-only work spawns
  │    zero frontend agents.
  │     ⏸ YOU APPROVE SCOPE ⏸   silence is not approval
  │
  ├─ git worktree add ../tg-<slug>-<id>      one per task, never shared
  │
  ├─ EXECUTOR ×N ─────────► change-summary.md + GATE PASS
  │    Independent ones run concurrently. Ponytail rules: reuse before writing,
  │    stdlib before dependency, root cause not symptom.
  │
  ├─ TESTER ──────────────► test-report.md
  │    Writes test cases from the SPEC, before looking at the diff. Runs the
  │    exact verify commands from change-summary.md. Real curl/browser evidence.
  │    FAIL → same executor, same worktree, with the bug block.
  │           Max 2 retries, then ESCALATE. No silent loops.
  │
  ├─ git merge --squash · worktree remove
  │    Whole feature lands as ONE commit, with the docs/REGISTRY.md entry
  │    in the same commit.
  │
  ├─ LEAD ────────────────► review of the MERGED diff + report.md
  │    Reviews the merged diff, not each worktree — the bug that matters is the
  │    one two tasks create together. Max 2 review rounds.
  │     ⏸ YOU SIGN OFF ⏸    breaking change = blocker, never a footnote
  │
  └─ RETRO ───────────────► lessons.md, shown to you.
                            Never edits CLAUDE.md, a skill, or a hook.
```

---

## Quality gate

`hooks/gate.sh` — deterministic, zero LLM, run from a project root:

1. Detects package manager (pnpm/yarn/bun/npm) and runner (vitest/jest)
2. Typecheck → fail = exit 1
3. Unit tests → fail = exit 1
4. Coverage diff — per-file, on changed files only, against a recorded baseline
5. **Stub detection** — `expect(true)`, `assert.ok(true)`, `.skip(`, `.only(`,
   `it.todo`, `xit(`, and multi-line empty test bodies. Any hit fails with
   `file:line`.
6. `GATE PASS` or `GATE FAIL: <reason>`

Every executor must run it and paste the output. A report without gate output is
not a report.

```bash
bash hooks/gate.sh                    # from a project root
TG_SCAN=all bash hooks/gate.sh        # scan every test file, not just changed
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

- **FAST ≤15 tool calls. FULL ≤60 per feature**, everyone's calls included.
  The orchestrator keeps a ledger and stops at 60 with a partial report rather
  than overrunning silently.
- Per-node budgets are **ceilings, not allowances**, and deliberately don't sum
  to 60 — a 2-task feature at every ceiling would spend ~100. Realistic
  projection is roughly `20 + 27×tasks`; over 60, the orchestrator asks you to
  raise the cap or cut scope **before** the first worktree.
- **Agents never read whole trees.** Context maps first, then `docs/REGISTRY.md`
  by tag (`head -40`, `grep -n "FEAT:"`, `sed -n` the hits — never `cat`), then
  targeted files.
- **Retry limit 2, then escalate.** No silent loops.
- Reports are always four questions — Done / Fine or not / Blockers / Next —
  plus a verdict line.

---

## Rigid vs probabilistic

A deterministic check is never handed to a prompt. A prompt never replaces a
deterministic check.

| Rigid (hooks, zero LLM) | Probabilistic (prompts) |
|---|---|
| typecheck, unit tests, coverage diff | problem solving |
| stub-test detection | test-case design |
| retry limit / escalation | convention extraction |
| worktree isolation | documentation |
| package manager + command detection | retro feedback |

That's why `/team-irfan init` is split in two: `hooks/init-scaffold.sh` detects
the package manager and copies the commands (facts in a file), and the agent
fills only Conventions, Purpose, and Key files (things that need reading code).

---

## Model matrix

Default, overridable per-project in `.team-irfan/config.md`:

| node | model | why |
|---|---|---|
| router / orchestrator | opus | triage is the highest-leverage decision here |
| pm | opus | inventing a business rule is the most expensive failure |
| lead | opus | merge review, breaking-change judgement |
| init | opus | convention extraction is all judgement |
| evaluation | opus | reads the record, proposes changes |
| pjm, executor, tester, solo-executor, retro | sonnet | bounded work against a written spec |

The orchestrator passes `model` explicitly on each spawn. The `model:` line in a
role file is documentation — these files aren't registered subagents, so nothing
parses their frontmatter.

---

## Layout

```
agents/      router · pm · pjm · lead · executor · tester · retro
             solo-executor · init · evaluation
hooks/       gate.sh · retry-guard.sh · subagent-gate.sh
             metrics.sh · init-scaffold.sh
skills/      guardrails/   engineering rules every node obeys
             context-loading/   the map-first rule
templates/   brief · task-spec · change-summary · test-report
             report · lessons · config · context-map · metrics.json
runs/        runs/<yyyymmdd-slug>/  — all state for one run
tests/       fixture/ · run-checks.sh · cases.md
```

A run directory holds `brief.md`, `tasks.md`, `task-<id>.md`,
`change-summary-<id>.md`, `test-report-<id>.md`, `retries.json`, `report.md`,
`metrics.json`, `lessons.md`.

---

## Tests

```bash
bash tests/run-checks.sh        # 74 deterministic checks, zero agents
```

Covers: stub rejection with `file:line` · clean-fixture pass · typecheck failure
· unit-test failure · retry escalation on the 3rd attempt · per-task-id counters
· template field headings · agent contracts (budget, model, forbidden block,
leaf clause) · init scaffold command detection · context-map headings and the
80-line cap · staleness detection in **both** directions · metrics schema with
derived fields · and that `Agent(` appears in no agent file except the
orchestrator's.

The fixture is a small TypeScript package with a seeded off-by-one bug and a
toggleable stub test. The harness restores it on exit.

---

## Requirements

Claude Code · `git` · `node` · `bash`. Projects are assumed to be Node/TypeScript
with `vitest` (never jest) — the gate degrades gracefully elsewhere but the
guardrails are written for that stack.

## Status

Built and verified check-by-check. **A full end-to-end FULL run has not been
exercised** — every component is tested in isolation, but the orchestrator's
complete sequence is still unproven. Start with FAST tasks.

Nested subagent spawning is unverified in this harness; the star topology means
it doesn't matter.
