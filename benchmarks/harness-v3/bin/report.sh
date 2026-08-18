#!/usr/bin/env bash
# Reads runs/results.csv and prints the report from section 8 of the spec.
# Medians, not means — with n=3 the median is the honest summary.
#
#   report.sh              markdown to stdout
#   report.sh > REPORT.md
set -euo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$H/bin/report.py" "$H/runs/results.csv"
