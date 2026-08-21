#!/usr/bin/env python3
"""Prints the five hypotheses with verdicts, the per-task table, and the
pairwise-review win matrix. Cost and wall time appear in the footer, unscored —
v3 proved that on saturated tasks they are the only axis left, and that axis is
not what v4 measures.

  report.py [--tier sonnet-low]      default: $BENCH_TIER, else $BENCH_MODEL +
                                     $BENCH_EFFORT, else sonnet-low
  report.py --tier opus-legacy       the pre-tier opus run: results/results.csv,
                                     results/judgments/, results/opus-legacy.infra.json

Two rules this file exists to enforce:

1. **Only valid cells vote.** A cell whose meta said INFRA_FAIL, or whose team
   run routed to a pipeline with no driver heartbeat, measured the harness and
   not the arm. score.sh marks those `validity=infra`; every verdict below sees
   the filtered rows only. The validity block at the top says exactly how many
   were dropped and why, so a thin result cannot look like a clean one.
2. **Below MIN_N there is no verdict.** Not HOLDS, not FALSIFIED —
   INSUFFICIENT DATA, naming the arm and the count. MIN_N comes from the round
   counts in SPEC §3, not from what happened to survive.

The report is written to <results-tier>/REPORT-<date>.md and printed.
"""
import argparse
import csv
import datetime
import glob
import json
import os
import statistics as st

H = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARMS = ["bare", "omc", "team"]
TASKS = ["Q1", "F1", "B1", "N5", "MEM-A", "MEM-B"]
SCORED = [t for t in TASKS if t != "Q1"]   # Q1 is a question; it is not graded

# SPEC §3: 3 rounds for Q1/F1/B1, 2 for N5 and the MEM pair.
ROUNDS = {"N5": 2, "MEM-A": 2, "MEM-B": 2}


def rounds_for(task):
    return ROUNDS.get(task, 3)


# MIN_N — the smallest evidence base each claim may be decided on, derived from
# the planned round counts rather than from what happened to survive: all scored
# cells for one arm (12 = F1 3 + B1 3 + N5 2 + MEM-A 2 + MEM-B 2), minus one
# short task's worth of slack. Below that an arm's rate is noise, and the answer
# is INSUFFICIENT DATA — never a verdict.
MIN_SCORED_PER_ARM = sum(rounds_for(t) for t in SCORED) - 3   # = 8

HONESTY = """\
## Honesty section (verbatim, per the spec)

- Arm C's plan gate is auto-approved; the measured system is team-irfan
  WITHOUT its human check.
- The quality reviewer is an LLM. It passed calibration on N planted pairs;
  its verdicts are pairwise and blind, but it is not a human reviewer and
  a systematic style preference could survive calibration.
- The memory comparison is asymmetric BY DESIGN — it measures a capability
  the baselines don't have, on identical inputs.
- If C1 and C5 come back tied at the opus tier, the honest conclusion is that
  at this model tier and fixture size, the harness's checks are redundant —
  run the sonnet tier before concluding anything.
- n per cell is 2-3. Direct run review is valid at any n; aggregate tuning
  of team-irfan itself stays blocked below n=5, as in v3.
- INFRA_FAIL cells are excluded from every verdict and listed with reason; a
  verdict is INSUFFICIENT DATA below the SPEC round counts."""

LINES = []


def P(s=""):
    LINES.append(s)
    print(s)


# ------------------------------------------------------------------ plumbing
def tier_from_model(model, effort):
    m = model[len("claude-"):] if model.startswith("claude-") else model
    for short in ("sonnet", "haiku", "opus", "fable"):
        if m.startswith(short):
            m = short
            break
    else:
        m = m.split("-")[0]
    return f"{m}-{effort}"


def resolve_tier(arg):
    if arg:
        return arg
    if os.environ.get("BENCH_TIER"):
        return os.environ["BENCH_TIER"]
    return tier_from_model(os.environ.get("BENCH_MODEL", "claude-sonnet-5"),
                           os.environ.get("BENCH_EFFORT", "low"))


def tier_paths(tier):
    if tier == "opus-legacy":
        return os.path.join(H, "runs"), os.path.join(H, "results")
    return os.path.join(H, "runs", tier), os.path.join(H, "results", tier)


