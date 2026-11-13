import json, os, glob, collections, time
files = [f for f in glob.glob(os.path.expanduser("~/.claude/projects") + "/**/*.jsonl", recursive=True) if os.path.getmtime(f) > time.time()-30*86400]
c = collections.Counter(); shape = collections.Counter()
def enum(v):
    if isinstance(v, (bool, int, float)) or v is None: return v
    if isinstance(v, str): return v if len(v) <= 24 and " " not in v else "<str>"
    if isinstance(v, dict): return {k: enum(x) for k, x in sorted(v.items())}
    return "<list>"
for f in files:
    for line in open(f, errors="ignore"):
        if '"permissionDecision"' not in line: continue
        try: r = json.loads(line)
        except Exception: continue
        d = r.get("permissionDecision")
        c[json.dumps(enum(d), sort_keys=True)] += 1
for k, v in c.most_common(25): print(v, k)
