# Registry

Context database for this project. Searched, not read whole.
Grep by tag: `FEAT:` `MOD:` `STATUS:` `DEC:`

## Index
| Feature | Modules | Latest | Status |
|---|---|---|---|
| bench-harness-v4 | benchmarks,hooks | R-0005 | shipped |
| harness-v3 benchmark | benchmarks/harness-v3, hooks | R-0001 | partial |

## Entries

### R-0005 · 2026-08-21 · [FEAT:bench-harness-v4] [MOD:benchmarks,hooks,agents,plugin] [STATUS:shipped] [DEC:yes]

**Input**
Phase 3+4 of harness-v4 plan: run sonnet-low matrix unattended, evaluate,
feed P0s back into team-irfan.

**Output**
- files: `benchmarks/harness-v4/results/sonnet-low/` (45 cells, REPORT-20260821.md), `docs/evaluations/2026-08-21-harness-v4-sonnet-low.md`, `hooks/{gate.sh,model-pin.sh}`, agents frontmatter de-pinned, plugin 3.1.4, run-checks §37. Commits 3903144(run sha)…42e6a45, 93d307d.
- change: 43 valid/2 infra (N5 team, budget $3 cap). C1 HOLDS · C2/C3 INSUFFICIENT DATA · C4 HOLDS · C5 FALSIFIED (6 pairwise losses). P0s shipped: gate contract+index guards, bench model pin (opus leak was 39–73% of killed cells).
- decision: budget-killed cells stay INFRA_FAIL, no retry (recorded rounds only); prompt tuning deferred below n=5 — only deterministic gates shipped.
- tests: run-checks 354/354 incl. §37; matrix ran start→report unattended in 43 min, $22.29.

**Verdict**
shipped — rerun N5 team with CELL_BUDGET_USD=6 --redo-infra=budget to fill C2/C3; fresh full sonnet matrix measures the new gates on C5; haiku floor queued after.

### R-0004 · 2026-08-21 · [FEAT:bench-harness-v4] [MOD:benchmarks,hooks,plugin] [STATUS:shipped] [DEC:yes]

**Input**
Harness v4: harden (preflight, pin, heartbeat, 3-state cells, deterministic
same-hole), never-stale supervision (run.sh --matrix, lanes, PROGRESS.md,
notify), then rerun on sonnet-low/haiku-low and feed back. Phases 1–2 only here.

**Output**
- files: `hooks/bench-sentinel.sh`, `hooks/headless-driver.sh` (heartbeat), plugin 3.1.3, `tests/run-checks.sh` §36; `benchmarks/harness-v4/bin/{lib,preflight,progress,notify,same-hole}.sh`, `run.sh --matrix`, `score.sh`/`report.py --tier`, `selftest/fake-claude`, `tasks/MEM-B/bandaid.markers`, `results/opus-legacy.infra.json`, SPEC ground rules + §7/§8, README. Commits a455ab1, 0f4e97d.
- change: cell validity from on-disk proof (sentinel/heartbeat/meta), INFRA_FAIL excluded from C1–C5, INSUFFICIENT DATA below SPEC n, per-tier results dirs, one-command unattended matrix with lanes/resume/--redo-infra/budget kill/notify. Legacy opus files byte-identical; `report.py --tier opus-legacy` → team 9 valid/6 infra, C1–C3 INSUFFICIENT DATA.
- decision: same-hole judged by grep markers (code edits under src/|prisma/ only) + retro_recorded from memory/handoff presence — LLM same-hole removed; lanes default = one per arm (rejected: strict sequential — proven slow, not safer).
- tests: `bin/selftest.sh` 37/37 (fake-claude, $0), `tests/run-checks.sh` 333/333, `bin/test_extract.py` 3/3; independent verifier PASS, code review REQUEST_CHANGES → 25 findings fixed + re-proved.

**Verdict**
shipped — Phase 3 (sonnet-low matrix, ~$25–45) not started: needs `claude plugin update` so installed SHA == HEAD, then `BENCH_MODEL=claude-sonnet-5 BENCH_EFFORT=low bin/run.sh --matrix`. Phase 4 eval follows the run.

### R-0003 · 2026-08-20 · [FEAT:bench-harness-v4] [MOD:benchmarks,plugin] [STATUS:partial] [DEC:yes]

