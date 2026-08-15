# Team Graph

Stateless agents, artifact state, human gates.

Each agent = **system prompt** (its role file in `agents/`) + **prompt** (the
input artifact) + **context** (that artifact and its own worktree, nothing
else) + **settings** (rigid hooks, probabilistic prompts).

All state lives in `runs/<yyyymmdd-slug>/`. No agent remembers anything. Kill
any node mid-run and the next one picks up from the files.

Invoke: `/team-irfan <task>`

---

## Flow

```
/team-irfan "<task>"
        │
        ▼
   ┌─────────┐
   │ ROUTER  │  triage only, never edits
   └────┬────┘
        │
        ├── HAND-BACK ── "faster manually: <reason>"  ── STOP
        │
        ├── QUESTION ─── answer inline, 0 agents, 0 artifacts
        │
        ├── FAST ──────► SOLO EXECUTOR ─► gate.sh ─► report (4Q)   [≤15 calls]
        │                (current tree, no worktree, no commit)
        │
        └── FULL                                                   [≤60 calls]
              │
              ▼
        ┌──────────┐
        │    PM    │  brief.md
        └────┬─────┘  verifies business logic WITH IRFAN
             │        never invents a stakeholder answer
             ▼
        ┌──────────┐
        │   PjM    │  tasks.md + task-spec.md per task
        └────┬─────┘
             │
        ⏸ ── IRFAN APPROVES SCOPE ── ⏸
             │
             ▼
        ┌──────────┐
        │   LEAD   │  spawns N executors from the breakdown
        └────┬─────┘  N = what the work needs. backend-only ⇒ 0 FE agents
             │        git worktree add ../tg-<slug>-<id>   (one each)
             │
             ├──► EXEC 1 ─► change-summary.md ─► gate.sh
             ├──► EXEC 2 ─► change-summary.md ─► gate.sh
             └──► EXEC n ─► change-summary.md ─► gate.sh
                              │
                              ▼
                        ┌──────────┐
                        │  TESTER  │  test-report.md, E2E, real evidence
                        └────┬─────┘  runs the exact commands from
                             │        change-summary.md "How to verify"
                 FAIL ───────┤
                             │  back to the SAME executor + the failure block
                             │  retry-guard.sh: max 2 retries
                             │  3rd attempt ─► ESCALATE ─► Lead ─► Irfan
                             │
                 PASS ───────▼
                        ┌──────────┐
                        │   LEAD   │  merge worktrees + code review
                        └────┬─────┘  final merge = ONE commit
                             │        git worktree remove after merge
                             ▼
                        report.md (4 questions + Verdict)
                             │
                        ⏸ ── IRFAN SIGNS OFF ── ⏸
                             │
                             ▼
                        ┌──────────┐
                        │  RETRO   │  runs/<id>/lessons.md
                        └──────────┘  shows it to Irfan.
                                      NEVER edits CLAUDE.md or any skill.
```

---

## Rigid vs probabilistic

**Rigid — hooks, zero LLM, exit codes only:**

| Check | Where |
|---|---|
| typecheck | `hooks/gate.sh` |
| unit tests | `hooks/gate.sh` |
| coverage diff | `hooks/gate.sh` |
| stub-test detection | `hooks/gate.sh` |
| retry limit | `hooks/retry-guard.sh` |
| worktree isolation | Lead, one worktree per executor |
| gate enforced on subagent exit | `hooks/subagent-gate.sh` via `SubagentStop` |

`subagent-gate.sh` is registered in `~/.claude/settings.json` under
`SubagentStop`. It is inert unless a `.tg-active` marker file sits in the cwd —
Lead creates it when a FULL run opens and removes it after sign-off. No marker,
no effect: every other workflow on this machine is untouched. When it is armed
and the gate fails, it exits 2, which blocks the subagent from reporting done
and feeds it the failure. `stop_hook_active` short-circuits the second block so
a subagent can never be trapped in a loop.

**Probabilistic — prompts, judged not measured:**

problem solving · test-case design · documentation · retro feedback

A deterministic check is never handed to a prompt. A prompt never replaces a
deterministic check.

---

## Efficiency contract

Permanent. Every node inherits it.

- **Fast path: ≤15 tool calls.** Full path: **≤60 per feature**, everyone's
  calls included. Lead keeps the ledger in `tasks.md` and stops at 60 — a
  partial `report.md` with the rest in Blockers, never a silent overrun.
- **Per-node budgets are ceilings, not allowances**, and they deliberately do
  not sum to 60:

  | router | pm | pjm | lead | executor | tester | retro |
  |---|---|---|---|---|---|---|
  | 4 | 10 | 8 | 20 | 15 ×task ×attempt | 12 ×task ×attempt | 5 |

  A 2-task feature at every ceiling would spend ~100. No run may spend every
  ceiling. Roughly `20 + 27×tasks` is the realistic projection — over 60 means
  Lead asks Irfan to raise the cap or cut scope **before** the first worktree,
  not after.
