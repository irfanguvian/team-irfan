# Report — <feature>

run: <yyyymmdd-slug>

**Done:** <what was completed. files and behavior, named. bullets.>

**Fine or not:** <concerns. contract changes, ponytail shortcuts, tests
rewritten in slop review, guardrail findings left unfixed, anything unverified.
"clean" only if genuinely clean.>

**Blockers:** <what needs Irfan. breaking changes ALWAYS land here. or "none">

**Next:** <the obvious follow-up, or "nothing">

## Ship checklist

Every box is a fact with evidence in this run directory, not a self-assessment.
An unchecked box is a blocker, not a caveat.

- [ ] `gate.sh` output pasted — every task, `GATE PASS`
- [ ] tester evidence attached — real command output in each `test-report-<id>.md`
- [ ] `docs/REGISTRY.md` updated in the merge commit (FEAT/MOD/STATUS/DEC)
- [ ] forbidden-actions clean — no push, no deploy, no CI trigger, no secret
      read, no destructive migration
- [ ] terminus is a **local merge commit** — nothing pushed, nothing deployed
- [ ] awaiting Irfan's sign-off ← **the workflow stops here**

---

<gate output and test-report verdicts, pasted>

**Verdict:** shipped | partial | blocked | reverted | abandoned — <one line:
what a future session needs to know, including what was deliberately left
undone.>
