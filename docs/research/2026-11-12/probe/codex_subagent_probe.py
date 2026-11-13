import json, os, glob, collections, time
cut = time.time()-30*86400; c = collections.Counter()
for f in [f for f in glob.glob(os.path.expanduser("~/.codex/sessions") + "/**/*.jsonl", recursive=True) if os.path.getmtime(f) > cut]:
    kind = None
    for line in open(f, errors="ignore"):
        try: r = json.loads(line)
        except Exception: continue
        p = r.get("payload") if isinstance(r.get("payload"), dict) else {}
        if r.get("type") == "session_meta" and kind is None:
            s = p.get("source"); kind = "subagent" if isinstance(s, dict) and "subagent" in s else ("exec" if p.get("originator") == "codex_exec" else "attended")
        if r.get("type") == "response_item" and p.get("type") == "message" and p.get("role") == "user":
            txt = [b.get("text", "") for b in p.get("content") or [] if b.get("type") == "input_text"]
            txt = [t for t in txt if not t.strip().startswith("<") and not t.strip().startswith("# AGENTS.md")]
            if any(t.strip() for t in txt): c[kind] += 1
    c[(kind, "sessions")] += 1
print(c)
