# How team-irfan works

A visual walkthrough of the graph: how a task is triaged, who runs, where state
lives, and where you are asked to decide.

Every diagram below renders on GitHub. If you are reading this in a terminal,
the tables and the ASCII pipeline in the [README](../README.md#the-full-pipeline--7-steps-one-human-gate)
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

## 2. The FULL pipeline — 7 steps, one human gate

Topology is a **star, not a chain**. The orchestrator runs in the main thread and
is the only context with a channel to you. Every other node is a leaf: one
artifact in, one artifact out, spawns nothing.

That is not a style choice. This pipeline has exactly ONE hard human gate — the
plan approval — and a subagent cannot stop and ask; a gate held by a leaf
silently degrades into an assumption with a checkbox.

```mermaid
flowchart TD
    subgraph ORCH["ORCHESTRATOR · main thread"]
        direction TB
        S0["open run<br/>goal branch, .tg-active, baseline gate"]
        MEM1["memory.sh retrieve --agent product<br/><i>## MEMORY block into the prompt</i>"]
        S1A["1 · PRODUCT — plan.draft.md + plan.json<br/>rules·SCOPE·PHASES·task blocks<br/>run_cap = min(round(calls×1.3), 60)"]
        S1B["1 · PRODUCT-CHALLENGER<br/>challenge.md · ACCEPT / REVISE<br/><i>user gave a path → verify only</i>"]
        S1C["1 · Product revision (max 1)<br/>→ plan.md, each item addressed or rejected"]
        PG["plan-gate.sh + plan-check.sh<br/><i>schema · run_cap · PHASES recomputed<br/>26 + 27×tasks, over cap ⇒ bounced</i>"]
        G1{{"⏸ YOU APPROVE THE PLAN<br/>the only gate · silence is not approval<br/>multi-phase ⇒ phase 1 only runs"}}
        S2A["2 · worktrees + executors ×N<br/>own Task block each · rule A +<br/>breaking-change checklist"]
        S2B["2 · QA — test cases from plan.json<br/><b>blind to every diff and worktree</b>"]
        S2C["2 · QA-CHALLENGER — challenge-qa.md<br/>coverage + compat cases, BEFORE execution"]
        S3["3 · QA runs per finished task<br/>+ FULL regression manifest —<br/>any manifest failure = compat break"]
        S4["4 · fix loop — same executor, same worktree<br/>max 2 retries, 3rd ⇒ BLOCKED, run stops"]
        MEM2["memory.sh retrieve --agent lead"]
        S5["5 · merge (one commit per task)<br/>then Lead review — machine gate<br/>then LEAD-CHALLENGER, blind re-review<br/>verdict disagreement ⇒ blocker"]
        S6["6 · summary + retro — printed + handoffs/<br/>manifest append · memory.sh compact<br/>multi-phase ⇒ NEXT PHASE: &lt;goal&gt;"]
        S7["7 · end — nothing else runs"]
    end

    S0 --> MEM1 --> S1A --> S1B --> S1C --> PG --> G1
    G1 --> S2A --> S3
    G1 --> S2B --> S2C --> S3
    S3 --> S4 --> MEM2 --> S5 --> S6 --> S7
    S6 -. "next phase = a fresh run<br/>own ledger, own gate, own approval" .-> S0

    S1A -.-> A3["plan.draft.md · plan.json"]
    S1B -.-> A9["challenge.md"]
    S1C -.-> A10["plan.md"]
    S2A -.-> A4["change-summary-&lt;id&gt;.md<br/>+ GATE PASS"]
    S2B -.-> A5["test-cases.md"]
    S2C -.-> A11["challenge-qa.md"]
    S3 -.-> A6["test-report-&lt;id&gt;.md"]
    S5 -.-> A7["report.md · challenge-lead.md<br/>docs/REGISTRY.md entry"]
    S6 -.-> A8[".team-irfan/handoffs/&lt;date&gt;-&lt;slug&gt;.md<br/>metrics.json"]
    A10 -. "SubagentStop ingest" .-> DB[("​.team-irfan/memory/<br/>product.db · lead.db")]
    A7 -. "SubagentStop ingest" .-> DB
    A8 -. "Stop ingest (ship block)" .-> DB
    DB -. "BM25 top-12" .-> MEM1
    DB -. "BM25 top-12" .-> MEM2

    style G1 fill:#744210,color:#fff
    style PG fill:#1a365d,color:#fff
    style S1B fill:#44337a,color:#fff
    style S2C fill:#44337a,color:#fff
    style S4 fill:#742a2a,color:#fff
    style S5 fill:#22543d,color:#fff
    style DB fill:#1a365d,color:#fff
```

### Who owns what

| | orchestrator | leaf nodes |
|---|---|---|
| talks to you | ✅ the plan gate | ❌ no channel exists |
| git operations | ✅ branch, worktree, merge, commit | ❌ except commits inside their own worktree |
| spawns agents | ✅ the only one | ❌ never |
| budget ledger | ✅ reads it (hook writes it) | counted by the hook |
| decides scope | ❌ asks you | Product proposes, challenger contests, plan-gate + plan-check verify, you approve |
| ships | ❌ | Lead's review verdict is the ship gate — PASS or BLOCKED |

---

## 3. Where state lives

**No agent remembers anything.** Kill any node mid-run and the next one picks up
from disk. This is what makes the star topology survivable.

```mermaid
flowchart LR
    subgraph RUN["runs/&lt;yyyymmdd-slug&gt;/ · one run"]
        B["plan.draft.md · challenge.md<br/>plan.md · plan.json<br/><i>the approved contract</i>"]
        TK["plan.md task blocks · test-cases.md<br/><i>the contract per executor, cases from the plan</i>"]
        CS["change-summary-&lt;id&gt;.md<br/><i>what changed + gate output</i>"]
        TR["test-report-&lt;id&gt;.md<br/><i>PASS / FAIL / ESCALATE</i>"]
        RP["report.md<br/><i>Lead review — PASS | BLOCKED</i>"]
        MT["metrics.json<br/><i>the only source of counts</i>"]
    end

    subgraph PROJ["the project repo · survives the run"]
        CM[".team-irfan/context/&lt;slug&gt;.md<br/><i>per-folder map, gitignored</i>"]
        RG["docs/REGISTRY.md<br/><i>searchable context database</i>"]
        HO["docs/handoff/&lt;date&gt;-&lt;slug&gt;.md<br/><i>what landed, how to test, proof</i>"]
        MEMD[".team-irfan/memory/<br/><i>product.db · lead.db · memory.log<br/>deterministic, never blocking</i>"]
        QAD[".team-irfan/qa/<br/><i>regression.manifest — the suite only grows</i>"]
    end

    B --> TK --> CS --> TR --> RP --> MT
    TK -.reads.-> CM
    CS -.writes.-> RG
    RP --> HO
    MT -.->|"/team-irfan-evaluation"| EV["prompt diffs<br/><i>one at a time, your y</i>"]
```

`metrics.json` is command-written and structured. `report.md` and the summary
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
    Attempt1 --> Merged: QA PASS
    Attempt1 --> Attempt2: FAIL + BUG block
    Attempt2 --> Merged: QA PASS
    Attempt2 --> Escalate: FAIL again
    Escalate --> [*]: run STOPS · BLOCKED written to blocked.log<br/>failing cases + evidence into the summary
    Merged --> [*]

    note right of Escalate
        Attempt 3 does not exist.
        retry-guard.sh writes the
        BLOCKED verdict itself — a
        killed run still shows why
        it stopped. No "continue?"
        loop, no silent retries.
    end note
```

The same bound applies to Lead's review: **max 2 rounds**, then verdict BLOCKED
and the run stops. That cap wins over any "keep iterating" instruction.

The retry counter is a hook (`hooks/retry-guard.sh`), not a prompt — a node
cannot talk its way past it.

---

## 6. The budget model

Tool calls, not tokens, not minutes. The hook keeps the ledger; the
orchestrator reads it.

- **Until the plan is approved:** the static cap, 60.
- **From approval:** the plan's own `run_cap = min(round(chosen option's
  expected_calls × 1.3), 60)` — computed by Product, verified by `plan-gate.sh` (and `plan-check.sh` recomputing every phase projection, 26 + 27×tasks),
  read by `ledger.sh cap <run>` (fallback 60 when plan.json is absent).

The projection is in the plan itself — each option carries `expected_calls` —
so the cap is set with the number visible at the gate, not discovered at call
150. Before EVERY spawn: `ledger.sh read` vs `ledger.sh cap`; at or over, the
run stops with a partial summary. The cap moves only on an explicit number
from you (`cap-raised:<n>`).

**Wall clock is measured, not capped.** Executors stamp start and end and report
elapsed minutes; over 15 they must say why. There is no hard abort — an agent
cannot watch a clock while a tool call is in flight, and a prompt that claims to
enforce a timeout is theatre.

---

## 7. What reaches you

```mermaid
flowchart LR
    N["each node returns"] --> P["[1/7] product done · 2 tasks · budget 12/39"]
    P --> N
    N --> FIN["run ends"]
    FIN --> SB["summary · chat + .team-irfan/handoffs/"]
    SB --> D["what the team did · diff --stat (pasted)<br/>test cases pass/fail · how to test (paste-able)<br/>breaking changes · lessons ≤3 lines · verdict"]

    style SB fill:#22543d,color:#fff
```

Two moments of contact: the plan (printed in full, then one approval question
with no plan content) and the summary at the end. One progress line per node in
between. The summary's test commands are literal paste-able strings, and the
diff --stat is pasted, never summarised. After the summary the session ends —
step 7 is END, nothing else runs.

---

## 8. Rigid vs probabilistic

A deterministic check is never handed to a prompt. A prompt never replaces a
deterministic check.

```mermaid
flowchart TB
    subgraph RIGID["Rigid · hooks, zero LLM"]
        R1["typecheck · unit tests · coverage diff"]
        R2["stub-test detection with file:line<br/>assertion-free test-case scan"]
        R3["plan-gate.sh schema + run_cap arithmetic"]
        R3b["retry limit · BLOCKED on the 3rd attempt"]
        R4["worktree isolation"]
        R5["package manager + command detection"]
    end
    subgraph PROB["Probabilistic · prompts"]
        P1["problem solving"]
        P2["option generation · test-case design"]
        P3["convention extraction"]
        P4["documentation"]
        P5["lessons in the summary"]
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
