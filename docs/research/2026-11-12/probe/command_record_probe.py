"""Counts how Claude Code slash-command user records are shaped: leading tag, and whether a <command-name> element is present. No text printed."""
import collections, glob, json, os, re, time
c = collections.Counter()
for f in glob.glob(os.path.expanduser("~/.claude/projects") + "/**/*.jsonl", recursive=True):
    if os.path.getmtime(f) < time.time() - 30 * 86400 or "/subagents/" in f:
        continue
    for line in open(f, errors="ignore"):
        if "command-" not in line and "bash-input" not in line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("type") != "user" or r.get("isMeta") or r.get("isSidechain"):
            continue
        m = (r.get("message") or {}).get("content")
        if isinstance(m, list):
            if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in m):
                continue
            m = "\n".join(b.get("text", "") for b in m if isinstance(b, dict) and b.get("type") == "text")
        if not isinstance(m, str):
            continue
        t = m.strip(); lead = re.match(r"<([\w-]+)", t)
        lead = lead.group(1) if lead else "-"
        if lead in ("command-name", "command-message", "bash-input"):
            c[(lead, "has <command-name> element" if re.search(r"<command-name>[\s\S]*?</command-name>", t) else "no <command-name> element")] += 1
for k, v in sorted(c.items()): print(v, *k)
