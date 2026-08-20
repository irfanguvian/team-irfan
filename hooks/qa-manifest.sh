#!/usr/bin/env bash
# team-graph regression-manifest runner. Deterministic, zero LLM.
#
#   usage: qa-manifest.sh [<qa-dir>]        default: .team-irfan/qa
#
#   exit 0  →  REGRESSION PASS: <n> run, <n> skipped   (or: no manifest)
#   exit 1  →  REGRESSION FAIL: <failures listed>
#
# The manifest is the persistent QA suite: it only grows (QA appends new
# cases on ship), and ANY failure in it is a backward-compat break and a
# blocker — regardless of the new feature's own tests.
#
# Entry types, by path:
#   curl/<feature>.sh                → bash, exit-code honest
#   collections/<feature>.postman.json → newman when installed, else SKIP
#   browser/<feature>.md             → SKIP here (QA drives chrome-axi; a
#                                      shell cannot click)
# A manifest entry whose file is missing is a FAIL — a shrunken suite must be
# loud, since the suite shrinks only via the gate.

set -uo pipefail

QA_DIR="${1:-.team-irfan/qa}"
MANIFEST="$QA_DIR/regression.manifest"

if [ ! -f "$MANIFEST" ]; then
  echo "qa-manifest: no regression manifest at $MANIFEST — nothing to run"
  exit 0
fi

RUN=0; SKIP=0; FAILS=""

while IFS= read -r entry; do
  entry=$(printf '%s' "$entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$entry" in ''|'#'*) continue ;; esac
  path="$QA_DIR/$entry"
  if [ ! -f "$path" ]; then
    FAILS="$FAILS  MISSING  $entry"$'\n'
    continue
  fi
  case "$entry" in
    curl/*.sh)
      if OUT=$(bash "$path" 2>&1); then
        RUN=$((RUN+1)); echo "  PASS  $entry"
      else
        FAILS="$FAILS  FAIL  $entry"$'\n'"$(printf '%s\n' "$OUT" | tail -5 | sed 's/^/        /')"$'\n'
      fi ;;
    collections/*.postman.json)
      if command -v newman >/dev/null 2>&1; then
        if OUT=$(newman run "$path" 2>&1); then
          RUN=$((RUN+1)); echo "  PASS  $entry"
        else
          FAILS="$FAILS  FAIL  $entry"$'\n'"$(printf '%s\n' "$OUT" | tail -5 | sed 's/^/        /')"$'\n'
        fi
      else
        SKIP=$((SKIP+1)); echo "  SKIP  $entry (newman not installed — run the curl fallback)"
      fi ;;
    browser/*.md)
      SKIP=$((SKIP+1)); echo "  SKIP  $entry (browser checks run via chrome-axi, not a shell)" ;;
    *)
      FAILS="$FAILS  FAIL  $entry (unknown entry type)"$'\n' ;;
  esac
done < "$MANIFEST"

if [ -n "$FAILS" ]; then
  printf '%s' "$FAILS"
  echo
  echo "REGRESSION FAIL: a failing manifest entry is a backward-compat break"
  exit 1
fi
echo
echo "REGRESSION PASS: $RUN run, $SKIP skipped"
exit 0
