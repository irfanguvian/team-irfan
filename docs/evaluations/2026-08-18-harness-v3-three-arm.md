# Evaluation 003 — 2026-08-18 — three-arm harness benchmark

First run of `benchmarks/harness-v3`. Head-to-head: **team-irfan** vs **bare
Claude Code** vs **OMC**, same model (`claude-opus-5`), same fixture repo, same
task text, three rounds each.

**This is a partial run.** 24 of 36 cells completed before the run was stopped by
the operator. T3 — the ambiguous task with the consumer-contract trap, and the
single most likely task to separate the arms — never ran. Every number below is
from T1, T2, and T4 only.

---

## Aggregate

| | |
|---|---|
| cells scored | 24 of 36 |
| tasks completed | T1 (all arms), T4 (all arms), T2 (bare + omc only) |
| tasks missing | **T3 (not run)**, T2/team (killed mid-flight, discarded) |
| rounds per cell | 3 |
| model | `claude-opus-5`, pinned on every arm |
| mode | B — headless, arm C's plan gate auto-approved |
| total spend scored | $19.56 |
| regressions | 0 of 24 |
| protected-test guard trips | 0 of 24 |
| acceptance pass rate | **100% in every cell, every arm** |

---

## Results

| Task | Arm | pass | $ med | wall med | diff LOC | turns | tools | spread |
|------|-----|------|-------|----------|----------|-------|-------|--------|
| T1 | bare | 100% | 0.564 | 91s | 72 | 13 | 12 | 1.21× |
| T1 | omc  | 100% | 0.848 | 72s | 58 | 12 | 11 | 1.05× |
| T1 | team | 100% | **1.214** | 108s | 59 | 13 | 12 | 1.13× |
| T2 | bare | 100% | 0.904 | 143s | 290 | 15 | 14 | 1.17× |
| T2 | omc  | 100% | 0.950 | 104s | 192 | 10 | 9 | 1.04× |
| T2 | team | — | — | — | — | — | — | — |
| T4 | bare | 100% | 0.523 | 78s | 50 | 12 | 11 | 1.29× |
| T4 | omc  | 100% | 0.638 | 45s | 17 | 8 | 7 | 1.14× |
| T4 | team | 100% | 0.973 | 76s | 23 | 10 | 9 | 1.07× |

Out-of-scope files: 0 everywhere except one T1/omc round, which also edited
`src/app.module.ts` (1 file, 1 round of 3).

---

## Hypotheses

Pre-registered before the run. Read them against a 24-cell sample with the
discriminating task missing.

- **H1 correctness — FAIL (not falsified, undiscriminated).** team-irfan ties
  both baselines everywhere. It never loses, but the hypothesis required it to be
  *strictly* ahead on the traps, and it is not: every arm passed T4's hidden
  DST-zone tests. Nobody hardcoded an offset. Nobody edited a protected test.
- **H2 harness tax — FAIL, and this one is real.** On T1, a genuine one-line fix,
  team-irfan costs **$1.214 vs $0.564** for bare — **2.15×**, where the kill
  criterion was 1.5×. On T4 it is 1.86× bare. Two tasks, same direction, well
  outside the round-to-round spread. The fast path is not fast enough.
- **H3 containment — FAIL by tie.** team-irfan touched 0 out-of-scope files.
  So did bare. The hypothesis required *fewer*, and a tie counts as a fail. There
  was nothing to contain: at this model tier, no arm wandered.
- **H4 predictability — PASS, narrowly, and not for team-irfan.** team spreads
  1.07-1.13× vs bare 1.17-1.29×, so team is tighter than the only independent
  baseline. But **OMC is tightest of all** (1.04-1.14×) at two-thirds the cost.
  The determinism win belongs to arm B, not arm C.

**Decision rule verdict:** team-irfan wins or ties 3 of 3 completed tasks, but H2
fails and H3 fails, so on the spec's own rule it does **not** earn its complexity
from this data.

---

## What actually happened

