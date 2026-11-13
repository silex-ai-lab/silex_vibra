"""Counts Claude Code main transcripts by entrypoint and whether a typed-looking, non-dispatch prompt exists
(the loose rule of wait_turn_probe.py). VIBRA_HOME overrides HOME. Counts only."""
import collections, glob, json, os, re
home = os.environ.get("VIBRA_HOME") or os.path.expanduser("~")
c = collections.Counter()
for f in glob.glob(home + "/.claude/projects/**/*.jsonl", recursive=True):
    if "/subagents/" in f:
        continue
    entry, loose, scheduled, first = None, 0, False, True
    for line in open(f, errors="ignore"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        entry = entry or r.get("entrypoint")
        if r.get("type") != "user" or r.get("isMeta") or r.get("isSidechain"):
            continue
        m = (r.get("message") or {}).get("content")
        if first and isinstance(m, str):
            first, scheduled = False, m.lstrip().startswith("<scheduled-task")
        if isinstance(m, list):
            if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in m):
                continue
            m = "\n".join(b.get("text", "") for b in m if isinstance(b, dict) and b.get("type") == "text")
        if isinstance(m, str) and m.strip() and not m.strip().startswith("<") and not re.match(r"Dispatch `?[\w.-]+`?:", m.strip()):
            loose += 1
    if loose:
        c[(entry, "scheduled" if scheduled else "-")] += 1
for k, v in sorted(c.items(), key=lambda kv: -kv[1]): print(v, *k)
