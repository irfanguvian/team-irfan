#!/usr/bin/env python3
"""Prints the five hypotheses with verdicts, the per-task table, and the
pairwise-review win matrix. Reads results/results.csv and results/judgments/.
Cost and wall time appear in the footer, unscored — v3 proved that on saturated
tasks they are the only axis left, and that axis is not what v4 measures.

  report.py
"""
import csv
import glob
import json
import os
import statistics as st

H = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARMS = ["bare", "omc", "team"]
TASKS = ["Q1", "F1", "B1", "N5", "MEM-A", "MEM-B"]

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
  of team-irfan itself stays blocked below n=5, as in v3."""


def fnum(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def load_rows():
    path = os.path.join(H, "results", "results.csv")
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return list(csv.DictReader(f))


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
    print(f"  {claim}: {verdict.upper()}")
    for line in why:
        print(f"    - {line}")
    print()


def c1(rows):
    scored = [r for r in rows if r["task"] != "Q1"]
    if not scored:
        return verdict_line("C1 verify-driven reliability", "insufficient data", ["no scored rows"])
    why, fd = [], {}
    for arm in ARMS:
        arm_rows = by(scored, arm=arm)
        fd[arm] = rate(arm_rows, "false_done")
        why.append(f"{arm}: false_done {fd[arm]:.0%} of {len(arm_rows)} runs"
                   if fd[arm] is not None else f"{arm}: no runs")
    team_rows = by(scored, arm="team")
    skipped = [r for r in team_rows if r.get("verified_before_done") == "False"]
    why.append(f"team skipped verification on {len(skipped)} run(s)")
    if fd.get("team") is None or any(fd.get(a) is None for a in ("bare", "omc")):
        return verdict_line("C1 verify-driven reliability", "insufficient data", why)
    if skipped:
        return verdict_line("C1 verify-driven reliability", "falsified", why)
    if fd["team"] > 0 and fd["team"] >= min(fd["bare"], fd["omc"]):
        return verdict_line("C1 verify-driven reliability", "falsified", why)
    if fd["team"] == fd["bare"] == fd["omc"] == 0:
        why.append("all arms at zero false_done — checks redundant at this tier (see honesty note)")
    verdict_line("C1 verify-driven reliability", "holds", why)


def c2(rows):
    scored = [r for r in rows if r["task"] != "Q1"]
    team = by(scored, arm="team")
    if not team:
        return verdict_line("C2 plan-then-execute", "insufficient data", ["no team rows"])
    why = []
    for arm in ("bare", "omc"):
        arm_rows = by(scored, arm=arm)
        planless = sum(1 for r in arm_rows if r.get("plan_exists") != "True")
        if arm_rows:
            why.append(f"{arm}: did not plan on {planless}/{len(arm_rows)} runs "
                       "(null adherence reported as 'did not plan' — that IS claim C2)")
    adherence = [fnum(r["plan_adherence"]) for r in team]
    adherence = [a for a in adherence if a is not None]
    replans = [fnum(r["replans"]) or 0 for r in team]
    med = st.median(adherence) if adherence else None
    why.append(f"team: plan on {sum(1 for r in team if r.get('plan_exists') == 'True')}/{len(team)} runs, "
               f"median adherence {med if med is None else f'{med:.2f}'}, "
               f"max replans/task {max(replans):.0f}")
    if not adherence:
        return verdict_line("C2 plan-then-execute", "insufficient data", why)
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
    scored = [r for r in rows if r["task"] != "Q1"]
    team = by(scored, arm="team")
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
        return verdict_line("C3 predictable effort", "insufficient data", why)
    wider = (spreads["team"] is not None
             and all(spreads[a] is not None and spreads["team"] > spreads[a] for a in ("bare", "omc")))
    if st.median(errs) > 0.30 or wider:
        return verdict_line("C3 predictable effort", "falsified", why)
    verdict_line("C3 predictable effort", "holds", why)


def c4(rows):
    a_rows, b_rows = by(rows, task="MEM-A"), by(rows, task="MEM-B")
    if not a_rows or not b_rows:
        return verdict_line("C4 memory", "insufficient data", ["MEM pair not run"])
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
    holes = []
    for p in glob.glob(os.path.join(H, "results", "judgments", "same-hole-team-*.json")):
        holes.append(json.load(open(p)))
    hole_hit = any(h.get("same_hole") is True for h in holes)
    if holes:
        why.append(f"team same_hole: {[h.get('same_hole') for h in holes]}"
                   " (session A's retro recorded the band-aid — repeating it = fail)")
    else:
        why.append("team same_hole: not judged yet (bin/judge.sh all)")
    if team_discount is None:
        return verdict_line("C4 memory", "insufficient data", why)
    if not team_discount or hole_hit:
        return verdict_line("C4 memory", "falsified", why)
    verdict_line("C4 memory", "holds", why)


def load_judgments():
    out = []
    for p in glob.glob(os.path.join(H, "results", "judgments", "*-vs-*.json")):
        try:
            out.append(json.load(open(p)))
        except json.JSONDecodeError:
            pass
    return out


def c5(judgments):
    if not judgments:
        return verdict_line("C5 generated quality", "insufficient data",
                            ["no judgments — bin/judge.sh --calibrate && bin/judge.sh all"])
    why, falsified = [], False
    for baseline in ("bare", "omc"):
        for task in TASKS:
            js = [j for j in judgments if j["task"] == task and set(j["arms"]) == {baseline, "team"}]
            if not js:
                continue
            w = sum(1 for j in js if j["winner"] == "team")
            l = sum(1 for j in js if j["winner"] == baseline)
            t = len(js) - w - l
            why.append(f"{task} team vs {baseline}: {w}W {t}T {l}L")
            if l > w and l > len(js) / 2:
                falsified = True
    verdict_line("C5 generated quality", "falsified" if falsified else "holds", why)


def table(rows):
    print("## Per-task table (cost/wall reported, NOT scored)\n")
    hdr = f"{'task':7} {'arm':5} {'n':>2} {'pass':>6} {'false_done':>10} {'verified':>8} {'plan':>5} {'cost$':>7} {'wall_s':>7}"
    print(hdr)
    print("-" * len(hdr))
    for task in TASKS:
        for arm in ARMS:
            rs = by(rows, task=task, arm=arm)
            if not rs:
                continue
            pr = [fnum(r["pass_rate"]) or 0 for r in rs]
            cost = [fnum(r["cost_usd"]) or 0 for r in rs]
            wall = [fnum(r["wall_sec"]) or 0 for r in rs]
            fd = rate(rs, "false_done") or 0
            ver = sum(1 for r in rs if r.get("verified_before_done") == "True")
            plan = sum(1 for r in rs if r.get("plan_exists") == "True")
            print(f"{task:7} {arm:5} {len(rs):>2} {st.mean(pr):>6.2f} {fd:>10.0%} "
                  f"{ver:>7}/{len(rs)} {plan:>4}/{len(rs)} {st.mean(cost):>7.2f} {st.mean(wall):>7.0f}")
    print("\nCost and wall time are context, not verdict: the one cost claim v4"
          "\nscores is C3 (predictability) and the C4 second-session discount.\n")


def main():
    rows = load_rows()
    print("# Harness v4 report — five hypotheses\n")
    if not rows:
        print("no scored rows yet — bin/score.sh all first\n")
    print("## Verdicts\n")
    c1(rows)
    c2(rows)
    c3(rows)
    c4(rows)
    c5(load_judgments())
    if rows:
        table(rows)
    print(HONESTY)


if __name__ == "__main__":
    main()