**Input**
Run bin/run.sh all (v4 harness, opus, 45 cells), give the verdict; save report,
commit+push, make team-irfan load latest version next run.

**Output**
- files: `benchmarks/harness-v4/results/{results.csv,REPORT-20260820.md,judgments/}` (42 judgments); commits f9d0e52, 3e8e772 (merge feat/v3.0 → main, v3.1.2), 9370e29 — pushed.
- change: 45/45 cells ran+scored+judged. Q1/F1/B1 all arms 100%. Arm C FULL cells (N5, MEM ×4) INVALID: plugin `hook-load-failed` on main 3.0.0 (`plugin.json` manifest hooks ref duplicates auto-loaded hooks/hooks.json) → headless driver absent → runs died at plan gate.
- decision: reported as-is (operator choice) instead of rerunning the 6 cells; feat/v3.0 merged AFTER the run so next runs load 3.1.2 with the Stop-hook driver.
- tests: selftest 8/8, test_extract 3/3, judge calibration 3/3 (opus).

**Verdict**
partial — verdicts C1/C3/C5 falsified-on-paper but measure a hookless team-irfan; rerun N5/team ×2 + MEM team ×4 on v3.1.2 before trusting them. C4 holds. Ops: MEM cells ran in 3 per-arm lanes (wall_sec noisy, cost clean); one OAuth session-limit stall mid-run, resumed on guvian14 account.

### R-0002 · 2026-08-20 · [FEAT:bench-harness-v4] [MOD:benchmarks] [STATUS:shipped] [DEC:yes]

**Input**
Implement Harness Benchmark v4 per SPEC.md: five falsifiable claims (C1-C5),
trap tasks Q1/F1/N5/B1/MEM-A/MEM-B, sequential runner, calibrated pairwise
judge, extract.py, report.py. Mark v3 superseded-for-conclusions.

**Output**
- files: `benchmarks/harness-v4/` (SPEC, README, tasks/, fixture-patches/,
  judge/, bin/{init,run,score,judge,selftest,status}.sh + {extract,report,test_extract}.py),
  `benchmarks/README.md`, v3 README note, repo README + CHANGELOG
- change: full v4 harness; fixture gains customers/refunds/audit modules; each
  task state = single orphan-commit tag (no history leak); MEM pair shares one
  persistent clone, scored from recorded commits in throwaway checkouts.
- decision: task states as parentless `git commit-tree` snapshots (rejected:
  linear commits — history would reveal bug planting); judge flip-on-swap = tie.
- tests: `bin/selftest.sh` (8 scorer cases incl. band-aid + 3-of-5 traps),
  `bin/test_extract.py` (3), `judge.sh --calibrate` 3/3 with claude-opus-5.

**Verdict**
shipped — harness ready; nothing run yet (run.sh all ≈45 opus sessions is the
deliberate next spend). configs/ holds plaintext OAuth copies — delete after runs.

### R-0001 · 2026-08-20 · [FEAT:harness-v3] [MOD:benchmarks/harness-v3,hooks] [STATUS:partial] [DEC:yes]

**Input**
Continue the haiku benchmark run for plugin 3.1.2 (Stop-hook driver): finish T2+T3 all arms, score, publish, analyse.

**Output**
- files: `results/2026-08-20-haiku-v3-driverfix/`, `docs/evaluations/2026-08-20-harness-v3-haiku-driverfix.md`, `bin/score.sh`, `bin/publish.sh`, `RESUME.md`
- change: 35/36 cells scored (T2/team/1 timed out, retry operator-aborted); 0/4 hypotheses hold; team 9/11 correct; 76% of team spend on opus/sonnet subagents despite TG_BENCH_MODEL=haiku.
- decision: plugin not touched mid-run (one variable per run); harness-only fixes landed (score.sh all rewrites CSV, publish.sh survives incomplete matrix). Driver `last_assistant_message` fix and PreToolUse model-pin hook deferred to next plugin version.
- tests: `bin/selftest.sh` green 14:27 (pre-run); bash -n on edited scripts.

**Verdict**
partial — run complete and published, but cost numbers for arm C are not haiku-comparable; re-run arm C after the model-pin hook.
