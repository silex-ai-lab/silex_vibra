"""Write a synthetic VIBRA_HOME that any seat may use for the Swift-vs-oracle comparison.

    python3 -I make_synthetic_home.py <out_dir> [--now 2026-11-03T21:00:00Z]

Covers: duplicate response records, a compaction, a subagent file, an unpriced
session, an out-of-window head across the DST change, a stale file, a zero-usage
<synthetic> record, and sessions that fire D1, D2 and D3 as leads.
"""
import json, os, sys
from datetime import datetime, timedelta, timezone

out = sys.argv[1]
now = datetime.fromisoformat((sys.argv[3] if len(sys.argv) > 3 else "2026-11-03T21:00:00Z").replace("Z", "+00:00"))
T0 = now - timedelta(days=1)
root = os.path.join(out, ".claude", "projects", "-Users-demo-work-proj")


def rec(i, cr=0, cc=0, inp=0, out=0, model="claude-sonnet-5-5", tools=(), at=None, rid=None, cwd="/Users/demo/work/proj"):
    return {"type": "assistant", "timestamp": (at or T0 + timedelta(minutes=i)).astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
            "cwd": cwd, "message": {"id": rid or f"m{i}", "model": model,
                                    "content": [{"type": "tool_use", "name": n, "input": {"path": "/x"}} for n in tools],
                                    "usage": {"input_tokens": inp, "output_tokens": out, "cache_creation_input_tokens": cc, "cache_read_input_tokens": cr}}}


def write(name, records, mtime=None):
    path = os.path.join(root, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for r in records: f.write(json.dumps(r) + "\n")
    m = (mtime or now).timestamp(); os.utime(path, (m, m))


write("carry.jsonl", [rec(i, cr=250_000, out=100) for i in range(60)] + [rec(60, cr=250_000, out=5, rid="d"), rec(60, cr=250_000, out=9, rid="d")])
write("rewrite.jsonl", [rec(i, cr=100_000) for i in range(6)] + [rec(6, model="<synthetic>")] + [rec(7, cc=100_000, at=T0 + timedelta(hours=3))]
      + [rec(i, cr=100_000, at=T0 + timedelta(hours=3, minutes=i)) for i in range(8, 14)])
write("burst.jsonl", [rec(i, cr=20_000) for i in range(3)] + [rec(i, cr=20_000, tools=("Read", "Grep")) for i in range(3, 7)]
      + [rec(i, cr=200_000, tools=("Bash",)) for i in range(7, 20)])
write("compaction.jsonl", [rec(i, cr=200_000 + i * 1_000) for i in range(30)] + [rec(30, cc=20_000)] + [rec(i, cr=20_000) for i in range(31, 45)])
write("switch.jsonl", [rec(i, cr=100_000) for i in range(6)] + [rec(6, cc=100_000, model="claude-opus-5-5")] + [rec(i, cr=100_000, model="claude-opus-5-5") for i in range(7, 14)])
write("idle10.jsonl", [rec(i, cr=100_000) for i in range(6)] + [rec(6, cc=100_000, at=T0 + timedelta(minutes=16))] + [rec(i, cr=100_000, at=T0 + timedelta(minutes=10 + i)) for i in range(7, 14)])
write("other.jsonl", [rec(i, cr=100_000) for i in range(6)] + [rec(6, cc=100_000)] + [rec(i, cr=100_000) for i in range(7, 14)])
write("unpriced.jsonl", [rec(i, cr=250_000, model="claude-fable-5-1") for i in range(60)])
head = datetime(2026, 10, 28, 0, 30).astimezone()
write("dst.jsonl", [rec(0, cr=5, at=head - timedelta(hours=1)), rec(1, cr=7, at=head)] + [rec(i, cr=1_000) for i in range(2, 12)])
write("small.jsonl", [rec(i, cr=1_000) for i in range(4)])
write("stale.jsonl", [rec(0, cr=3)], mtime=now - timedelta(days=9))
write("carry/subagents/agent-a1.jsonl", [rec(i, cr=250_000, tools=("Read",)) for i in range(60)])
print(out)
