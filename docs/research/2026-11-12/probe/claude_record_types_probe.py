import json, os, sys, glob, collections, time
root = os.path.expanduser("~/.claude/projects")
files = glob.glob(root + "/**/*.jsonl", recursive=True)
types = collections.Counter(); subtypes = collections.Counter(); keys = collections.Counter()
oldest = min((os.path.getmtime(f) for f in files), default=0)
recent = [f for f in files if os.path.getmtime(f) > time.time() - 30*86400]
for f in recent:
    for line in open(f, errors="ignore"):
        try: r = json.loads(line)
        except Exception: continue
        t = r.get("type"); types[t] += 1
        if t in ("system", "permission-mode", "attachment", "progress"):
            subtypes[(t, r.get("subtype") or r.get("level") or (r.get("attachment") or {}).get("type"))] += 1
        if t == "user" and isinstance(r.get("toolUseResult"), (dict, str)):
            tur = r["toolUseResult"]
            if isinstance(tur, str): keys[("str-result", tur[:40].split(":")[0])] += 0  # content not printed
print("files", len(files), "recent30d", len(recent), "oldest_days", round((time.time()-oldest)/86400, 1))
for k, v in types.most_common(): print("type", k, v)
for k, v in subtypes.most_common(40): print("sub", k, v)
