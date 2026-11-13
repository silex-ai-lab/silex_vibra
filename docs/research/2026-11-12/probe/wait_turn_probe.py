import json, os, glob, re, time, datetime, statistics, collections
def ts(s): return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
CAP = 7200
files = [f for f in glob.glob(os.path.expanduser("~/.claude/projects") + "/**/*.jsonl", recursive=True)
         if os.path.getmtime(f) > time.time()-30*86400 and "/subagents/" not in f]
waits = []; over = 0; per = []; attended = 0; opened = 0
for f in files:
    since = None; disp = False; prompts = 0; mins = 0.0
    for line in open(f, errors="ignore"):
        try: r = json.loads(line)
        except Exception: continue
        t = r.get("type")
        if r.get("isSidechain"): continue
        if t == "assistant":
            m = r.get("message") or {}
            since = ts(r["timestamp"]) if (m.get("stop_reason") == "end_turn" and not disp) else None
        elif t == "user" and not r.get("isMeta"):
            c = (r.get("message") or {}).get("content")
            if isinstance(c, list):
                if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c): continue
                c = "\n".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
            if not isinstance(c, str) or not c.strip(): continue
            s = c.strip()
            if s.startswith("<") and not s.startswith("<pasted"): continue   # wrapper (approximation)
            if s.startswith("[Request interrupted"): continue
            disp = re.match(r"Dispatch `?[\w.-]+`?:", s) is not None
            if disp: since = None; continue
            prompts += 1
            if since is not None:
                g = ts(r["timestamp"]) - since
                if g > CAP: over += 1
                waits.append(min(g, CAP)); mins += min(g, CAP) / 60
            since = None
    if prompts:
        attended += 1; per.append(mins); opened += since is not None
def q(x): return [round(v, 1) for v in statistics.quantiles(sorted(x), n=4, method="inclusive")]
print("attended sessions", attended, "turn waits", len(waits), "over 2h", over, "open at end", opened)
print("turn wait seconds p25/50/75", q(waits))
print("blocked minutes per session p25/50/75", q(per), "sum", round(sum(per)))
