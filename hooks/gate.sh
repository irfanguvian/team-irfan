#!/usr/bin/env bash
# team-graph deterministic gate. Zero LLM. Run from a project root.
#
#   exit 0  →  GATE PASS
#   exit 1  →  GATE FAIL: <reason>
#
# Env (all optional):
#   TG_RUN            run dir, e.g. ~/.claude/team-graph/runs/20260815-fix-thing
#                     coverage baseline is read from $TG_RUN/coverage-base.txt
#   TG_BASE           git ref the worktree branched from (e.g. main). Used to
#                     find changed files when the executor already committed.
#   TG_SCAN=all       stub-scan every test file instead of only changed ones
#   TG_RECORD_BASE=1  write the coverage baseline, then exit 0
#
# NOTE ON RTK: this script deliberately calls tsc/vitest/jest raw. `rtk test`
# swallows the child exit code (`rtk test bash -c 'exit 1'` returns 0) and
# `rtk err` remaps it to 3. A gate that trusts rtk reports green on red. The
# global PreToolUse hook does not reach in here — it only rewrites Bash tool
# calls, and `bash gate.sh` itself is passed through unchanged.

set -uo pipefail

# shellcheck source=../lib/atomic.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/atomic.sh"

MAX_LINES=40   # cap on any failing command's output, keeps agent context small

fail() { echo; echo "GATE FAIL: $1"; exit 1; }
show() { head -n "$MAX_LINES"; }

# ---------------------------------------------------------------- 1. detect

[ -f package.json ] || fail "no package.json in $(pwd) — run gate.sh from the project root"

if   [ -f pnpm-lock.yaml ];                     then PM=pnpm
elif [ -f yarn.lock ];                          then PM=yarn
elif [ -f bun.lockb ] || [ -f bun.lock ];       then PM=bun
elif [ -f package-lock.json ];                  then PM=npm
else PM=npm
fi

BIN=./node_modules/.bin
runner_bin() { [ -x "$BIN/$1" ] && echo "$BIN/$1"; }

if   [ -n "$(runner_bin vitest)" ]; then RUNNER=vitest
elif [ -n "$(runner_bin jest)"   ]; then RUNNER=jest
elif grep -q '"vitest"' package.json 2>/dev/null; then RUNNER=vitest
elif grep -q '"jest"'   package.json 2>/dev/null; then RUNNER=jest
else RUNNER=none
fi

TS=no
if [ -f tsconfig.json ] && { [ -x "$BIN/tsc" ] || grep -q '"typescript"' package.json 2>/dev/null; }; then
  TS=yes
fi

echo "gate: pm=$PM runner=$RUNNER typescript=$TS"

# ------------------------------------------------------- changed test files

changed_files() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  { [ -n "${TG_BASE:-}" ] && git diff --name-only "$TG_BASE"...HEAD 2>/dev/null
    git diff --name-only HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | sort -u
}

# A test file is one a runner would actually load. The extension must END the
# name — `.test.ts.bak` and `.test.ts.orig` from a merge are not test files,
# and scanning them produces failures nobody can fix.
TEST_RE='\.(test|spec)\.(ts|tsx|js|jsx|mjs|cjs|mts|cts)$'

is_test_path() { printf '%s' "$1" | grep -qE "$TEST_RE"; }

TEST_FILES=""
if [ "${TG_SCAN:-}" = "all" ]; then
  TEST_FILES=$(find . -type d -name node_modules -prune -o -type f -print 2>/dev/null \
               | grep -E "$TEST_RE" | sort)
else
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    is_test_path "$f" && TEST_FILES="$TEST_FILES$f"$'\n'
  done <<< "$(changed_files)"
  TEST_FILES=$(printf '%s' "$TEST_FILES" | sed '/^$/d')
fi

# ------------------------------------------------------------- 2. typecheck

if [ "$TS" = yes ]; then
  TSC=$(runner_bin tsc)
  [ -z "$TSC" ] && TSC="npx --no-install tsc"
  if ! OUT=$($TSC --noEmit 2>&1); then
    echo "$OUT" | show
    fail "typecheck"
  fi
  echo "gate: typecheck ok"
