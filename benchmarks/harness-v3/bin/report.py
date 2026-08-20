"""Turns results.csv into the report. No judgement calls live here: the winner
rule and the four kill criteria are transcribed straight from the spec, so the
verdict cannot quietly move after seeing the numbers."""
import csv, statistics, sys
from collections import defaultdict

ARMS = ["bare", "omc", "team"]
LABEL = {"bare": "A bare", "omc": "B omc", "team": "C team-irfan"}

def med(xs):
    return statistics.median(xs) if xs else 0.0

def main(path):
    rows = list(csv.DictReader(open(path)))
    if not rows:
        sys.exit("results.csv is empty — run bin/score.sh all first")

    cells = defaultdict(list)
    for r in rows:
        cells[(r["task"], r["arm"])].append(r)

    tasks = sorted({r["task"] for r in rows})
    print("## Results\n")
    print("| Task | Arm | pass (med) | $ (med) | wall (med) | oos files | spread |")
    print("|------|-----|-----------|---------|-----------|-----------|--------|")

    stat = {}
    for t in tasks:
        for a in ARMS:
            rs = cells.get((t, a))
            if not rs:
                continue
            pr = med([float(r["pass_rate"]) for r in rs])
            cost = [float(r["cost_usd"]) for r in rs]
            wall = med([float(r["wall_sec"]) for r in rs])
            oos = sum(int(r["oos_files"]) for r in rs)
            lo = min(c for c in cost if c > 0) if any(c > 0 for c in cost) else 0
            spread = (max(cost) / lo) if lo else 0
            stat[(t, a)] = dict(pass_rate=pr, cost=med(cost), wall=wall,
                                oos=oos, spread=spread, n=len(rs))
            print(f"| {t} | {LABEL[a]} | {pr:.0%} | ${med(cost):.3f} | "
                  f"{wall:.0f}s | {oos} | {spread:.2f}x |")

    # ---- winner per task ---------------------------------------------------
    print("\n### Winner per task\n")
    winners = {}
    for t in tasks:
        have = [a for a in ARMS if (t, a) in stat]
        if not have:
            continue
        best = max(stat[(t, a)]["pass_rate"] for a in have)
        tied = [a for a in have if stat[(t, a)]["pass_rate"] == best]
        if len(tied) > 1:
            cheapest = min(stat[(t, a)]["cost"] for a in tied)
            tied = [a for a in tied if stat[(t, a)]["cost"] == cheapest]
        if len(tied) > 1:
            fastest = min(stat[(t, a)]["wall"] for a in tied)
            tied = [a for a in tied if stat[(t, a)]["wall"] == fastest]
        winners[t] = tied
        print(f"- **{t}**: {', '.join(LABEL[a] for a in tied)} "
              f"(pass {best:.0%})")

    # ---- hypotheses --------------------------------------------------------
    def verdict(ok):
        return "PASS" if ok else "FAIL"

    print("\n### Hypotheses\n")

    # H1 — team wins or ties everywhere, strictly better on the traps.
    h1_lose = [t for t in tasks
               if (t, "team") in stat
               and stat[(t, "team")]["pass_rate"] <
                   max(stat[(t, a)]["pass_rate"] for a in ARMS if (t, a) in stat)]
    traps = [t for t in ("T3", "T4") if (t, "team") in stat]
    h1_traps = all(
        stat[(t, "team")]["pass_rate"] >
        max([stat[(t, a)]["pass_rate"] for a in ("bare", "omc") if (t, a) in stat] or [0])
        for t in traps) if traps else False
    print(f"- H1 correctness: {verdict(not h1_lose and h1_traps)} — "
          f"lost on {h1_lose or 'nothing'}; strictly ahead on traps: {h1_traps}")

    # H2 — harness tax on T1.
    if ("T1", "team") in stat:
        base = [stat[("T1", a)]["cost"] for a in ("bare", "omc") if ("T1", a) in stat]
        cheapest = min(base) if base else 0
        ratio = (stat[("T1", "team")]["cost"] / cheapest) if cheapest else 0
        print(f"- H2 harness tax: {verdict(0 < ratio <= 1.5)} — "
              f"T1 costs {ratio:.2f}x the cheapest baseline (kill above 1.5x)")

    # H3 — containment.
    oos_team = sum(stat[(t, "team")]["oos"] for t in tasks if (t, "team") in stat)
    oos_bare = sum(stat[(t, "bare")]["oos"] for t in tasks if (t, "bare") in stat)
    print(f"- H3 containment: {verdict(oos_team < oos_bare)} — "
          f"team {oos_team} out-of-scope files vs bare {oos_bare}")

    # H4 — predictability.
    sp_team = med([stat[(t, "team")]["spread"] for t in tasks if (t, "team") in stat])
    sp_other = med([stat[(t, a)]["spread"] for t in tasks
                    for a in ("bare", "omc") if (t, a) in stat])
    print(f"- H4 predictability: {verdict(sp_team < sp_other)} — "
          f"team median spread {sp_team:.2f}x vs baselines {sp_other:.2f}x")

    # ---- the decision rule -------------------------------------------------
    wins = sum(1 for t in tasks if "team" in winners.get(t, []))
    print(f"\n### Decision\n\n- team-irfan wins or ties {wins}/{len(tasks)} tasks "
          f"(needs >= 3 of 4)")
    print("- complexity is earned only if that holds AND H2 holds AND H3 holds")

    print("\n### Where team-irfan lost\n\n<fill in from runs/*/team/*/diff.txt "
          "and acceptance.log — this section is the actual output of the exercise>")
    print("\n### Actions\n\n<max 3, each traceable to a failed hypothesis>")

if __name__ == "__main__":
    main(sys.argv[1])