- **Router must HAND-BACK when manual is faster.** Under ~5 minutes of human
  work, or too ambiguous to triage — one line, then stop. Running the graph on
  a typo is the most expensive failure mode there is.
- **Reports are always the four questions** — Done / Fine or not / Blockers /
  Next — plus a Verdict line. Short, human-readable, no machine jargon.
- **Agents never read whole trees.** Grep `docs/REGISTRY.md` (`head -40`, then
  `grep -n "FEAT:"`, then `sed -n` the hits — never `cat`), then targeted files
  only. A registry entry that answers the question means the code it describes
  does not get re-read.
- **Retry limit 2, then escalate.** No silent loops, ever.
- **Human gates are hard stops:** PjM scope approval, ship sign-off. A node
  that passes one on its own has failed.

---

## Modes

| Mode | Where | What it does |
|---|---|---|
| **Caveman** | every node's prose, all documentation, every verdict | terse output — fragments, no preamble, no tool-call narration. Technical terms, code, and error strings stay verbatim. Warnings and irreversible-action confirmations drop out of caveman for clarity. |
| **Ponytail** | executors only (solo + full) | the laziest solution that actually works. Ladder: does it need to exist → already in this codebase → stdlib → native → installed dependency → one line → minimum code. Runs *after* understanding, never instead of it. Shortcuts get a `ponytail:` comment naming the ceiling and the upgrade path. |

Ponytail is on executors because that is where the same pattern keeps getting
re-implemented. It is deliberately **not** on PM, PjM, Tester, or Lead review —
laziness in requirements or verification is just a gap.

---

## Skills each node may load

Curated. Loading a skill costs calls, so no node loads one it does not need.

| Node | Skill | When |
|---|---|---|
| all | `team-graph/skills/guardrails/SKILL.md` | always — read it first |
| PM | `oh-my-claudecode:deep-interview` | only when requirements are genuinely ambiguous and Irfan is available |
| Executor · Solo | `chrome-devtools-axi` | any UI change — mandatory, a visual change without a browser check is unverified |
| Executor · Solo | `claude-api` | change touches Claude/Anthropic model ids, pricing, tokens, caching, SDK. Read before opening the file, never answer from memory |
| Executor · Solo | `graphify` | **only if** `graphify-out/graph.json` already exists — `graphify query "<q>" --budget 2000` instead of reading files. Never build an index mid-task |
| Tester | `chrome-devtools-axi` | browser E2E |
| Tester | `run` | launching the project's app to test against |
| Lead review | `code-review` | correctness pass on the merged diff |
| Lead review | `security-review` | any auth, input, query, or secret surface |
| Lead review | `audit-checklist` | review passes only — catches what the review missed |
| Lead git | `gh-axi` | every GitHub operation, before raw `gh` |

**Deliberately excluded:** `/team`, `/autopilot`, `/ralph`, `/ultrawork`,
`/ultraqa` — competing orchestrators with different retry policies. Team-graph
runs its own nodes. Also excluded: `dataviz`, `artifact-*`, `figma-axi`,
`lavish`, `simplify` — out of scope for this graph.

**RTK is deliberately kept out of `gate.sh`.** Measured, not assumed:

```
$ rtk test bash -c 'exit 1'   ; echo $?   →  0     # child failure swallowed
$ rtk err  bash -c 'exit 3'   ; echo $?   →  3     # remapped, not passed through
```

A gate that trusts `rtk test` reports green on red. `gate.sh` calls
`tsc`/`vitest`/`jest` raw and caps its own output at 40 lines instead. The
global PreToolUse hook passes `bash gate.sh` through unchanged (`rtk rewrite`
returns 1 = no equivalent), so the gate is never rewritten out from under
itself.

The trap that remains is on **agents**: a bare `npx vitest run` typed by a node
gets rewritten to `rtk vitest run` and can look green while red. Every executor
and tester prompt says so. `gate.sh` output is the only test evidence any node
may report.

---

## Layout

```
~/.claude/team-graph/
  agents/     router.md solo-executor.md pm.md pjm.md lead.md executor.md
              tester.md retro.md
  hooks/      gate.sh retry-guard.sh subagent-gate.sh
  skills/     guardrails/SKILL.md
  templates/  brief.md task-spec.md change-summary.md test-report.md report.md lessons.md
  runs/       runs/<yyyymmdd-slug>/  ← all state for one run
  tests/      fixture/ run-checks.sh cases.md
  README.md
```

A run directory holds: `brief.md`, `tasks.md`, `task-<id>.md`,
`change-summary-<id>.md`, `test-report-<id>.md`, `coverage-base.txt`,
`retries.json`, `report.md`, `lessons.md`.

---

## Boundaries

Team-graph owns `~/.claude/team-graph/` and the file
`~/.claude/commands/team-irfan.md`. It touches nothing else. No node edits
`CLAUDE.md`, `FUNDAMENTALS.md`, `settings.json`, or anything under
`~/.claude/plugins/`.
