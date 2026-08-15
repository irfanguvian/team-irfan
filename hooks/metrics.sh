#!/usr/bin/env bash
# Write runs/<id>/metrics.json from command-sourced facts. Zero self-assessment.
#
#   usage: metrics.sh <run-dir> <route> <tool_calls> <budget> [key=value ...]
#
#   keys: folders, context_maps_used, maps_refreshed, human_overrides  (comma-separated lists)
#         gate_fails  (semicolon-separated "stage:reason" pairs)
#         retries, escalated, shipped
#
# over_budget is derived, never passed. retries comes from retries.json when it
# exists — a number typed by an agent is a number an agent can flatter.

set -uo pipefail

RUN_DIR="${1:-}"; ROUTE="${2:-}"; CALLS="${3:-0}"; BUDGET="${4:-0}"; shift 4 2>/dev/null || true

[ -z "$RUN_DIR" ] || [ -z "$ROUTE" ] && { echo "usage: metrics.sh <run-dir> <route> <tool_calls> <budget> [k=v ...]" >&2; exit 2; }

mkdir -p "$RUN_DIR"

# retries: authoritative source is retry-guard's own state file
RETRIES=0
if [ -f "$RUN_DIR/retries.json" ]; then
  RETRIES=$(node -e '
    try { const s = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
          console.log(Object.values(s).reduce((a,b)=>a+b,0)); }
    catch { console.log(0); }' "$RUN_DIR/retries.json" 2>/dev/null || echo 0)
fi

# key=value pairs go through as separate argv entries, never as one
# whitespace-joined string — a reason like "unit tests:boundary case" has
# spaces in it and splitting on whitespace silently truncates the record.
TG_RUN_ID="$(basename "$RUN_DIR")" TG_ROUTE="$ROUTE" \
TG_CALLS="$CALLS" TG_BUDGET="$BUDGET" TG_RETRIES="$RETRIES" \
node -e '
  const fs = require("fs");
  const kv = {};
  for (const pair of process.argv.slice(2)) {
    const i = pair.indexOf("=");
    if (i > 0) kv[pair.slice(0, i)] = pair.slice(i + 1);
  }
  const list = k => (kv[k] || "").split(",").map(s => s.trim()).filter(Boolean);
  const bool = k => kv[k] === "true" || kv[k] === "1";
  const calls = Number(process.env.TG_CALLS) || 0;
  const budget = Number(process.env.TG_BUDGET) || 0;

  const out = {
    id: process.env.TG_RUN_ID,
    date: kv.date || new Date().toISOString().slice(0, 10),
    route: process.env.TG_ROUTE,
    folders: list("folders"),
    tool_calls: calls,
    budget,
    over_budget: budget > 0 && calls > budget,
    gate_fails: (kv.gate_fails || "").split(";").filter(Boolean).map(p => {
      const i = p.indexOf(":");
      return i > 0 ? { stage: p.slice(0, i), reason: p.slice(i + 1) }
                   : { stage: p, reason: "" };
    }),
    retries: Number(process.env.TG_RETRIES) || 0,
    escalated: bool("escalated"),
    context_maps_used: list("context_maps_used"),
    maps_refreshed: list("maps_refreshed"),
    human_overrides: list("human_overrides"),
    shipped: bool("shipped"),
  };
  const file = process.argv[1];
  fs.writeFileSync(file + ".tmp", JSON.stringify(out, null, 2) + "\n");
  fs.renameSync(file + ".tmp", file);
  console.log(`metrics → ${file} · route=${out.route} calls=${out.tool_calls}/${out.budget}` +
              (out.over_budget ? " OVER" : "") + ` retries=${out.retries}` +
              ` gate_fails=${out.gate_fails.length}`);
' "$RUN_DIR/metrics.json" "$@"
