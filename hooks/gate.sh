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

is_test_path() {
  case "$1" in
    *.test.*|*.spec.*|*/__tests__/*|test/*|tests/*|*/test/*|*/tests/*) return 0 ;;
    *) return 1 ;;
  esac
}

TEST_FILES=""
if [ "${TG_SCAN:-}" = "all" ]; then
  TEST_FILES=$(find . -type d -name node_modules -prune -o \
                    -type f \( -name '*.test.*' -o -name '*.spec.*' \) -print 2>/dev/null | sort)
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

# ------------------------------------------------- 3+4. unit tests, coverage

COV_BASE="${TG_RUN:-}/coverage-base.txt"
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
  cp "$SUMMARY" "$COV_BASE"
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

# ---------------------------------------------------------------- 6. verdict

echo
echo "GATE PASS"
exit 0
