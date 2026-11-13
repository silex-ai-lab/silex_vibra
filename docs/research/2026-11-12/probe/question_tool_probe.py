import json, os, glob, collections, time
files = [f for f in glob.glob(os.path.expanduser("~/.claude/projects") + "/**/*.jsonl", recursive=True) if os.path.getmtime(f) > time.time()-30*86400]
c = collections.Counter()
for f in files:
    names = {}
    for line in open(f, errors="ignore"):
        try: r = json.loads(line)
        except Exception: continue
        if r.get("type") == "assistant":
            for b in (r.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in ("AskUserQuestion", "ExitPlanMode"): names[b["id"]] = b["name"]
        if r.get("type") == "user":
            for b in (r.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("tool_use_id") in names:
                    pd = r.get("permissionDecision") or {}
                    c[(names[b["tool_use_id"]], pd.get("source"), pd.get("decision"), bool(r.get("isSidechain")))] += 1
for k, v in c.most_common(): print(v, k)
cx = collections.Counter()
for f in [f for f in glob.glob(os.path.expanduser("~/.codex/sessions") + "/**/*.jsonl", recursive=True) if os.path.getmtime(f) > time.time()-30*86400]:
    for line in open(f, errors="ignore"):
        try: r = json.loads(line)
        except Exception: continue
        p = r.get("payload") if isinstance(r.get("payload"), dict) else {}
        if p.get("type") in ("function_call", "custom_tool_call"): cx[p.get("name")] += 1
print(cx.most_common(15))
