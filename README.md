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

**Probabilistic — prompts, judged not measured:**

problem solving · test-case design · documentation · retro feedback

A deterministic check is never handed to a prompt. A prompt never replaces a
deterministic check.

---

## Efficiency contract

Permanent. Every node inherits it.

- **Fast path: ≤15 tool calls.** Full path: **≤60 per feature.** Each node's
  own budget is written in its prompt frontmatter.
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

**RTK** is wired inside `gate.sh` (`rtk test`, `rtk err`) to keep gate output
small. Agents do not call it directly; the global PreToolUse hook already
rewrites their Bash calls.

---

## Layout

```
~/.claude/team-graph/
  agents/     router.md solo-executor.md pm.md pjm.md lead.md executor.md tester.md
  hooks/      gate.sh retry-guard.sh
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
