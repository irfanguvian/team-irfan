# Test cases — <feature>

run: <yyyymmdd-slug>
author: QA
source: plan.json ONLY — no diff, no worktree was read
type: backend-e2e | frontend-browser | both

<every case traces to a plan.json goal or scope item. a case asserting nothing
— status-only with no body/effect check, or expect(true)-style — is forbidden
and fails the gate.>

## Backend cases (executable, copy-pasteable)

### CASE-1 — <behavior asserted, one line>

- source: <plan.json goal | scope item>
- command:
  ```bash
  curl -s -i http://127.0.0.1:3000/api/thing -H 'content-type: application/json' -d '{"id":1}'
  ```
- expect_status: 200
- expect_body: <exact field = exact value, or decisive substring>

## Frontend cases (browser)

<steps invoke the `chrome-devtools-axi` skill, the way `skills/guardrails` is
referenced. skill absent at runtime → QA writes the steps as a manual
checklist and SAYS SO — never fake browser output.>

### CASE-2 — <behavior asserted, one line>

- source: <plan.json goal | scope item>
- steps: <navigate, act, observe — via chrome-devtools-axi>
- expect_effect: <visible outcome, exact — element text, url, state change>
