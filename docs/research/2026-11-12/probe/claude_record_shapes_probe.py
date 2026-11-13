import json, os, glob, collections, time
files = [f for f in glob.glob(os.path.expanduser("~/.claude/projects") + "/**/*.jsonl", recursive=True) if os.path.getmtime(f) > time.time()-30*86400]
ks = collections.Counter(); pm = collections.Counter(); tr = collections.Counter(); modev = collections.Counter(); prev = collections.Counter()
for f in files:
    last = None
    for line in open(f, errors="ignore"):
        try: r = json.loads(line)
        except Exception: continue
        t = r.get("type")
        if t == "permission-mode":
            ks[("pm", tuple(sorted(r.keys())))] += 1; pm[r.get("permissionMode")] += 1; prev[("before-pm", last)] += 1
        if t == "mode": ks[("mode", tuple(sorted(r.keys())))] += 1; modev[str(r.get("mode"))[:20]] += 1
        if t == "user":
            c = (r.get("message") or {}).get("content")
            if isinstance(c, list) and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
                tur = r.get("toolUseResult")
                tr[("tur", type(tur).__name__, tuple(sorted(tur.keys()))[:8] if isinstance(tur, dict) else None)] += 0
                tr[("userkeys", tuple(sorted(k for k in r.keys())))] += 1
                for b in c:
                    if isinstance(b, dict) and b.get("type") == "tool_result":
                        txt = b.get("content"); s = txt if isinstance(txt, str) else json.dumps(txt)
                        tr[("rejected", "doesn't want to proceed" in s or "user rejected" in s.lower() or "denied" in s.lower()[:200])] += 1
                        tr[("is_error", b.get("is_error"))] += 1
        last = t
for k, v in ks.most_common(6): print(k, v)
print(pm.most_common()); print(modev.most_common(8)); print(prev.most_common(8))
for k, v in tr.most_common(12): print(k, v)
