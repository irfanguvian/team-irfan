#!/usr/bin/env bash
# team-graph plan gate. Deterministic, zero LLM. Validates <run-dir>/plan.json
# before the single human plan-approval gate.
#
#   usage: plan-gate.sh <run-dir>
#
#   exit 0  →  PLAN GATE PASS
#   exit 1  →  PLAN GATE FAIL: <named reason>
#
# The orchestrator runs this and pastes the output BEFORE the approval
# question. A failing plan-gate sends PjM back to regenerate (max 2 attempts,
# then HAND-BACK with the error). The schema check is deterministic, so it
# lives here and never in a prompt.

set -uo pipefail

RUN_DIR="${1:-}"
[ -n "$RUN_DIR" ] || { echo "usage: plan-gate.sh <run-dir>" >&2; exit 2; }

PLAN="$RUN_DIR/plan.json"
[ -f "$PLAN" ] || { echo "PLAN GATE FAIL: plan.json missing at $PLAN"; exit 1; }

node -e '
  const fs = require("fs");
  const fail = m => { console.log("PLAN GATE FAIL: " + m); process.exit(1); };
  let p;
  try { p = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
  catch (e) { fail("plan.json is not valid JSON — " + e.message); }

  for (const k of ["goal","scope_folders","options","chosen_option_id","test_contract","run_cap"])
    if (!(k in p)) fail("missing field: " + k);

  if (typeof p.goal !== "string" || !p.goal.trim()) fail("goal is empty");

  if (!Array.isArray(p.scope_folders) || p.scope_folders.length === 0)
    fail("scope_folders is empty");

  if (!Array.isArray(p.options) || p.options.length < 1 || p.options.length > 3)
    fail("options count " + (Array.isArray(p.options) ? p.options.length : "not-a-list") + " (allowed 1-3)");

  for (const o of p.options) {
    for (const k of ["id","approach","files","risk","expected_calls"])
      if (!(k in o)) fail("option " + (o.id ?? "?") + " missing field: " + k);
    if (typeof o.expected_calls !== "number" || !isFinite(o.expected_calls))
      fail("expected_calls is not a number (option " + o.id + ")");
    if (!Array.isArray(o.files) || o.files.length === 0)
      fail("option " + o.id + " lists no files");
  }

  const chosen = p.options.find(o => o.id === p.chosen_option_id);
  if (!chosen) fail("chosen_option_id \"" + p.chosen_option_id + "\" not in options");

  const t = p.test_contract || {};
  if (!["backend-e2e","frontend-browser","both"].includes(t.type))
    fail("test_contract.type \"" + t.type + "\" not one of backend-e2e|frontend-browser|both");
  if (t.cases_source !== "plan")
    fail("test_contract.cases_source must be \"plan\", got \"" + t.cases_source + "\"");

  const want = Math.min(Math.round(chosen.expected_calls * 1.3), 60);
  if (p.run_cap !== want)
    fail("run_cap " + p.run_cap + " != computed " + want + " (min(round(" + chosen.expected_calls + " * 1.3), 60))");

  console.log("PLAN GATE PASS · goal ok · " + p.options.length + " option(s) · chosen " +
              chosen.id + " · run_cap " + p.run_cap);
' "$PLAN"
