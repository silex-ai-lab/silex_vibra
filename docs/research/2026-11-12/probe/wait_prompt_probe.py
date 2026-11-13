import json, os, glob, collections, time, datetime, statistics
def ts(s): return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
files = [f for f in glob.glob(os.path.expanduser("~/.claude/projects") + "/**/*.jsonl", recursive=True) if os.path.getmtime(f) > time.time()-30*86400]
tools = collections.Counter(); turkeys = collections.Counter(); gaps = []; sess = collections.Counter(); side = collections.Counter(); between = collections.Counter()
for f in files:
    uses = {}; order = []
    for line in open(f, errors="ignore"):
        try: r = json.loads(line)
        except Exception: continue
        t = r.get("type")
        if t == "assistant":
            for b in (r.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use": uses[b.get("id")] = (r.get("timestamp"), b.get("name"), len(order))
        order.append(t)
        pd = r.get("permissionDecision")
        if t == "user" and isinstance(pd, dict) and str(pd.get("source", "")).startswith("user"):
            for b in (r.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("tool_use_id") in uses:
                    at, name, idx = uses[b["tool_use_id"]]
                    tools[name] += 1; sess[f] += 1; side[r.get("isSidechain")] += 1
                    between[tuple(sorted(set(order[idx+1:-1])))] += 1
                    tur = r.get("toolUseResult")
                    turkeys[tuple(sorted(tur.keys())) if isinstance(tur, dict) else type(tur).__name__] += 1
                    gaps.append(ts(r["timestamp"]) - ts(at))
print("n", len(gaps), "sessions", len(sess), "sidechain", dict(side))
print(tools.most_common())
for k, v in turkeys.most_common(8): print(v, k)
for k, v in between.most_common(8): print(v, k)
g = sorted(gaps); q = statistics.quantiles(g, n=4, method="inclusive"); print("gap s p25/50/75", [round(x,1) for x in q], "min", round(g[0],1), "max", round(g[-1],1))
