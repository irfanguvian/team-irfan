#!/usr/bin/env bash
# Freezes the current results into one folder that is safe to read months later.
#
#   publish.sh 2026-08-18-partial
#
# Writes results/<label>/ with the CSV, a median table, and a note of which cells
# are missing. Everything else in runs/ is transcripts and worktree paths that go
# stale; this folder is the part worth keeping.
set -euo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
label="${1:?usage: publish.sh <label>}"
out="$H/results/$label"
mkdir -p "$out"
cp "$H/runs/results.csv" "$out/results.csv"
"$H/bin/status.sh" > "$out/COVERAGE.txt" || true   # status.sh exits 1 on an incomplete matrix; coverage is still worth freezing
python3 "$H/bin/summarize.py" "$out/results.csv" "$label" > "$out/SUMMARY.md"
echo "published: $out"
ls -1 "$out"
