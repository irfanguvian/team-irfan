# 2026-08-21 — harness v4, sonnet-low tier (first hardened run)

First matrix on the hardened v4 bench (plugin 3.1.3, sha `3903144`, model
`claude-sonnet-5`, effort low, judge `claude-opus-5`, 3 lanes, unattended
start-to-report in 43 min, $22.29 + judge). Published:
`benchmarks/harness-v4/results/sonnet-low/REPORT-20260821.md`.

## Validity

| arm | valid | infra | total |
|---|---|---|---|
| bare | 15 | 0 | 15 |
| omc | 15 | 0 | 15 |
| team | 13 | 2 | 15 |

Infra: N5/team r1+r2, reason=budget ($3 cell cap, killed at 223 s/244 s).
The bench itself ran clean — preflight, sentinel, heartbeat, watcher kill,
crash-free lanes, auto score→judge→report, zero polling.

## Verdicts (valid cells only)

| claim | verdict | one line |
|---|---|---|
| C1 verify-driven reliability | HOLDS | false_done 0% everywhere — checks redundant at this tier (honesty note applies) |
| C2 plan-then-execute | INSUFFICIENT DATA | both team N5 cells infra; no FULL-route plan ever measured |
| C3 predictable effort | INSUFFICIENT DATA | same — predicted_calls only exists on FULL |
| C4 memory | HOLDS | team B cheaper (0.64 vs 0.73) AND faster to locate (4.5 vs 5.0); same_hole clean both rounds |
| C5 generated quality | **FALSIFIED** | team loses pairwise majority: F1 (3L), MEM-A (2L), MEM-B (1L); B1 all ties |

Honest line: **team-irfan lost C5 on valid cells.** Not on minimality — in 3
of 6 losing pairs team's diff was smaller — on substance: compat breaks and a
missing index that guardrails explicitly forbids, from a rulebook that never
entered context.

## Root causes (direct run review, valid at any n)

1. **Guardrails never load in the FAST lane — 0 of 7 team runs read
   `skills/guardrails/SKILL.md`.** 5/7 runs the orchestrator edits inline (0
   spawns), so neither `solo-executor.md` (the only file that says "read
   guardrails") nor the rulebook itself is in context. Every FAST diff is base
   model instinct + one improvised why-line. The two losing hunk types are
   exactly the two rules in the unread file: contract preservation
   (guardrails §182-187 — F1 lost 3 pairs: global ValidationPipe blast
   radius, dropped `@HttpCode(200)`, replaced `{ok:false,errors}` body with
   the Nest envelope) and mandatory index check (§133 — MEM lost 3 pairs:
   N+1 collapsed to one query on an unindexed `customerId IN (...) ORDER BY
   occurredAt`; MEM-B r2 diff byte-identical to omc's except the missing
   `@@index([customerId, occurredAt])`).
2. **Opus leak burned the N5 budget, not FULL-route cost.** 7 of 11 agent
   frontmatters pin `model: opus`; the lead ALSO passes `model:opus` in Task
   calls (overriding executor.md's own sonnet). Opus share of the killed
   cells: r1 39% ($1.23), r2 73% ($2.33) — on a tier pinned to sonnet. r2
   spent $2.33 on an opus product→challenger→revise round for a mechanical
   4-file N+1 (its plan invented a schema change, tripping the challenger).
   Leak-free FULL ≈ $3.5–4.5 on sonnet; $3 cap is under the floor either way.
3. **FAST spawn path violates its own contract when it does delegate.**
   F1/team/1: no `ROUTE:` printed before acting; handover pre-committed the
   executor to a hypothesis ("is ValidationPipe applied globally?"), executor
   obeyed literally → 4 files, out-of-scope app.module.ts edit, 100-line diff
   (solo-executor.md caps at 2 named files). n=1, but it breached existing
   written rules.

## Fix list for team-irfan

P0 (deterministic — implemented now, plugin 3.1.4; see CHANGELOG):
- **gate.sh contract guard**: fail when the diff removes an `@HttpCode(` or
  deletes an `ok: false` response literal without an `INTENTIONAL BREAKING:`
  line in the report. Covers F1's 3 losses.
- **gate.sh index guard**: fail when the diff adds a Prisma `in:`-filtered
  `where`/new `orderBy` while `schema.prisma` is untouched, unless the report
  carries `index checked:`. Covers MEM's 3 losses.
- **model-pin hook (bench sessions)**: under `TEAM_IRFAN_AUTO_APPROVE=1`, a
  PreToolUse hook rejects Task calls carrying a `model` param, and agent
  frontmatter no longer pins `model: opus` — nodes inherit the session model.
  Kills the opus leak on both paths (frontmatter + lead override).

P1 (deterministic, not yet implemented):
- PreToolUse guard: block first Edit/Write in a team session until
  guardrails/SKILL.md has been read (fixes root cause 1's mechanism, not just
  its two symptoms).
- Challenger round counter in the ledger: cap plan-phase spawns at 2; the
  3.1.2 "conditional challenger" rule is prose only and r2 sailed past it.
- Bench: extract.py/collect.sh must include `<sid>/subagents/*.jsonl`
  (team tool_calls/verified currently measured on the orchestrator transcript
  only); judge.sh must persist the judge's rationale JSON, not just the
  winner; prune stale `fix/*` branches from the fixture between cells;
  per-arm cell budget (team floor $6).

P2 (prompt — blocked below n=5 per cell, collect more n first):
- router.md handover template: "state symptom and file, never a hypothesis";
  ROUTE-print-before-acting ordering (enforce via check, don't rewrite prose
  at n=1).

## Rerun

After 3.1.4 lands (`claude plugin update team-irfan@team-irfan`):

```bash
cd ~/.claude/team-graph/benchmarks/harness-v4
BENCH_MODEL=claude-sonnet-5 BENCH_EFFORT=low CELL_BUDGET_USD=6 \
  bin/run.sh --matrix --tasks N5 --arms team --redo-infra=budget
```

Then a fresh full matrix on the same tier to measure the P0 gates' effect on
C5 (this redo only fills C2/C3's N5 hole). Haiku floor tier
(`BENCH_MODEL=claude-haiku-4-5-20251001 BENCH_EFFORT=low CELL_BUDGET_USD=1.5
bin/run.sh --matrix`) stays queued behind that decision.

Aggregate prompt/routing tuning stays blocked below n=5 per cell (v3 rule);
nothing here retunes prompts — P0s are gates and config.
