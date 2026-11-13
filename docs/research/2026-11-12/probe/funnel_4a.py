"""Counts-only funnel for task 4a: why the clause qualifies on N rows. Prints numbers only."""
import collections, os, sys, time
sys.path.insert(0, sys.argv[1]); import evidence_oracle as o
home, cut = os.path.expanduser("~"), time.time() - 30 * 86400
c = collections.Counter()
for agent, sessions, fold in [("claudeCode", o.claude_sessions(home, cut), o.fold_claude), ("codex", o.codex_sessions(home, cut), o.fold_codex)]:
    for files in sessions:
        ev, saw = [], False
        for f in files:
            e, s = fold(f, [], home); ev += e; saw = saw or s
        name, pick = o.verdict(ev, saw)
        if name != "checkedAfterLastChange":
            continue
        c[f"{agent} 1 row checkedAfterLastChange"] += 1
        after = [x for x in ev if x[1] == "check" and x[0] > max(y[0] for y in ev if y[1] == "change")]
        latest = [max((x for x in after if x[2] == k), key=lambda x: x[0]) for k in o.RANK if any(x[2] == k for x in after)]
        p = next((x for x in latest if x[3].startswith("failed")), latest[0])
        if p[2] != "test" or not p[3].startswith("passed"):
            continue
        c[f"{agent} 2 P is a passed test"] += 1
        earlier = [x for x in ev if x[1] == "check" and x[2] == "test" and x[0] < p[0]]
        if not earlier:
            continue
        f = max(earlier, key=lambda x: x[0])
        if not f[3].startswith("failed"):
            continue
        c[f"{agent} 3 F failed"] += 1
        if f[4] is None:
            continue
        c[f"{agent} 4 F has completedAt"] += 1
        win = [x for x in ev if x[1] == "change" and x[0] < p[0] and (x[4] or o.INF) > f[4]]
        if win:
            c[f"{agent} 5 any change touches window"] += 1
        tw = [x for x in win if x[5] is not None]
        if tw:
            c[f"{agent} 6 test change touches window"] += 1
        if any(x[5][2] is not None for x in tw):
            c[f"{agent} 7 a compared test change touches window"] += 1
for k in sorted(c):
    print(f"{c[k]:>5}  {k}")