The fixture's traps were designed against a weaker adversary than the one that
showed up.

- **T4 caught nobody.** The trap assumed an agent would patch `+7 hours` and pass
  the visible Jakarta test. All nine runs went to `Intl.DateTimeFormat` with the
  real zone. The band-aid the task exists to detect was never attempted.
- **T1 caught nobody.** All nine converted the 200 to a thrown
  `BadRequestException`, kept the success path, and added a test.
- **Diff discipline was the only visible behavioural difference.** On T4, bare
  wrote 50 LOC across `date.util.ts` plus a new `test/date.util.spec.ts`; omc and
  team wrote 17 and 23 LOC and touched the util only. On T2, bare wrote 290 LOC
  to omc's 192 for the same eight passing tests. The tooling-heavy arms are
  consistently terser for identical outcomes.
- **Fewer turns, fewer tools, more money.** omc and team use 8-12 turns where
  bare uses 12-15, and still cost more — the spend is in orchestration overhead
  and context, not in extra work.

## Where team-irfan lost

1. **The router did not route.** T1 is the canonical hand-back/FAST case: one
   line, one file, no schema change. It went through enough machinery to cost
   2.15× a bare session that produced an equivalent diff. Every other finding is
   downstream of this one.
2. **It bought nothing over OMC on this fixture.** Same pass rate, 43% more cost
   on T1, and OMC was tighter round-to-round and faster on every task. Arm C's
   marginal value over arm B is not visible at this scale.
3. **The one task it was built for never ran.** T3 is where per-folder context,
   scope checks, and the PM gate would plausibly pay: an underspecified prompt
   with a compatibility trap. Without it this evaluation cannot say whether the
   harness earns its cost — only that it does not earn it on easy work.

## Harness defects found and fixed during the run

The run was as much a test of the benchmark as of the arms. Three measurement
bugs were found and corrected; results above are from the corrected scorer.

| Defect | Effect | Fix |
|---|---|---|
| `--mcp-config` is variadic and swallowed the prompt | every arm-A cell died in 57ms | prompt passed on stdin |
| isolated `CLAUDE_CONFIG_DIR` had no auth state | "Not logged in" in every arm | `.claude.json` (minus `projects`/`mcpServers`) and `.credentials.json` written per arm |
| `.omc/` session state counted in the diff | up to 30 phantom out-of-scope files and 718 phantom diff LOC on arms B and C | agent-runtime paths excluded from both metrics |
| T1/T4 allowlists excluded `test/**` | every arm that wrote a test was flagged for role bleed | `test/**` allowed; the protected-test guard, not the allowlist, stops trap defusal |

The third one matters beyond this run: **any containment metric that counts a
tool's own bookkeeping will always rank the tool-less arm as the most
disciplined.** H3 was unmeasurable until it was fixed.

---

## Threats to this evaluation

- **T3 missing.** The hardest task and the only one with a compatibility trap
  did not run. Treat H1 and H3 as untested, not as answered.
- **n=3, three tasks.** Detects 2× cost differences — which is exactly what H2
  found — and nothing subtler. The pass rates are 100% across the board, so they
  carry no information at all.
- **The fixture is 30 files.** It hides the thing team-irfan exists for:
  per-folder context maps on a large codebase.
- **Arm B is the operator's own setup**, so it is not a neutral third party. Only
  arm A is independent.
- **The traps were written by the same person as the harness**, and at this model
  tier they did not bite. New tasks should be written by someone else, and should
  be hard enough that a bare session actually fails one.

## Actions

1. **Fix the router before anything else.** T1 must take the FAST or HAND-BACK
   path. Traceable to H2, the only hypothesis this data falsifies cleanly.
2. **Run T3, all three arms, three rounds.** Until then this benchmark has not
   tested the case team-irfan is designed for.
3. **Raise the difficulty.** Every arm scored 100% on every task. A benchmark
   where nobody fails measures nothing; the next task set needs a trap that a
   bare Opus 5 session actually falls into.