else
  echo "gate: typecheck skipped (no tsconfig.json / no typescript)"
fi

# ------------------------------------------------------------------ 2b. lint
# 2026-08-20 T1: a correct fix died on one unused import — this gate said
# PASS, the external lint gate said fail. Guardrails rank static (types,
# lint) as layer 1; the gate runs what the guardrails preach.
if node -e 'process.exit((JSON.parse(require("fs").readFileSync("package.json","utf8")).scripts||{}).lint?0:1)' 2>/dev/null; then
  if ! OUT=$(npm run lint 2>&1); then
    echo "$OUT" | show
    fail "lint"
  fi
  echo "gate: lint ok"
else
  echo "gate: lint skipped (no lint script)"
fi

# ------------------------------------------------- 3+4. unit tests, coverage

# The run-wide baseline is written once from the project root. A gate run inside
# a tg-* worktree records to its OWN file instead, so a resumed run re-recording
# the baseline cannot rewrite the file concurrent executors are reading against —
# a torn read there produces a wrong PASS, which is worse than a crash.
COV_SHARED="${TG_RUN:-}/coverage-base.txt"
COV_BASE="$COV_SHARED"
case "$(basename "$(pwd)")" in
  tg-*) COV_BASE="${TG_RUN:-}/coverage-base-$(basename "$(pwd)").txt" ;;
esac
# reading: prefer this worktree's own baseline, fall back to the run's
[ "${TG_RECORD_BASE:-}" = "1" ] || [ -f "$COV_BASE" ] || COV_BASE="$COV_SHARED"

NEED_COV=no
[ -n "${TG_RUN:-}" ] && [ -f "$COV_BASE" ] && NEED_COV=yes
[ "${TG_RECORD_BASE:-}" = "1" ] && NEED_COV=yes

COV_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tg-cov.XXXXXX")
trap 'rm -rf "$COV_DIR"' EXIT

if [ "$RUNNER" = none ]; then
  echo "gate: no test runner installed — unit tests skipped"
  [ "$NEED_COV" = yes ] && fail "coverage requested but no test runner is installed"
else
  RB=$(runner_bin "$RUNNER"); [ -z "$RB" ] && RB="npx --no-install $RUNNER"
  if [ "$RUNNER" = vitest ]; then
    CMD=($RB run --passWithNoTests)
    [ "$NEED_COV" = yes ] && CMD+=(--coverage --coverage.reporter=json-summary "--coverage.reportsDirectory=$COV_DIR")
  else
    CMD=($RB --passWithNoTests)
    [ "$NEED_COV" = yes ] && CMD+=(--coverage --coverageReporters=json-summary "--coverageDirectory=$COV_DIR")
  fi

  if ! OUT=$("${CMD[@]}" 2>&1); then
    echo "$OUT" | grep -aE 'FAIL|✕|●|Error|error|failed' | show
    [ -z "$(echo "$OUT" | grep -aE 'FAIL|✕|●|Error|error|failed')" ] && echo "$OUT" | tail -n "$MAX_LINES"
    fail "unit tests"
  fi
  echo "gate: unit tests ok"
fi

SUMMARY="$COV_DIR/coverage-summary.json"

if [ "${TG_RECORD_BASE:-}" = "1" ]; then
  [ -n "${TG_RUN:-}" ] || fail "TG_RECORD_BASE=1 needs TG_RUN"
  [ -f "$SUMMARY" ] || fail "no coverage-summary.json produced — is a coverage provider installed?"
  mkdir -p "$TG_RUN"
  atomic_cp "$SUMMARY" "$COV_BASE" || fail "could not write the coverage baseline"
  echo "gate: coverage baseline written to $COV_BASE"
  echo
  echo "GATE PASS"
  exit 0
fi

