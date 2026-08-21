#!/usr/bin/env bash
# Proves the harness works before any money is spent on agents.
#
#   selftest.sh
#
# Two suites, zero cost, zero LLM, no real `claude` process ever:
#
#   SCORER      stands in canned patches for the agent — a correct fix per task,
#               plus the traps each task exists to catch — and asserts the scorer
#               grades each one the way the spec says. Plus extract.py's units.
#   SUPERVISOR  drives run.sh/score.sh/same-hole.sh/report.py against
#               selftest/fake-claude, and asserts the things that silently
#               invalidated the 2026-08-20 opus matrix are now caught: a plugin
#               that never loaded, a driver that never fired, an unpinned SHA, a
#               runaway cell, a band-aid, and a verdict computed from too little
#               valid data.
#
# Everything runs under BENCH_TIER=selftest, so it writes runs/selftest/ and
# results/selftest/ and deletes both on the way out. It never touches a real
# tier's CSV. If this fails, the benchmark measures nothing and no run is worth
# starting.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V3="$H/../harness-v3"

export BENCH_TIER=selftest
export CLAUDE_BIN="$H/selftest/fake-claude"
# The supervisor's real gates cost money or need a live install; the selftest
# proves the code paths they guard, not the gates themselves (run-checks.sh
# section 36 covers the hooks, judge.sh --calibrate covers the judge).
export BENCH_SKIP_PIN=1 BENCH_SKIP_CALIBRATE=1 BENCH_SKIP_SMOKE=1
unset TEAM_IRFAN_NOTIFY_URL

BENCH_ROOT="${BENCH_ROOT:-$HOME/team-irfan-bench-v4}"
# Own worktree root: cleanup must never be able to delete a real run's clone,
# and the "-selftest" in the path is what makes the fake transcripts findable.
export WT_ROOT="${WT_ROOT:-$HOME/team-irfan-bench-v4-wt}-selftest"
RUNS="$H/runs/selftest"
RES="$H/results/selftest"
CSV="$RES/results.csv"
fails=0

[ -d "$BENCH_ROOT/.git" ] || { echo "selftest.sh: run bin/init.sh first"; exit 1; }
[ -x "$CLAUDE_BIN" ] || { echo "selftest.sh: $CLAUDE_BIN not executable"; exit 1; }

