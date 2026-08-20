#!/usr/bin/env bash
# Proves the scorer works before any money is spent on agents.
#
#   selftest.sh
#
# Stands in canned patches for the agent — a correct fix per task, plus the
# traps each task exists to catch — and asserts the scorer grades each one the
# way the spec says. Also runs extract.py's unit tests. If this fails, the
# benchmark measures nothing and no run is worth starting.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V3="$H/../harness-v3"
BENCH_ROOT="${BENCH_ROOT:-$HOME/team-irfan-bench-v4}"
WT_ROOT="${WT_ROOT:-$HOME/team-irfan-bench-v4-wt}"
fails=0

[ -d "$BENCH_ROOT/.git" ] || { echo "selftest.sh: run bin/init.sh first"; exit 1; }

echo "== extract.py unit tests =="
python3 "$H/bin/test_extract.py" 2>&1 | tail -1 || fails=$((fails+1))
echo

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
  printf '{"status":"selftest","wall_sec":0}\n' > "$1/meta.json"
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
  out="$H/runs/$task/selftest/${case#*-}"
  rm -rf "$wt" "$out"
  git -C "$BENCH_ROOT" worktree prune
  git -C "$BENCH_ROOT" worktree add -q --detach "$wt" "$(base_tag "$task")"
  deps_db "$wt"
  apply_patch "$case" "$wt"
  fake_run "$out" "$wt"

  "$H/bin/score.sh" "$task" selftest "${case#*-}" >/dev/null 2>&1
  got=$(tail -1 "$H/results/results.csv" | awk -F'","' '{print $5}')
  if [ "$(awk -v g="$got" -v w="$want" 'BEGIN{print (g+0==w+0)?1:0}')" = 1 ]; then
    echo "ok   $case -> pass_rate $got"
  else
    echo "FAIL $case -> pass_rate $got, wanted $want"
    fails=$((fails+1))
  fi
  rm -rf "$wt"
done

# MEM path: clone + commits, scored from the recorded commit, never the live clone
task=MEM-A; case=MEM-good; want=1
wt="$WT_ROOT/selftest-mem"; out="$H/runs/MEM-A/selftest/good"
rm -rf "$wt" "$out"; mkdir -p "$wt" "$out"
git -C "$BENCH_ROOT" archive mem-base | tar -x -C "$wt"
( cd "$wt" && git init -q -b main && git add -A \
    && git -c user.name=bench -c user.email=bench@local commit -qm "chore: app" )
deps_db "$wt"
fake_run "$out" "$wt"
git -C "$wt" rev-parse HEAD > "$out/base-commit.txt"
apply_patch "$case" "$wt"
git -C "$wt" add -A
git -C "$wt" -c user.name=bench -c user.email=bench@local commit -qm "chore: session"
git -C "$wt" rev-parse HEAD > "$out/commit.txt"
"$H/bin/score.sh" MEM-A selftest good >/dev/null 2>&1
got=$(tail -1 "$H/results/results.csv" | awk -F'","' '{print $5}')
if [ "$(awk -v g="$got" -v w="$want" 'BEGIN{print (g+0==w+0)?1:0}')" = 1 ]; then
  echo "ok   MEM-good -> pass_rate $got"
else
  echo "FAIL MEM-good -> pass_rate $got, wanted $want"
  fails=$((fails+1))
fi
rm -rf "$wt"

# selftest rows must not linger in the real CSV
grep -v ',"selftest",' "$H/results/results.csv" > "$H/results/results.csv.tmp" \
  && mv "$H/results/results.csv.tmp" "$H/results/results.csv"
rm -rf "$H/runs/Q1/selftest" "$H/runs/F1/selftest" "$H/runs/B1/selftest" \
       "$H/runs/N5/selftest" "$H/runs/MEM-A/selftest"

echo
[ "$fails" = 0 ] && echo "selftest passed" || echo "selftest failed: $fails case(s)"
exit "$fails"