if [ "$NEED_COV" = yes ]; then
  [ -f "$SUMMARY" ] || fail "no coverage-summary.json produced — is a coverage provider installed?"
  CHANGED_ALL=$(changed_files | tr '\n' ':')
  if ! DROP=$(TG_CHANGED="$CHANGED_ALL" node -e '
    const fs = require("fs");
    const base = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const now  = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    const changed = (process.env.TG_CHANGED || "").split(":").filter(Boolean);
    const tail = p => p.replace(process.cwd() + "/", "");
    const drops = [];
    for (const key of Object.keys(now)) {
      if (key === "total") continue;
      const rel = tail(key);
      // only files this run actually touched
      if (changed.length && !changed.some(c => rel.endsWith(c) || c.endsWith(rel))) continue;
      const b = base[key]; if (!b) continue;             // new file, no baseline to drop from
      if (now[key].lines.pct < b.lines.pct - 0.01)
        drops.push(`${rel}  ${b.lines.pct}% -> ${now[key].lines.pct}%`);
    }
    if (drops.length) { console.log(drops.join("\n")); process.exit(1); }
    process.exit(0);
  ' "$COV_BASE" "$SUMMARY" 2>&1); then
    echo "$DROP" | show
    fail "coverage dropped on changed files"
  fi
  echo "gate: coverage ok (no drop on changed files)"
elif [ -n "${TG_RUN:-}" ]; then
  echo "gate: coverage diff skipped (no baseline at $COV_BASE)"
else
  echo "gate: coverage diff skipped (TG_RUN not set)"
fi

# ------------------------------------------------------- 5. stub detection

if [ -z "$TEST_FILES" ]; then
  echo "gate: stub scan skipped (no changed test files; set TG_BASE or TG_SCAN=all)"
else
  HITS=""

  # line-based patterns
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    H=$(grep -nE \
      -e 'expect\([[:space:]]*true[[:space:]]*\)' \
      -e 'assert\.ok\([[:space:]]*true[[:space:]]*\)' \
      -e '\.skip\(' \
      -e '\.only\(' \
      -e '\b(it|test|describe)\.todo\b' \
      -e '\bx(it|test|describe)\(' \
      "$f" 2>/dev/null | sed "s|^|$f:|")
    [ -n "$H" ] && HITS="$HITS$H"$'\n'
  done <<< "$TEST_FILES"

  # empty test bodies, including multi-line: it('x', () => {}) / function () {}
  EMPTY=$(printf '%s\n' "$TEST_FILES" | tr '\n' '\0' | xargs -0 -r perl -0777 -ne '
    while (/(?:\b(?:it|test)\s*\(.{0,200}?,\s*(?:async\s*)?(?:\(\s*\)|function\s*\(\s*\))\s*(?:=>\s*)?\{\s*\})/gs) {
      my $pre = substr($_, 0, pos($_));
      my $line = ($pre =~ tr/\n//) + 1;
      print "$ARGV:$line: empty test body\n";
    }' 2>/dev/null)
  [ -n "$EMPTY" ] && HITS="$HITS$EMPTY"$'\n'

  HITS=$(printf '%s' "$HITS" | sed '/^$/d')
  if [ -n "$HITS" ]; then
    echo "$HITS" | show
    fail "stub tests detected"
  fi
  echo "gate: stub scan ok ($(printf '%s\n' "$TEST_FILES" | wc -l | tr -d ' ') test file(s))"
fi

# ------------------------------------------- 5b. assertion-free test cases

# QA writes <run>/test-cases.md from plan.json. A case that asserts nothing —
# status-only with no body/effect check, or an expect(true)-style line — is the
# markdown twin of a stub test, and it is caught the same way: deterministically,
# with a name, never by a review prompt.
TC="${TG_RUN:-}/test-cases.md"
if [ -n "${TG_RUN:-}" ] && [ -f "$TC" ]; then
  TCBAD=""
  # expect(true)-style lines anywhere in the file
  TRIV=$(grep -nE 'expect\([[:space:]]*true[[:space:]]*\)|assert\.ok\([[:space:]]*true[[:space:]]*\)' "$TC" 2>/dev/null | sed "s|^|$TC:|")
  [ -n "$TRIV" ] && TCBAD="$TRIV"$'\n'
  # a CASE block with no non-empty expect_body/expect_effect line
  NOASSERT=$(awk -v f="$TC" '
    function flush() { if (id != "" && !ok) printf "%s:%d: %s has no expect_body/expect_effect\n", f, ln, id }
    /^### CASE-/ { flush(); id=$2; ln=NR; ok=0; next }
    /^-?[[:space:]]*expect_(body|effect):[[:space:]]*[^[:space:]]/ { ok=1 }
    END { flush() }
  ' "$TC")
  [ -n "$NOASSERT" ] && TCBAD="$TCBAD$NOASSERT"$'\n'
  TCBAD=$(printf '%s' "$TCBAD" | sed '/^$/d')
  if [ -n "$TCBAD" ]; then
    echo "$TCBAD" | show
    fail "assertion-free test cases"
  fi
  echo "gate: test-case scan ok ($TC)"
fi

# ------------------------------------------ 5c. contract + index diff guards

# The 2026-08-21 sonnet-low matrix lost six C5 pairs to two defects a review
# prompt never caught, because guardrails/SKILL.md went unread on the FAST
# path: a fix that deleted a decorator or an error-response literal (a silent
# contract break, §182-187), and a new filter/sort shipped with
# prisma/schema.prisma untouched (§133). Both are visible in the diff, so the
# gate reads the diff instead of asking anyone to remember the rule.

run_diff() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  # `-- .` keeps a nested project root (a fixture inside a bigger repo) from
  # gating on its parent's changes.
  [ -n "${TG_BASE:-}" ] && git diff "$TG_BASE"...HEAD -- . 2>/dev/null
  git diff HEAD -- . 2>/dev/null
  git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do
    [ -n "$f" ] && git diff --no-index -- /dev/null "$f" 2>/dev/null
  done
}

DIFF=$(run_diff)

if [ -z "$DIFF" ]; then
  echo "gate: contract + index guards skipped (empty diff)"
else
  # What the run claims, in the artifacts a human actually reads: the run's own
  # markdown (plan included — an INTENTIONAL BREAKING is only valid if the
  # approved plan already declares it), the handoff, and the last commit message.
  GATED=$( { [ -n "${TG_RUN:-}" ] && cat "$TG_RUN"/*.md
             cat .team-irfan/handoffs/*.md
             git log -1 --format=%B
           } 2>/dev/null )

  if ! grep -q '^INTENTIONAL BREAKING:' <<< "$GATED"; then
    BREAKS=$(awk '
      /^\+\+\+ / { next }
      /^--- /    { f = substr($0, 7); next }
      /^-/       { if ($0 ~ /@HttpCode\(/ || $0 ~ /ok:[ \t]*false/)
                     printf "%s: %s\n", f, substr($0, 2) }
    ' <<< "$DIFF")
    if [ -n "$BREAKS" ]; then
      echo "$BREAKS" | show
      echo "guardrails §182-187: a contract-carrying line is not deleted in passing."
      echo "Restore it, or declare 'INTENTIONAL BREAKING: <what>' in the plan/report —"
      echo "valid only when the approved plan already says so."
      fail "contract line removed without INTENTIONAL BREAKING"
    fi
  fi

  if ! grep -qF 'index checked:' <<< "$GATED"; then
    IDX=$(awk '
      /^--- /    { next }
      /^\+\+\+ / { f = substr($0, 7); next }
      /^\+/      { if (f ~ /(^|\/)src\/.*\.ts$/ &&
                       (($0 ~ /(^|[^A-Za-z0-9_])in:[ \t]*/ && f ~ /\.(service|repository)\.ts$/) \
                        || $0 ~ /orderBy/))
                     printf "%s: %s\n", f, substr($0, 2) }
    ' <<< "$DIFF")
    if [ -n "$IDX" ] && ! changed_files | grep -q 'prisma/schema\.prisma'; then
      echo "$IDX" | show
      echo "guardrails §133: every WHERE / ORDER BY column is indexed, with the"
      echo "migration in the same change — prisma/schema.prisma is untouched here."
      echo "Add the index, or record 'index checked: <which existing index covers it>'."
      fail "new filter/sort without a schema change"
    fi
  fi

  echo "gate: contract + index guards ok"
fi

# ------------------------------------------------------- 6. mutation smoke

# Opt-in (TG_MUTATE=1) because it re-runs the suite once per source file. The
# QA runs it; executors do not.
#
# The stub scan above is syntactic — it catches a test that LOOKS empty. This
# catches the one that looks fine and asserts nothing real: delete the
# implementation, and if the test still passes it was never testing it. That is
# a deterministic check, so it belongs here and not in a slop-review prompt.

mut_restore_all() {
  for b in $MUT_BACKUPS; do
    [ -f "$b" ] && mv "$b" "${b%.tg-mutant-bak}"
  done
  MUT_BACKUPS=""
}
MUT_BACKUPS=""
trap 'rm -rf "$COV_DIR"; mut_restore_all' EXIT

if [ "${TG_MUTATE:-}" = "1" ] && [ "$RUNNER" != none ]; then
  SRC_RE='\.(ts|tsx|js|jsx|mjs|cjs|mts|cts)$'
  if [ "${TG_SCAN:-}" = "all" ]; then
    SRCS=$(find . -type d -name node_modules -prune -o -type f -print 2>/dev/null \
           | grep -E "$SRC_RE" | grep -vE "$TEST_RE" | grep -vE '\.d\.ts$' | sort)
  else
    SRCS=$(changed_files | grep -E "$SRC_RE" | grep -vE "$TEST_RE" | grep -vE '\.d\.ts$' | sort -u)
  fi

  SURVIVED=""
  CHECKED=0
  while IFS= read -r src; do
    [ -n "$src" ] && [ -f "$src" ] || continue
    stem="${src%.*}"; ext="${src##*.}"
    TFILE=""
    for cand in "$stem.test.$ext" "$stem.spec.$ext"; do
      [ -f "$cand" ] && TFILE="$cand" && break
    done
    [ -n "$TFILE" ] || continue

    # a stub module: every value export becomes a throwing function. Nothing
    # that imports it can do real work, so any test that still passes was
    # asserting on the import, not on the behaviour.
    if ! STUB=$(node -e '
      const fs = require("fs");
      const src = fs.readFileSync(process.argv[1], "utf8");
      const names = new Set();
      for (const re of [/export\s+(?:async\s+)?function\s+([A-Za-z_$][\w$]*)/g,
                        /export\s+(?:const|let|var)\s+([A-Za-z_$][\w$]*)/g,
                        /export\s+class\s+([A-Za-z_$][\w$]*)/g]) {
        let m; while ((m = re.exec(src))) names.add(m[1]);
      }
      for (const m of src.matchAll(/export\s*\{([^}]*)\}/g))
        for (const part of m[1].split(","))
          { const n = part.split(/\s+as\s+/).pop().trim(); if (/^[A-Za-z_$][\w$]*$/.test(n)) names.add(n); }
      if (!names.size) process.exit(3);
      process.stdout.write([...names].map(n =>
        "export const " + n + ": any = (..._a: any[]) => { throw new Error(\"mutant\") }"
      ).join("\n") + "\n");
    ' "$src" 2>/dev/null); then
      echo "gate: mutation skipped $src (no value exports to stub)"
      continue
    fi

    cp "$src" "$src.tg-mutant-bak" || fail "could not back up $src for mutation"
    MUT_BACKUPS="$MUT_BACKUPS $src.tg-mutant-bak"
    printf '%s' "$STUB" > "$src"

    if [ "$RUNNER" = vitest ]; then
      MOUT=$("$RB" run "$TFILE" 2>&1); MRC=$?
    else
      MOUT=$("$RB" "$TFILE" 2>&1); MRC=$?
    fi

    mv "$src.tg-mutant-bak" "$src"
    MUT_BACKUPS=""
    CHECKED=$((CHECKED+1))

    [ "$MRC" -eq 0 ] && SURVIVED="$SURVIVED$TFILE  (implementation $src deleted, suite still green)"$'\n'
  done <<< "$SRCS"

  if [ -n "$SURVIVED" ]; then
    printf '%s' "$SURVIVED" | show
    fail "tests survive mutation of the code they cover"
  fi
  echo "gate: mutation smoke ok ($CHECKED file(s) mutated, every suite went red)"
elif [ "${TG_MUTATE:-}" = "1" ]; then
  echo "gate: mutation smoke skipped (no test runner installed)"
fi

# ---------------------------------------------------------------- 7. verdict

echo
echo "GATE PASS"
exit 0
