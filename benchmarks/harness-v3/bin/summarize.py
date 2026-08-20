"""results.csv -> a table a human can read without opening a spreadsheet."""
import csv, statistics, sys
from collections import defaultdict

ARMS = ["bare", "omc", "team"]
LABEL = {"bare": "A bare", "omc": "B omc", "team": "C team-irfan"}
ORDER = ["T1", "T4", "T2", "T3"]

def main(path, label):
    rows = list(csv.DictReader(open(path)))
    cells = defaultdict(list)
    for r in rows:
        cells[(r["task"], r["arm"])].append(r)
    tasks = [t for t in ORDER if any(k[0] == t for k in cells)]

    print(f"# Benchmark results — {label}\n")
    print(f"{len(rows)} scored cells. Medians of the rounds present; "
          f"spread is max/min cost across them.\n")
    print("| Task | Arm | rounds | pass | $ med | wall med | diff LOC | turns | tools | oos | spread |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for t in tasks:
        for a in ARMS:
            rs = cells.get((t, a))
            if not rs:
                print(f"| {t} | {LABEL[a]} | 0 | — | — | — | — | — | — | — | — |")
                continue
            med = lambda k: statistics.median(float(r[k]) for r in rs)
            cost = [float(r["cost_usd"]) for r in rs]
            spread = max(cost) / min(cost) if min(cost) > 0 else 0
            print(f"| {t} | {LABEL[a]} | {len(rs)} | {med('pass_rate'):.0%} | "
                  f"{statistics.median(cost):.3f} | {med('wall_sec'):.0f}s | "
                  f"{med('diff_loc'):.0f} | {med('num_turns'):.0f} | {med('tool_calls'):.0f} | "
                  f"{sum(int(r['oos_files']) for r in rs)} | {spread:.2f}x |")

    total = sum(float(r["cost_usd"]) for r in rows)
    regs = sum(1 for r in rows if r["regression"] != "pass")
    guards = sum(1 for r in rows if r["guard"] != "ok")
    print(f"\n- total spend: ${total:.2f}")
    print(f"- regression-gate failures: {regs} of {len(rows)}")
    print(f"- protected-test guard trips: {guards} of {len(rows)}")
    print("\nA cell with `regression = fail` or a tripped guard scores pass_rate 0 "
          "regardless of its acceptance result.")
    print("\nSee `COVERAGE.txt` in this folder for which cells ran and the commands "
          "to finish the rest.")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "unlabelled")