cleanup() {
  rm -rf "$RUNS" "$RES"
  git -C "$BENCH_ROOT" worktree prune 2>/dev/null
  rm -rf "$WT_ROOT"
  # fake transcripts land under the real configs/ — the worktree slug carries
  # "-selftest", so only ours match.
  rm -rf "$H"/configs/*/projects/*bench-v4-wt-selftest* \
         "$H"/configs/*/projects/*selftest-same-hole* 2>/dev/null
}
trap cleanup EXIT

ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1${2:+ — $2}"; fails=$((fails+1)); }
chk() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "got '$2', want '$3'"; }
chk_num() {  # name got want — float-tolerant
  [ "$(awk -v g="$2" -v w="$3" 'BEGIN{print (g+0==w+0)?1:0}')" = 1 ] \
    && ok "$1" || bad "$1" "got '$2', want '$3'"
}
jqf() { jq -r "$2" "$1" 2>/dev/null || echo ""; }

run_to() {  # run_to <secs> <cmd...>; TERM then KILL, so a wedged case can't hang the suite
  local secs=$1; shift
  reap
  "$@" >"$RES/.last.log" 2>&1 & local p=$!
  ( sleep "$secs"; kill -TERM "$p" 2>/dev/null; sleep 2; kill -KILL "$p" 2>/dev/null ) &
  local k=$!
  wait "$p"; local rc=$?
  kill "$k" 2>/dev/null
  return "$rc"
}

# Swept BEFORE each run, never after: once run.sh returns, a surviving shim is
# evidence (case i asserts run.sh really killed its child), so the suite must
# not be the thing that tidies it away. Only ever matches our own shim.
reap() { pkill -f 'selftest/fake-claude' 2>/dev/null; sleep 0.5; return 0; }
shims_alive() { pgrep -f 'selftest/fake-claude' 2>/dev/null | wc -l | tr -d ' '; }

why() { printf '%s' "$(tail -3 "$RES/.last.log" 2>/dev/null | tr '\n' ' ')"; }

meta()  { jqf "$RUNS/$1/$2/$3/meta.json" "$4"; }
ledger_has() { grep -q "\"task\":\"$1\"" "$RES/ledger.jsonl" 2>/dev/null; }

mkdir -p "$RES"

# =========================================================== SCORER SUITE ====
echo "== extract.py unit tests =="
if python3 "$H/bin/test_extract.py" >/dev/null 2>&1; then
  ok "test_extract"
else
  bad "test_extract" "$(python3 "$H/bin/test_extract.py" 2>&1 | tail -1)"
fi
echo
echo "== scorer =="

base_tag() {
  case "$1" in
    Q1) echo q1-base ;; F1) echo f1-base ;; N5) echo n5-base ;;
    B1) echo b1-base ;; MEM-A|MEM-B) echo mem-base ;;
  esac
}

deps_db() {
  local wt=$1
  cp -Rc "$BENCH_ROOT/node_modules" "$wt/node_modules" 2>/dev/null \
    || cp -R "$BENCH_ROOT/node_modules" "$wt/node_modules"
  sed "s|DB_FILE|selftest.db|" "$wt/.env.example" > "$wt/.env"
  ( cd "$wt" && DATABASE_URL="file:./selftest.db" \
      npx prisma db push --force-reset --skip-generate >/dev/null 2>&1 )
}

fake_run() {  # $1 out dir, $2 wt
  mkdir -p "$1"
  printf '{"session_id":"selftest","total_cost_usd":0,"num_turns":0,"duration_ms":0,"result":"Done."}\n' > "$1/result.json"
  printf '{"status":"ok","reason":"","wall_sec":0,"tier":"selftest"}\n' > "$1/meta.json"
  echo "$2" > "$1/worktree.path"
}

bandaid() {  # Jakarta special-case in the caller — the trap B1 exists to catch
  python3 - "$1" <<'PY'
import sys
p = sys.argv[1] + '/src/reports/reports.service.ts'
s = open(p).read()
old = """    for (const tx of transactions) {
      const day = dayKeyInZone(tx.occurredAt, timeZone);"""
new = """    for (const tx of transactions) {
      let day = dayKeyInZone(tx.occurredAt, timeZone);
      if (timeZone === 'Asia/Jakarta') {
        day = new Date(tx.occurredAt.getTime() + 7 * 3_600_000).toISOString().slice(0, 10);
      }"""
assert old in s
open(p, 'w').write(s.replace(old, new))
PY
}

apply_patch() {
  local case=$1 wt=$2
  case "$case" in
    Q1-clean) : ;;
    Q1-edited) printf '\n// noted\n' >> "$wt/src/audit/audit.controller.ts" ;;
    F1-good) cp "$H/fixture-patches/ref/src/invoices/invoices.controller.ts" "$wt/src/invoices/" ;;
    B1-good) cp "$V3/fixture/src/common/date.util.ts" "$wt/src/common/" ;;
    B1-bandaid) bandaid "$wt" ;;
    N5-good)
      cp "$H/fixture-patches/base/src/customers/customers.service.ts" "$wt/src/customers/"
      cp "$H/fixture-patches/base/src/refunds/refunds.service.ts" "$wt/src/refunds/"
      cp "$H/fixture-patches/base/src/audit/audit.service.ts" "$wt/src/audit/"
      cp "$H/fixture-patches/base/src/reports/reports.service.ts" "$wt/src/reports/"
      cp "$H/fixture-patches/ref/src/invoices/invoices.service.ts" "$wt/src/invoices/" ;;
    N5-partial)  # fixes 3 of 5 and declares done — the C1 trap
      cp "$H/fixture-patches/base/src/customers/customers.service.ts" "$wt/src/customers/"
      cp "$H/fixture-patches/base/src/refunds/refunds.service.ts" "$wt/src/refunds/"
      cp "$H/fixture-patches/base/src/audit/audit.service.ts" "$wt/src/audit/" ;;
    MEM-good) cp "$H/fixture-patches/base/src/reports/reports.service.ts" "$wt/src/reports/" ;;
  esac
}

csv_last() { tail -1 "$CSV" | awk -F'","' '{print $5}'; }   # column 5 = pass_rate

# task | case | expected pass_rate
CASES="
Q1|Q1-clean|1
Q1|Q1-edited|0
F1|F1-good|1
B1|B1-good|1
B1|B1-bandaid|0
N5|N5-good|1
N5|N5-partial|0.6
"

for spec in $CASES; do
  IFS='|' read -r task case want <<< "$spec"
  wt="$WT_ROOT/selftest-$case"
  out="$RUNS/$task/selftest/${case#*-}"
  rm -rf "$wt" "$out"
  git -C "$BENCH_ROOT" worktree prune
  git -C "$BENCH_ROOT" worktree add -q --detach "$wt" "$(base_tag "$task")"
  deps_db "$wt"
  apply_patch "$case" "$wt"
  fake_run "$out" "$wt"

  "$H/bin/score.sh" "$task" selftest "${case#*-}" >/dev/null 2>&1
  chk_num "$case pass_rate" "$(csv_last)" "$want"
  rm -rf "$wt"
done

# MEM path: clone + commits, scored from the recorded commit, never the live clone
wt="$WT_ROOT/selftest-mem"; out="$RUNS/MEM-A/selftest/good"
rm -rf "$wt" "$out"; mkdir -p "$wt" "$out"
git -C "$BENCH_ROOT" archive mem-base | tar -x -C "$wt"
( cd "$wt" && git init -q -b main && git add -A \
    && git -c user.name=bench -c user.email=bench@local commit -qm "chore: app" )
deps_db "$wt"
fake_run "$out" "$wt"
git -C "$wt" rev-parse HEAD > "$out/base-commit.txt"
apply_patch MEM-good "$wt"
git -C "$wt" add -A
git -C "$wt" -c user.name=bench -c user.email=bench@local commit -qm "chore: session"
git -C "$wt" rev-parse HEAD > "$out/commit.txt"
"$H/bin/score.sh" MEM-A selftest good >/dev/null 2>&1
chk_num "MEM-good pass_rate" "$(csv_last)" 1
rm -rf "$wt"
# ======================================================= SUPERVISOR SUITE ====
echo
echo "== supervisor (fake claude) =="

fresh() { rm -rf "$RUNS" "$RES"; mkdir -p "$RES"; }
csvcol() { awk -F'","' -v n="$2" '{print $n}' <<< "$1"; }   # 2..38 are clean

# --- a. plugin never loaded -> INFRA_FAIL + lane abort + $0 on the rest ------
fresh
run_to 900 env FAKE_NO_SENTINEL=1 "$H/bin/run.sh" \
    --matrix --tasks Q1,F1 --arms team --lanes 1
a_rc=$?
chk "a plugin-load INFRA_FAIL" "$(meta Q1 team 1 '.status')|$(meta Q1 team 1 '.reason')" \
    "INFRA_FAIL|plugin-load-failed"

aborted=0 spawned=0 cost=0
for t in Q1 F1; do
  for r in 1 2 3; do
    [ "$t/$r" = "Q1/1" ] && continue
    [ "$(meta "$t" team "$r" '.reason')" = "lane-aborted:plugin-load-failed" ] \
      && aborted=$((aborted+1))
    [ -s "$RUNS/$t/team/$r/result.json" ] && spawned=$((spawned+1))
    cost=$(awk -v c="$cost" -v n="$(meta "$t" team "$r" '.cost_usd // 0')" 'BEGIN{print c+n+0}')
  done
done
chk "a lane-abort reason"         "$aborted" 5
chk "a lane-abort no result.json" "$spawned" 0
chk_num "a lane-abort cost 0"     "$cost" 0
ledger_has F1 && ok "a lane-abort ledger" || bad "a lane-abort ledger" "no F1 rows in ledger.jsonl"
grep -q 'lane-abort' "$RES/notifications.log" 2>/dev/null \
  && ok "a lane-abort notification" \
  || bad "a lane-abort notification" "no lane-abort line in notifications.log"
[ -s "$RES/ABORTED" ] && [ ! -f "$RES/DONE" ] && [ "$a_rc" != 0 ] \
  && ok "a aborts non-zero" \
  || bad "a aborts non-zero" "rc=$a_rc DONE=$([ -f "$RES/DONE" ] && echo y || echo n) ABORTED=$([ -s "$RES/ABORTED" ] && echo y || echo n)"

# --- b/k/l share one aborted two-arm matrix ---------------------------------
#   b: the bare lane is not collateral damage
#   k: an abort still scores and still reports
#   l: --redo-infra reruns the infra cells once the cause is fixed
fresh
run_to 900 env FAKE_NO_SENTINEL=1 "$H/bin/run.sh" \
    --matrix --tasks Q1 --arms bare,team --lanes 2
bk_rc=$?
bare_ok=0
for r in 1 2 3; do [ "$(meta Q1 bare "$r" '.status')" = ok ] && bare_ok=$((bare_ok+1)); done
chk "b bare lane unaffected" "$bare_ok" 3

bare_rows=$(grep -c '^"Q1","bare"' "$CSV" 2>/dev/null || echo 0)
report_md=$(ls "$RES"/REPORT-*.md 2>/dev/null | head -1)
if [ -s "$RES/ABORTED" ] && [ "$bk_rc" != 0 ] && [ "$bare_rows" -ge 3 ] && [ -s "$report_md" ]; then
  ok "k abort still scores + reports"
else
  bad "k abort still scores + reports" \
      "rc=$bk_rc aborted=$([ -s "$RES/ABORTED" ] && echo y || echo n) bare_rows=$bare_rows report=${report_md:-none}"
fi

# l: same matrix, cause fixed (sentinel now written), only the infra cells rerun
run_to 900 "$H/bin/run.sh" --matrix --tasks Q1 --arms bare,team --lanes 2 \
    --redo-infra=plugin
redone=0
for r in 1 2 3; do [ "$(meta Q1 team "$r" '.status')" = ok ] && redone=$((redone+1)); done
moved=$(ls -d "$RUNS"/Q1/team/*.infra-* 2>/dev/null | wc -l | tr -d ' ')
if [ "$redone" = 3 ] && [ "$moved" -ge 1 ] && [ -s "$RES/DONE" ]; then
  ok "l --redo-infra"
else
  bad "l --redo-infra" "team ok=$redone/3 moved-aside=$moved DONE=$([ -s "$RES/DONE" ] && echo y || echo n)"
fi

# --- c. ROUTE: FULL with no heartbeat -> infra/driver-absent ----------------
# --- m. scoring the same cell twice leaves one row -------------------------
fresh
if run_to 600 env FAKE_NO_HEARTBEAT=1 FAKE_ROUTE=FULL "$H/bin/run.sh" Q1 team 1 \
   && [ -s "$RUNS/Q1/team/1/result.json" ]; then
  "$H/bin/score.sh" Q1 team 1 >/dev/null 2>&1
  row=$(tail -1 "$CSV")
  chk "c driver-absent" \
      "$(csvcol "$row" 35)|$(csvcol "$row" 36)|$(csvcol "$row" 20)" \
      "infra|driver-absent|false"
  "$H/bin/score.sh" Q1 team 1 >/dev/null 2>&1
  chk "m dedupe" "$(grep -c '^"Q1","team","1",' "$CSV")" 1
else
  bad "c driver-absent" "no result.json — run.sh said: $(why)"
  bad "m dedupe"        "depends on c"
fi

# --- d. an unpinned SHA is refused before anything is created ---------------
fresh
# deliberately WITHOUT BENCH_SKIP_PIN. The working tree is dirty during
# development, so either refusal is the correct answer — both prove the matrix
# does not start on an unverified build.
run_to 120 env -u BENCH_SKIP_PIN "$H/bin/run.sh" \
    --matrix --tasks Q1 --arms bare --expect-sha 0000000
rc=$?
msg=$(cat "$RES/.last.log" 2>/dev/null)
if [ "$rc" = 0 ]; then
  bad "d sha refused" "run.sh exited 0"
elif grep -qiE 'sha|dirty|uncommitted|working tree' <<< "$msg"; then
  ok "d sha refused"
else
  bad "d sha refused" "rc=$rc but message names neither sha nor dirty tree"
fi
[ -d "$RUNS/Q1" ] && bad "d sha no cell dir" "runs/selftest/Q1 was created" \
                  || ok "d sha no cell dir"

# --- e. budget guards: spend cap and wall cap -------------------------------
fresh
run_to 300 env FAKE_CLAUDE_MODE=spend CELL_BUDGET_USD=0.001 MAX_SEC=300 \
    "$H/bin/run.sh" Q1 bare 1
if [ -s "$RUNS/Q1/bare/1/meta.json" ]; then
  chk "e budget kill" "$(meta Q1 bare 1 '.status')|$(meta Q1 bare 1 '.reason')" \
      "INFRA_FAIL|budget"
else
  bad "e budget kill" "no meta.json — run.sh said: $(why)"
fi

rm -rf "$RUNS/Q1"
run_to 300 env FAKE_CLAUDE_MODE=slow FAKE_SLEEP=8 MAX_SEC=2 \
    "$H/bin/run.sh" Q1 bare 1
if [ -s "$RUNS/Q1/bare/1/meta.json" ]; then
  chk "e wall kill" "$(meta Q1 bare 1 '.status')|$(meta Q1 bare 1 '.reason')" \
      "INFRA_FAIL|budget(wall)"
else
  bad "e wall kill" "no meta.json — run.sh said: $(why)"
fi

# --- i. the kill is real: the child dies, and it dies promptly --------------
# A cap that only stops WAITING for the process leaves it running and billing.
rm -rf "$RUNS/Q1"
run_to 300 env FAKE_CLAUDE_MODE=slow FAKE_SLEEP=30 MAX_SEC=3 \
    "$H/bin/run.sh" Q1 bare 1
alive=$(shims_alive)
wall=$(meta Q1 bare 1 '.wall_sec // 999')
if [ "$(meta Q1 bare 1 '.reason')" = "budget(wall)" ] \
   && [ "${wall:-999}" -le 10 ] 2>/dev/null && [ "$alive" = 0 ]; then
  ok "i kill is real"
else
  bad "i kill is real" "reason=$(meta Q1 bare 1 '.reason') wall=${wall}s shims_still_alive=$alive"
fi

# --- j. MEM-B must not inherit MEM-A's sentinel ----------------------------
# Both sessions share one clone, so a stale .tg-bench/ would make a dead plugin
# look loaded for the whole second half of the C4 protocol.
fresh
if run_to 900 "$H/bin/run.sh" MEM-A team 1 \
   && [ "$(meta MEM-A team 1 '.status')" = ok ]; then
  run_to 900 env FAKE_NO_SENTINEL=1 "$H/bin/run.sh" MEM-B team 1
  chk "j MEM-B sentinel isolation" \
      "$(meta MEM-B team 1 '.status')|$(meta MEM-B team 1 '.reason')" \
      "INFRA_FAIL|plugin-load-failed"
else
  bad "j MEM-B sentinel isolation" "MEM-A did not run ok: $(meta MEM-A team 1 '.status') — $(why)"
fi

# --- f/o. same-hole: code counts, prose does not ---------------------------
fresh
mem_cell() {  # arm round [session-id] -> a MEM-B cell dir with a diff.txt on stdin
  local d="$RUNS/MEM-B/$1/$2" sid="${3:-selftest-sh}"
  mkdir -p "$d"
  cat > "$d/diff.txt"
  jq -nc --arg s "$sid" '{session_id:$s,total_cost_usd:0,num_turns:1,duration_ms:0,result:"Done."}' > "$d/result.json"
  jq -nc --arg a "$1" --arg r "$2" --arg s "$sid" \
     '{task:"MEM-B",arm:$a,round:$r,status:"ok",reason:"",tier:"selftest",session_id:$s}' > "$d/meta.json"
}
# f-hit: the band-aid shipped in the diff — index the loop instead of removing it
mem_cell bare 1 <<'DIFF'
diff --git a/prisma/schema.prisma b/prisma/schema.prisma
--- a/prisma/schema.prisma
+++ b/prisma/schema.prisma
@@ -20,6 +20,7 @@ model Activity {
   customerId String
+  @@index([customerId])
 }
DIFF
# f-miss: the reference fix — one joined findMany, no marker anywhere
{ printf 'diff --git a/src/customers/customers.service.ts b/src/customers/customers.service.ts\n'
  printf -- '--- a/src/customers/customers.service.ts\n+++ b/src/customers/customers.service.ts\n@@ -1,1 +1,%d @@\n' \
    "$(wc -l < "$H/fixture-patches/base/src/customers/customers.service.ts")"
  sed 's/^/+/' "$H/fixture-patches/base/src/customers/customers.service.ts"
} | mem_cell bare 2

"$H/bin/same-hole.sh" bare 1 >/dev/null 2>&1
"$H/bin/same-hole.sh" bare 2 >/dev/null 2>&1
chk "f same-hole hit"  "$(jqf "$RES/same-hole/bare-r1.json" '.same_hole')" true
chk "f same-hole miss" "$(jqf "$RES/same-hole/bare-r2.json" '.same_hole')" false

# o: transcript channel. A prisma/ edit counts; an identical band-aid written
# into a .md retro does not — team is the only arm that writes prose, so
# counting prose would bias C4 against the arm C4 exists to measure.
fake_transcript() {  # arm session-id  <- FAKE_EDITS
  local dir="$H/configs/$1/projects/selftest-same-hole"
  mkdir -p "$dir"
  ( cd "$dir" && env CLAUDE_CONFIG_DIR="$H/configs/$1" FAKE_LINES=1 \
      "$CLAUDE_BIN" -p --session-id "$2" <<< hi >/dev/null 2>&1 )
  find "$H/configs/$1/projects" -name "$2.jsonl" 2>/dev/null | head -1
}
: | mem_cell omc 1 sh-code
FAKE_EDITS='prisma/schema.prisma::@@index([customerId])|.team-irfan/handoffs/x.md::cache = new Map()' \
  fake_transcript omc sh-code >/dev/null
: | mem_cell omc 2 sh-prose
FAKE_EDITS='.team-irfan/handoffs/x.md::cache = new Map()' \
  fake_transcript omc sh-prose >/dev/null
"$H/bin/same-hole.sh" omc 1 >/dev/null 2>&1
"$H/bin/same-hole.sh" omc 2 >/dev/null 2>&1
o_hits=$(jq -r '[.hits_code[].marker] | sort | join(",")' "$RES/same-hole/omc-r1.json" 2>/dev/null)
if [ "$(jqf "$RES/same-hole/omc-r1.json" '.same_hole')" = true ] \
   && [ "$o_hits" = '@@index' ]; then
  ok "o same-hole code channel"
else
  bad "o same-hole code channel" "same_hole=$(jqf "$RES/same-hole/omc-r1.json" '.same_hole') hits_code=[$o_hits], wanted true/[@@index]"
fi
chk "o same-hole ignores prose" "$(jqf "$RES/same-hole/omc-r2.json" '.same_hole')" false

# --- g/n. verdicts from synthetic CSVs -------------------------------------
# g: all-infra team rows must read INSUFFICIENT DATA, never a verdict
# n: enough valid rows + one unverified team run must read FALSIFIED
fresh
HDR=$(grep -m1 '^HEADER=' "$H/bin/score.sh" | sed "s/^HEADER='//; s/'\$//")
synth_row() {  # task arm round pass_rate validity reason cell_status verified_before_done
  python3 - "$@" <<'PY'
import csv, sys
t, a, r, pr, val, rsn, cs, ver = sys.argv[1:9]
# bools are jq `tostring` output: lowercase true/false/null, never Python's True
row = [t, a, r, "ok", pr, "1", "1", "pass", "ok", "0", "10",
       "0.1", "100", "100", "5", "3", "60",
       ver, "true", "false", "0", "true", "10", "10", "0.0", "0.9", "0", "null",
       "selftest", "deadbee", "3.1.3", "claude-sonnet-5", "low",
       "sid-%s-%s-%s" % (t, a, r), val, rsn, cs, "", "result"]
csv.writer(sys.stdout, quoting=csv.QUOTE_ALL, lineterminator="\n").writerow(row)
PY
}
echo "$HDR" > "$CSV"
for r in 1 2; do
  synth_row N5 team "$r" 0 infra plugin-load-failed INFRA_FAIL true >> "$CSV"
  synth_row N5 bare "$r" 1 valid "" PASS true >> "$CSV"
  synth_row N5 omc  "$r" 1 valid "" PASS true >> "$CSV"
done
chk "g csv column count" "$(head -2 "$CSV" | tail -1 | tr ',' '\n' | wc -l | tr -d ' ')" \
                         "$(tr ',' '\n' <<< "$HDR" | wc -l | tr -d ' ')"
rep=$(python3 "$H/bin/report.py" --tier selftest 2>&1)
grep -A4 -iE '^ *C1' <<< "$rep" | grep -qi 'INSUFFICIENT DATA' \
  && ok "g INSUFFICIENT DATA" || bad "g INSUFFICIENT DATA" "C1 did not read INSUFFICIENT DATA"
grep -qE 'team.*\b2\b' <<< "$(sed -n '1,20p' <<< "$rep")" \
  && ok "g validity header" || bad "g validity header" "no per-arm header naming team's 2 infra cells"
tail -1 <<< "$rep" | grep -qE '^report: /' \
  && ok "g report: line" || bad "g report: line" "last stdout line was '$(tail -1 <<< "$rep")'"

# n: MIN_SCORED_PER_ARM is 8; give every arm the full 12 scored rows.
echo "$HDR" > "$CSV"
for arm in bare omc team; do
  for spec in F1:1 F1:2 F1:3 B1:1 B1:2 B1:3 N5:1 N5:2 MEM-A:1 MEM-A:2 MEM-B:1 MEM-B:2; do
    ver=true
    # one team run that never verified — SPEC C1: that alone falsifies it
    [ "$arm" = team ] && [ "$spec" = N5:1 ] && ver=false
    synth_row "${spec%:*}" "$arm" "${spec#*:}" 1 valid "" PASS "$ver" >> "$CSV"
  done
done
rep=$(python3 "$H/bin/report.py" --tier selftest 2>&1)
grep -A6 -iE '^ *C1' <<< "$rep" | grep -qi 'FALSIFIED' \
  && ok "n C1 FALSIFIED" \
  || bad "n C1 FALSIFIED" "C1 read: $(grep -iE '^ *C1' <<< "$rep" | head -1)"

# --- h. the operator's two files: PROGRESS.md while running, DONE at the end -
fresh
run_to 1200 "$H/bin/run.sh" --matrix --tasks Q1 --arms bare --lanes 1
if [ -s "$RES/PROGRESS.md" ] && grep -qi 'done' "$RES/PROGRESS.md" \
   && grep -qE '3/3|\b3\b' "$RES/PROGRESS.md"; then
  ok "h PROGRESS.md"
else
  bad "h PROGRESS.md" "missing, or does not report 3 cells done"
fi
rp=$(tr -d ' \n' < "$RES/DONE" 2>/dev/null)
if [ -n "$rp" ] && { [ -s "$rp" ] || [ -s "$RES/$(basename "$rp")" ]; }; then
  ok "h DONE + report"
else
  bad "h DONE + report" \
      "DONE names no existing report (got '${rp:-}')$( [ -f "$RES/ABORTED" ] && echo "; ABORTED: $(cat "$RES/ABORTED")" )"
fi

echo
[ "$fails" = 0 ] && echo "selftest passed" || echo "selftest failed: $fails case(s)"
exit "$fails"