def fnum(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def load_sidecar(res):
    """Infra cells recorded out-of-band, for a CSV written before validity existed."""
    path = os.path.join(res, "opus-legacy.infra.json")
    if not os.path.exists(path):
        return {}, ""
    doc = json.load(open(path))
    cells = doc.get("cells", doc) if isinstance(doc, dict) else doc
    note = doc.get("note", "") if isinstance(doc, dict) else ""
    return {(c["task"], c["arm"], str(c["round"])): c.get("reason", "infra")
            for c in cells}, note


# score.sh emits these through jq's tostring: "true"/"false"/"null", lowercase.
# Python's own str(bool) is not, and comparing against "True" here silently made
# C1's verification branch unreachable once already (review, 2026-08-21).
BOOLISH = ("verified_before_done", "claims_done", "false_done", "plan_exists")


def load_rows(res):
    path = os.path.join(res, "results.csv")
    if not os.path.exists(path):
        return [], ""
    with open(path) as f:
        rows = list(csv.DictReader(f))
    # one row per cell, last write wins — score.sh dedupes too; this is the
    # belt to its braces, for a CSV assembled by hand or by an older scorer.
    dedup = {}
    for r in rows:
        dedup[(r["task"], r["arm"], r["round"])] = r
    rows = list(dedup.values())
    for r in rows:
        for k in BOOLISH:
            if r.get(k):
                r[k] = r[k].strip().lower()
    sidecar, note = load_sidecar(res)
    for r in rows:
        key = (r["task"], r["arm"], r["round"])
        if key in sidecar:
            r["validity"] = "infra"
            r["reason"] = sidecar[key]
            r["cell_status"] = "INFRA_FAIL"
        elif not r.get("validity"):
            # a pre-validity CSV: absence of evidence of infra failure is the
            # only thing it can tell us, so the row counts.
            r["validity"] = "valid"
    return rows, note


def by(rows, **kw):
    out = rows
    for k, v in kw.items():
        out = [r for r in out if r.get(k) == v]
    return out


def rate(rows, field, value="true"):
    if not rows:
        return None
    return sum(1 for r in rows if r.get(field) == value) / len(rows)


def verdict_line(claim, verdict, why):
    P(f"  {claim}: {verdict.upper()}")
    for line in why:
        P(f"    - {line}")
    P()


def insufficient(claim, why):
    return verdict_line(claim, "insufficient data", why)


# ------------------------------------------------------------------- verdicts
def c1(rows):
    """FALSIFIED if team's false_done rate >= any baseline, or it skipped
    verification on any run. (SPEC §1 C1 — unchanged.)"""
    scored = [r for r in rows if r["task"] in SCORED]
    counts = {a: len(by(scored, arm=a)) for a in ARMS}
    thin = [f"{a} n={counts[a]}" for a in ARMS if counts[a] < MIN_SCORED_PER_ARM]
    if thin:
        return insufficient("C1 verify-driven reliability",
                            [f"valid scored rows below MIN_N={MIN_SCORED_PER_ARM}: "
                             + ", ".join(thin)])
    why, fd = [], {}
    for arm in ARMS:
        arm_rows = by(scored, arm=arm)
        fd[arm] = rate(arm_rows, "false_done")
        why.append(f"{arm}: false_done {fd[arm]:.0%} of {len(arm_rows)} valid runs")
    team_rows = by(scored, arm="team")
    skipped = [r for r in team_rows if r.get("verified_before_done") == "false"]
    why.append(f"team skipped verification on {len(skipped)} run(s)")
    if skipped:
        return verdict_line("C1 verify-driven reliability", "falsified", why)
    if fd["team"] > 0 and fd["team"] >= min(fd["bare"], fd["omc"]):
        return verdict_line("C1 verify-driven reliability", "falsified", why)
    if fd["team"] == fd["bare"] == fd["omc"] == 0:
        why.append("all arms at zero false_done — checks redundant at this tier (see honesty note)")
    verdict_line("C1 verify-driven reliability", "holds", why)


def team_min_n(rows, claim):
    """C2/C3 are claims about team's own behaviour: enough scored rows, and at
    least one N5 — the task the claims were designed around."""
    scored = [r for r in rows if r["task"] in SCORED]
    team = by(scored, arm="team")
    n5 = by(team, task="N5")
    if len(team) < MIN_SCORED_PER_ARM or not n5:
        insufficient(claim, [f"team valid scored rows n={len(team)} "
                             f"(MIN_N={MIN_SCORED_PER_ARM}), valid N5 rows n={len(n5)} (MIN_N=1)"])
        return None
    return team


def c2(rows):
    """FALSIFIED if adherence < 0.8, or more than one replan per task."""
    team = team_min_n(rows, "C2 plan-then-execute")
    if team is None:
        return
    scored = [r for r in rows if r["task"] in SCORED]
    why = []
    for arm in ("bare", "omc"):
        arm_rows = by(scored, arm=arm)
        planless = sum(1 for r in arm_rows if r.get("plan_exists") != "true")
        if arm_rows:
            why.append(f"{arm}: did not plan on {planless}/{len(arm_rows)} runs "
                       "(null adherence reported as 'did not plan' — that IS claim C2)")
    adherence = [fnum(r["plan_adherence"]) for r in team]
    adherence = [a for a in adherence if a is not None]
    replans = [fnum(r["replans"]) or 0 for r in team]
    med = st.median(adherence) if adherence else None
    why.append(f"team: plan on {sum(1 for r in team if r.get('plan_exists') == 'true')}/{len(team)} runs, "
               f"median adherence {med if med is None else f'{med:.2f}'}, "
               f"max replans/task {max(replans):.0f}")
    if not adherence:
        return insufficient("C2 plan-then-execute", why)
    if med < 0.8 or max(replans) > 1:
        return verdict_line("C2 plan-then-execute", "falsified", why)
    verdict_line("C2 plan-then-execute", "holds", why)


def spread(rows):
    """mean over tasks of (stdev/median) of cost across rounds"""
    vals = []
    for t in TASKS:
        costs = [fnum(r["cost_usd"]) for r in by(rows, task=t)]
        costs = [c for c in costs if c]
        if len(costs) >= 2 and st.median(costs) > 0:
            vals.append(st.pstdev(costs) / st.median(costs))
    return st.mean(vals) if vals else None


def c3(rows):
    """FALSIFIED if median |prediction error| > 30%, or cost spread wider than
    both baselines."""
    team = team_min_n(rows, "C3 predictable effort")
    if team is None:
        return
    scored = [r for r in rows if r["task"] in SCORED]
    errs = [fnum(r["prediction_error"]) for r in team]
    errs = [abs(e) for e in errs if e is not None]
    why = []
    if errs:
        why.append(f"team: median |prediction error| {st.median(errs):.0%} over {len(errs)} predicted runs")
    else:
        why.append("team: no predicted_calls found in any plan")
    spreads = {a: spread(by(scored, arm=a)) for a in ARMS}
    for a in ARMS:
        why.append(f"{a}: cost spread {spreads[a]:.2f}" if spreads[a] is not None
                   else f"{a}: cost spread n/a")
    capped = [r for r in team if r["status"].startswith("capped")]
    if capped:
        why.append(f"team hit the cap on {len(capped)} run(s) — that IS a C3 result")
    if not errs:
        return insufficient("C3 predictable effort", why)
    wider = (spreads["team"] is not None
             and all(spreads[a] is not None and spreads["team"] > spreads[a] for a in ("bare", "omc")))
    if st.median(errs) > 0.30 or wider:
        return verdict_line("C3 predictable effort", "falsified", why)
    verdict_line("C3 predictable effort", "holds", why)


def c4(rows, res):
    """FALSIFIED if session B is neither cheaper nor faster to locate than
    session A, or it repeats the mistake session A's retro recorded."""
    a_rows, b_rows = by(rows, task="MEM-A"), by(rows, task="MEM-B")
    incomplete = []
    for arm in ARMS:
        ra = {r["round"] for r in by(a_rows, arm=arm)}
        rb = {r["round"] for r in by(b_rows, arm=arm)}
        if not ra & rb:
            incomplete.append(f"{arm} (A rounds {sorted(ra) or '-'}, B rounds {sorted(rb) or '-'})")
    if incomplete:
        return insufficient("C4 memory",
                            ["no round with both MEM-A and MEM-B valid for: "
                             + "; ".join(incomplete)])
    why, team_discount = [], None
    for arm in ARMS:
        ac = [fnum(r["cost_usd"]) for r in by(a_rows, arm=arm)]
        bc = [fnum(r["cost_usd"]) for r in by(b_rows, arm=arm)]
        al = [fnum(r["calls_to_locate"]) for r in by(a_rows, arm=arm)]
        bl = [fnum(r["calls_to_locate"]) for r in by(b_rows, arm=arm)]
        ac, bc = [x for x in ac if x], [x for x in bc if x]
        al, bl = [x for x in al if x], [x for x in bl if x]
        if not ac or not bc:
            why.append(f"{arm}: incomplete pair")
            continue
        cheaper = st.median(bc) < st.median(ac)
        faster = bool(al and bl and st.median(bl) < st.median(al))
        why.append(f"{arm}: session B cost {st.median(bc):.2f} vs A {st.median(ac):.2f}"
                   f" ({'cheaper' if cheaper else 'NOT cheaper'}), locate "
                   f"{st.median(bl) if bl else '?'} vs {st.median(al) if al else '?'}"
                   f" ({'faster' if faster else 'NOT faster'})")
        if arm == "team":
            team_discount = cheaper or faster
    # same-hole is a grep over markers, not a judgment (bin/same-hole.sh)
    valid_b_rounds = {r["round"] for r in by(b_rows, arm="team")}
    holes = []
    for p in sorted(glob.glob(os.path.join(res, "same-hole", "team-r*.json"))):
        try:
            h = json.load(open(p))
        except json.JSONDecodeError:
            continue
        if str(h.get("round")) in valid_b_rounds:
            holes.append(h)
    hole_hit = any(h.get("same_hole") and h.get("retro_recorded") for h in holes)
    if holes:
        why.append("team same_hole: "
                   + ", ".join(f"r{h.get('round')} hole={h.get('same_hole')}"
                               f"/retro={h.get('retro_recorded')}" for h in holes)
                   + " (a hit needs both: A's retro recorded the band-aid AND B repeated it)")
    else:
        why.append("team same_hole: not checked on any valid round (bin/same-hole.sh all)")
    if team_discount is None:
        return insufficient("C4 memory", why)
    if not team_discount or hole_hit:
        return verdict_line("C4 memory", "falsified", why)
    verdict_line("C4 memory", "holds", why)


def load_judgments(res, valid_keys):
    """A pairwise judgment is only evidence if BOTH cells it compared are valid."""
    out, dropped = [], 0
    for p in sorted(glob.glob(os.path.join(res, "judgments", "*-vs-*.json"))):
        try:
            j = json.load(open(p))
        except json.JSONDecodeError:
            continue
        if all((j["task"], arm, str(j["round"])) in valid_keys for arm in j["arms"]):
            out.append(j)
        else:
            dropped += 1
    return out, dropped


def c5(judgments, dropped):
    """FALSIFIED if team loses the pairwise majority against either baseline on
    any task. A pairing decided on one judgment is not a majority — MIN_N=2."""
    why, falsified, decided, thin = [], False, 0, []
    for baseline in ("bare", "omc"):
        for task in TASKS:
            js = [j for j in judgments if j["task"] == task and set(j["arms"]) == {baseline, "team"}]
            if not js:
                continue
            if len(js) < 2:
                thin.append(f"{task} team vs {baseline} (n={len(js)})")
                continue
            decided += 1
            w = sum(1 for j in js if j["winner"] == "team")
            l = sum(1 for j in js if j["winner"] == baseline)
            t = len(js) - w - l
            why.append(f"{task} team vs {baseline}: {w}W {t}T {l}L")
            if l > w and l > len(js) / 2:
                falsified = True
    if dropped:
        why.append(f"{dropped} judgment(s) dropped — one side of the pairing was an infra cell")
    if thin:
        why.append("pairings below MIN_N=2, not decided: " + "; ".join(thin))
    if not decided:
        return insufficient("C5 generated quality",
                            why or ["no judgments — bin/judge.sh --calibrate && bin/judge.sh all"])
    verdict_line("C5 generated quality", "falsified" if falsified else "holds", why)


# --------------------------------------------------------------------- blocks
def validity_block(all_rows, note):
    P("## Validity\n")
    hdr = f"{'arm':6} {'valid':>6} {'infra':>6} {'total':>6}"
    P(hdr)
    P("-" * len(hdr))
    for arm in ARMS:
        rs = by(all_rows, arm=arm)
        infra = [r for r in rs if r["validity"] == "infra"]
        P(f"{arm:6} {len(rs) - len(infra):>6} {len(infra):>6} {len(rs):>6}")
    infra_rows = [r for r in all_rows if r["validity"] == "infra"]
    P()
    if infra_rows:
        P("Infra cells (excluded from every verdict below):\n")
        for r in infra_rows:
            P(f"  - {r['task']}/{r['arm']}/r{r['round']} — {r.get('reason') or 'infra'}")
        P()
    else:
        P("No infra cells: every run measured the arm, not the harness.\n")
    if note:
        P(f"> {note}\n")


def table(rows):
    P("## Per-task table — valid cells only (cost/wall reported, NOT scored)\n")
    hdr = (f"{'task':7} {'arm':5} {'n':>2} {'pass':>6} {'false_done':>10} "
           f"{'verified':>8} {'plan':>5} {'cost$':>7} {'wall_s':>7}")
    P(hdr)
    P("-" * len(hdr))
    for task in TASKS:
        for arm in ARMS:
            rs = by(rows, task=task, arm=arm)
            if not rs:
                continue
            pr = [fnum(r["pass_rate"]) or 0 for r in rs]
            cost = [fnum(r["cost_usd"]) or 0 for r in rs]
            wall = [fnum(r["wall_sec"]) or 0 for r in rs]
            fd = rate(rs, "false_done") or 0
            ver = sum(1 for r in rs if r.get("verified_before_done") == "true")
            plan = sum(1 for r in rs if r.get("plan_exists") == "true")
            P(f"{task:7} {arm:5} {len(rs):>2} {st.mean(pr):>6.2f} {fd:>10.0%} "
              f"{ver:>7}/{len(rs)} {plan:>4}/{len(rs)} {st.mean(cost):>7.2f} {st.mean(wall):>7.0f}")
    P("\nCost and wall time are context, not verdict: the one cost claim v4"
      "\nscores is C3 (predictability) and the C4 second-session discount.\n")


def failure_modes(all_rows):
    modes = {}
    for r in all_rows:
        m = r.get("failure_mode")
        if m:
            modes.setdefault(m, []).append(f"{r['task']}/{r['arm']}/r{r['round']}")
    if not modes:
        return
    P("## Failure modes\n")
    for m in sorted(modes):
        P(f"  {m}: {len(modes[m])} — {', '.join(modes[m])}")
    P()


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--tier", default=None)
    args = ap.parse_args()
    tier = resolve_tier(args.tier)
    _runs, res = tier_paths(tier)

    all_rows, note = load_rows(res)
    matrix = {}
    mpath = os.path.join(res, "matrix.json")
    if os.path.exists(mpath):
        try:
            matrix = json.load(open(mpath))
        except json.JSONDecodeError:
            matrix = {}

    P(f"# Harness v4 report — five hypotheses — tier `{tier}`\n")
    if matrix:
        P(f"Run started {matrix.get('started_at', '?')} · sha `{matrix.get('git_sha', '?')}`"
          f" · plugin {matrix.get('plugin_version', '?')} · model {matrix.get('model', '?')}"
          f" · effort {matrix.get('effort', '?')} · judge {matrix.get('judge_model', '?')}\n")
    if not all_rows:
        P(f"no scored rows in {os.path.join(res, 'results.csv')} — bin/score.sh all first\n")

    validity_block(all_rows, note)

    rows = [r for r in all_rows if r["validity"] == "valid"]
    valid_keys = {(r["task"], r["arm"], r["round"]) for r in rows}
    judgments, dropped = load_judgments(res, valid_keys)

    P("## Verdicts\n")
    c1(rows)
    c2(rows)
    c3(rows)
    c4(rows, res)
    c5(judgments, dropped)
    if rows:
        table(rows)
    failure_modes(all_rows)
    lanes = matrix.get("lanes")
    if lanes and int(lanes) > 1:
        P(f"> wall_s measured under concurrent load ({lanes} lanes) — one lane per arm,"
          f"\n> sequential within an arm. Wall time is comparable across arms, not to a"
          f"\n> single-lane run.\n")
    P(HONESTY)

    when = (matrix.get("started_at") or "")[:10].replace("-", "") \
        or datetime.date.today().strftime("%Y%m%d")
    os.makedirs(res, exist_ok=True)
    out = os.path.join(res, f"REPORT-{when}.md")
    prior = sorted(glob.glob(os.path.join(res, "REPORT-*.md")))
    if tier == "opus-legacy" and prior:
        # the legacy report is a record of what was concluded on 08-20, not an
        # output of this script; re-reading its CSV must not add a second one.
        out = os.path.abspath(prior[0])
        print(f"\n(not rewritten — {os.path.basename(out)} is the legacy record)")
    else:
        with open(out, "w") as f:
            f.write("\n".join(LINES) + "\n")
    # run.sh captures this for results/<tier>/DONE — keep it last, keep the shape.
    print(f"report: {os.path.abspath(out)}")


if __name__ == "__main__":
    main()
