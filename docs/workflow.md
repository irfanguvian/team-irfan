# How team-irfan works

A visual walkthrough of the graph: how a task is triaged, who runs, where state
lives, and where you are asked to decide.

Every diagram below renders on GitHub. If you are reading this in a terminal,
the tables and the ASCII pipeline in the [README](../README.md#the-full-pipeline)
carry the same information.

---

## 1. Triage — one command, four outcomes

The router is the only node that decides what happens. It reads, it does not
write, and it prints the route before doing anything else. First match wins.

```mermaid
flowchart TD
    T["/team-irfan &lt;task&gt;"] --> R{"Router<br/>first match wins"}

    R -->|"under ~5 min by hand,<br/>or too ambiguous to triage"| HB["HAND-BACK<br/><i>one line, then stop</i>"]
    R -->|"asks something<br/>rather than changing something"| Q["QUESTION<br/><i>answered directly, zero agents</i>"]
    R -->|"≤2 files · known pattern ·<br/>no schema or contract change"| F["FAST<br/><i>solo executor → gate → report</i><br/>≤15 calls"]
    R -->|"everything else"| FU["FULL<br/><i>the pipeline in §2</i><br/>≤60 calls"]

    HB --> M["metrics.json"]
    Q --> M
    F --> M
    FU --> M

    style HB fill:#2d3748,color:#fff
    style Q fill:#2d3748,color:#fff
    style F fill:#2c5282,color:#fff
    style FU fill:#742a2a,color:#fff
```

**Tiebreaks are deliberately asymmetric.** Unsure between FAST and FULL → FULL,
because a wrongly-FAST task skips the human scope gate. Unsure between HAND-BACK
and FAST → HAND-BACK, because your five minutes beat fifteen tool calls.

**HAND-BACK and QUESTION still write `metrics.json`.** A route that did not run
is the one the evaluation node most needs to see: a hand-back rate near zero
means the router is not handing back, and that failure is invisible because
every run still looks successful.

---

## 2. The FULL pipeline

Topology is a **star, not a chain**. The orchestrator runs in the main thread and
is the only context with a channel to you. Every other node is a leaf: one
artifact in, one artifact out, spawns nothing.

That is not a style choice. This pipeline has three hard human gates, and a
subagent cannot stop and ask — a gate held by a leaf silently degrades into an
assumption with a checkbox.

```mermaid
flowchart TD
    subgraph ORCH["ORCHESTRATOR · main thread"]
        direction TB
        S1["1 · open run<br/>goal branch, .tg-active, baseline gate"]
        S2["2 · PM"]
        G1{{"⏸ YOU ANSWER<br/>open questions"}}
        S3["3 · PjM"]
        G2{{"⏸ YOU APPROVE SCOPE<br/>silence is not approval"}}
        S3B["3b · context maps<br/>init per unmapped folder"]
        S4["4 · worktrees<br/>one per task, never shared"]
        S5["5 · executors ×N<br/>independent ones concurrent"]
        S6["6 · tester per task"]
        S7["7 · merge<br/>one commit per task"]
        S8["8 · lead reviews merged diff"]
        G3{{"⏸ YOU SIGN OFF<br/>breaking change = blocker"}}
        S9["9 · ship block + metrics + retro"]
    end

    S1 --> S2 --> G1 --> S3 --> G2 --> S3B --> S4 --> S5 --> S6 --> S7 --> S8 --> G3 --> S9

    S2 -.-> A1["brief.md"]
    S3 -.-> A2["tasks.md<br/>task-&lt;id&gt;.md"]
    S3B -.-> A3[".team-irfan/context/&lt;slug&gt;.md"]
    S5 -.-> A4["change-summary-&lt;id&gt;.md<br/>+ GATE PASS"]
    S6 -.-> A5["test-report-&lt;id&gt;.md"]
    S7 -.-> A6["docs/REGISTRY.md entry"]
    S8 -.-> A7["report.md"]
    S9 -.-> A8["docs/handoff/&lt;date&gt;-&lt;slug&gt;.md<br/>metrics.json · lessons.md"]

    style G1 fill:#744210,color:#fff
    style G2 fill:#744210,color:#fff
    style G3 fill:#744210,color:#fff
```

### Who owns what

| | orchestrator | leaf nodes |
|---|---|---|
| talks to you | ✅ every gate | ❌ no channel exists |
| git operations | ✅ branch, worktree, merge, commit | ❌ except commits inside their own worktree |
| spawns agents | ✅ the only one | ❌ never |
| budget ledger | ✅ owns it | reports its own usage |
| decides scope | ❌ asks you | PjM proposes, you approve |

---

## 3. Where state lives

**No agent remembers anything.** Kill any node mid-run and the next one picks up
from disk. This is what makes the star topology survivable.

```mermaid
flowchart LR
    subgraph RUN["runs/&lt;yyyymmdd-slug&gt;/ · one run"]
        B["brief.md<br/><i>business rules + sources</i>"]
        TK["tasks.md · task-&lt;id&gt;.md<br/><i>the contract per executor</i>"]
        CS["change-summary-&lt;id&gt;.md<br/><i>what changed + gate output</i>"]
        TR["test-report-&lt;id&gt;.md<br/><i>PASS / FAIL / ESCALATE</i>"]
        RP["report.md · lessons.md"]
        MT["metrics.json<br/><i>the only source of counts</i>"]
    end

    subgraph PROJ["the project repo · survives the run"]
        CM[".team-irfan/context/&lt;slug&gt;.md<br/><i>per-folder map, gitignored</i>"]
        RG["docs/REGISTRY.md<br/><i>searchable context database</i>"]
        HO["docs/handoff/&lt;date&gt;-&lt;slug&gt;.md<br/><i>what landed, how to test, proof</i>"]
    end

    B --> TK --> CS --> TR --> RP --> MT
    TK -.reads.-> CM
    CS -.writes.-> RG
    RP --> HO
    MT -.->|"/team-irfan-evaluation"| EV["prompt diffs<br/><i>one at a time, your y</i>"]
```

`metrics.json` is command-written and structured. `report.md` and `lessons.md`
are prose written by nodes. **The evaluation node takes counts only from
`metrics.json`** — a number that came from a sentence is not a number.

---

## 4. Context loading — why repeat runs are cheap

Agents read **context maps, not folders**. The map is generated once per folder
and then validated with one `git diff` per run.

```mermaid
flowchart TD
    ST["node needs a folder"] --> HM{"map exists?<br/>.team-irfan/context/&lt;slug&gt;.md"}
    HM -->|no| GEN["orchestrator spawns init<br/><i>a leaf cannot do this itself</i>"]
    GEN --> HM
    HM -->|yes| FR["git diff --name-only &lt;last_commit&gt; -- &lt;folder&gt;"]
    FR -->|"empty"| TRUST["trust the map<br/><b>do not re-read the folder</b>"]
    FR -->|"non-empty"| RR["re-read only the files it named<br/>≤10 calls, then bump last_commit"]
    TRUST --> WORK["work"]
    RR --> WORK

    style TRUST fill:#22543d,color:#fff
    style GEN fill:#2c5282,color:#fff
```

**Map generation belongs to the orchestrator, not the node that noticed.** Every
node is a leaf and cannot spawn `init`; a map left to "whoever touches it first"
is a map that never gets written. A run whose `metrics.json` reads
`context_maps_used: none` did exactly that, and paid for it by re-reading every
folder cold in every node.

Reading outside the in-scope folders is a forbidden action. The escape hatch is
`docs/REGISTRY.md`, grepped by `FEAT:` / `MOD:` tag — never `cat`.

---

## 5. Failure handling — bounded, never a loop

```mermaid
stateDiagram-v2
    [*] --> Attempt1
    Attempt1 --> Merged: tester PASS
    Attempt1 --> Attempt2: FAIL + BUG block
    Attempt2 --> Merged: tester PASS
    Attempt2 --> Escalate: FAIL again
    Escalate --> [*]: orchestrator hands it to you<br/>re-scope or drop
    Merged --> [*]

    note right of Escalate
        Attempt 3 does not exist.
        Two retries on one root cause
        means the failure block was
        not actionable — that is
        recorded, not retried.
    end note
```

The same bound applies to the Lead's review: **max 2 rounds**, then it writes the
handoff and stops. That cap wins over any "keep iterating" instruction.

The retry counter is a hook (`hooks/retry-guard.sh`), not a prompt — a node
cannot talk its way past it.

---

## 6. The budget model

Tool calls, not tokens, not minutes. The orchestrator keeps the ledger.

| tasks | projected calls | verdict |
|---|---|---|
| 1 | ~47 | fits under the 60 cap |
| 2 | ~74 | over — PjM says so in the SCOPE block |
| 3+ | ~100+ | mis-scoped, or you raise the cap. Your call, not the graph's |

Projection is roughly `20 + 27 × tasks`. Each task costs a worktree, an
executor, a tester and a merge — so **more tasks is more fixed overhead, not more
parallelism**. Splitting is for work that genuinely cannot share a file, never
for work that merely can be described in more sentences.

At 60, the orchestrator stops and writes a partial report rather than overrunning
silently. Per-node budgets are ceilings, not allowances; they deliberately do not
sum to 60.

**Wall clock is measured, not capped.** Executors stamp start and end and report
elapsed minutes; over 15 they must say why. There is no hard abort — an agent
cannot watch a clock while a tool call is in flight, and a prompt that claims to
enforce a timeout is theatre.

---

## 7. What reaches you

```mermaid
flowchart LR
    N["each node returns"] --> P["[3/10] pjm done · 5 tasks · budget 12/60"]
    P --> N
    N --> FIN["run ends"]
    FIN --> SB["ship block · chat + docs/handoff/"]
    SB --> D["What landed · How to run · How to test<br/>Proof (pasted gate output) · Not done · Verdict"]

    style SB fill:#22543d,color:#fff
```

One progress line per node, one ship block at the end. The ship block's test
command is the literal string you can paste, and **Proof** is pasted `gate.sh`
output, never a summary of it. A run that ends with commits appearing and nothing
said is a run you have to audit out of git — which costs you more than the run
saved.

---

## 8. Rigid vs probabilistic

A deterministic check is never handed to a prompt. A prompt never replaces a
deterministic check.

```mermaid
flowchart TB
    subgraph RIGID["Rigid · hooks, zero LLM"]
        R1["typecheck · unit tests · coverage diff"]
        R2["stub-test detection with file:line"]
        R3["retry limit · escalation"]
        R4["worktree isolation"]
        R5["package manager + command detection"]
    end
    subgraph PROB["Probabilistic · prompts"]
        P1["problem solving"]
        P2["test-case design"]
        P3["convention extraction"]
        P4["documentation"]
        P5["retro feedback"]
    end

    style RIGID fill:#1a365d,color:#fff
    style PROB fill:#44337a,color:#fff
```

This is why `/team-irfan init` is split in two: `hooks/init-scaffold.sh` detects
the package manager and copies the commands verbatim from `package.json` — facts
in a file — and the agent fills only Purpose, Key files, and Conventions, which
need reading code.

---

## 9. Safety boundary

```mermaid
flowchart LR
    W["team-irfan"] -->|"terminus"| MC["local commit"]
    MC -.->|"you"| PU["git push"]
    PU -.->|"you"| CI["CI"]
    CI -.->|"you"| DP["deploy"]

    style MC fill:#22543d,color:#fff
    style PU fill:#744210,color:#fff
    style CI fill:#744210,color:#fff
    style DP fill:#744210,color:#fff
```

Every node carries an identical forbidden-actions block: no push, no deploy, no
CI trigger or bypass, no reading or writing `.env*` or secrets, no destructive
migration, no publish, no editing outside declared scope.

**A green `gate.sh` is a local signal, not permission to skip CI.** CI stays the
final gate.

---

## See also

- [README](../README.md) — install, usage, the efficiency contract
- [`agents/`](../agents/) — the prompt files themselves; each one is the contract for that node
- [`skills/guardrails/SKILL.md`](../skills/guardrails/SKILL.md) — the engineering rules every node obeys
- [`docs/evaluations/`](evaluations/) — what past runs measured, and what was changed because of it
- [CHANGELOG](../CHANGELOG.md) — what changed in each version of this workflow
