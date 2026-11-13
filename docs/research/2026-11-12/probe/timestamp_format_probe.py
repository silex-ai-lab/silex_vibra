"""Counts timestamp fraction-digit lengths and zone suffixes in the first 50 lines of up to 400 files per agent."""
import collections, glob, os, re
c = collections.Counter()
for root in ("~/.claude/projects", "~/.codex/sessions"):
    for f in glob.glob(os.path.expanduser(root) + "/**/*.jsonl", recursive=True)[:400]:
        for i, line in enumerate(open(f, errors="ignore")):
            if i > 50:
                break
            m = re.search(r'"timestamp":"([^"]+)"', line)
            if m:
                s = m.group(1); fr = re.search(r"\.(\d+)", s)
                c[(root.split("/")[1], len(fr.group(1)) if fr else 0, "Z" if s.endswith("Z") else s[-6:])] += 1
for k, v in sorted(c.items()): print(v, *k)
