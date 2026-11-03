"""Synthetic contract tests for perf_oracle.py. Run: python3 -I oracle_selftest.py"""
import json, os, sys, tempfile
from datetime import datetime, timedelta, timezone

os.environ["TZ"] = "America/Los_Angeles"
import time; time.tzset()
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import perf_oracle as o

NOW = datetime(2026, 11, 3, 21, 0, tzinfo=timezone.utc)
T0 = NOW - timedelta(days=1)
SONNET = "claude-sonnet-5-5"
failures = []


def rec(i, cr=0, cc=0, inp=0, out=0, model=SONNET, tools=(), at=None, rid=None, cwd="/Users/demo/work/proj"):
    ts = (at or T0 + timedelta(minutes=i)).isoformat().replace("+00:00", "Z")
    content = [{"type": "tool_use", "name": n, "input": {"x": 1}} for n in tools]
    return {"type": "assistant", "timestamp": ts, "cwd": cwd,
            "message": {"id": rid or f"msg_{i}", "model": model, "content": content,
                        "usage": {"input_tokens": inp, "output_tokens": out,
                                  "cache_creation_input_tokens": cc, "cache_read_input_tokens": cr}}}


def run(records, now=NOW):
    d = tempfile.mkdtemp()
    p = os.path.join(d, "s.jsonl")
    with open(p, "w") as f:
        for r in records: f.write(json.dumps(r) + "\n")
    _, _, inw = o.make_window(now, 7)
    samples = o.samples_of(p)
    return samples, o.analyze("s", samples, inw, o.DEFAULTS)


def find(res, kind):
    return next((s for s in res["found"] if s["detector"] == kind), None) if res else None


def check(name, cond, detail=""):
    if not cond: failures.append(f"{name}: {detail}")
    print(("ok   " if cond else "FAIL ") + name, detail)


_, r = run([rec(0, cc=10_000), rec(1, cr=10_000, cc=100_000)] + [rec(i, cr=110_000) for i in range(2, 10)])
check("new content is not a D2 rewrite", find(r, "cacheRewrite") is None)

_, r = run([rec(i, inp=100_000) for i in range(10)])
check("no cache writes means no D2", find(r, "cacheRewrite") is None)

recs = [rec(i, cr=100_000) for i in range(5)] + [rec(5, cc=100_000, at=T0 + timedelta(hours=3))] + [rec(i, cr=100_000, at=T0 + timedelta(hours=3, minutes=i)) for i in range(6, 10)]
_, r = run(recs)
d2 = find(r, "cacheRewrite")
check("expired cache after 3h is one D2 event", d2 is not None and d2["finding"] == dict(events=1, rewrittenTokens=100_000, dominantCause="idleOver1h"), str(d2 and d2["finding"]))
check("D2 exposure = 100k x (3.75 - 0.30) / 1e6", d2 is not None and abs(d2["exposureUSD"] - 0.345) < 1e-9, str(d2 and d2["exposureUSD"]))

alt = [rec(i, cr=(100_000 if i % 2 == 0 else 190_000), tools=("Read",)) for i in range(10)]
_, r = run(alt)
d3 = find(r, "explorationBurst")
check("D3 with no later turns has zero exposure", d3 is not None and d3["exposureUSD"] == 0, str(d3 and d3["exposureUSD"]))

burst = [rec(i, cr=100_000, tools=("Read",)) for i in range(3)] + [rec(3, cr=190_000, tools=("Bash",))] + [rec(i, cr=190_000, tools=("Bash",)) for i in range(4, 10)]
_, r = run(burst)
d3 = find(r, "explorationBurst")
check("D3 carry = 90k x 6 later turns x 0.30 / 1e6", d3 is not None and abs(d3["exposureUSD"] - 0.162) < 1e-9, str(d3 and d3["exposureUSD"]))
check("D3 exposure never exceeds session value", d3 is not None and d3["exposureUSD"] <= d3["sessionValueUSD"])

_, r = run([rec(i, cr=100_000) for i in range(9)] + [rec(9, out=500)])
check("an output-only record is not a turn", r is None, str(r))

s, _ = run([dict(rec(0, cr=50_000, rid="m1"), timestamp=None), rec(0, cr=50_000, out=10, rid="m1", at=T0 + timedelta(seconds=7))])
check("fold keeps the first non-nil timestamp", len(s) == 1 and s[0]["at"] == T0 + timedelta(seconds=7) and s[0]["u"][1] == 10, str(s))

old = NOW - timedelta(days=9)
recs = [rec(0, cr=100_000, tools=("Read",), at=old), rec(1, cr=100_000, tools=("Grep",), at=old + timedelta(minutes=1)),
        rec(2, cr=100_000, tools=("Glob",))] + [rec(i, cr=100_000) for i in range(3, 13)]
_, r = run(recs)
d3 = find(r, "explorationBurst")
check("burstTurns counts in-window turns only", d3 is not None and d3["finding"]["burstTurns"] == 1, str(d3 and d3["finding"]))

_, r = run([rec(i, cr=250_000) for i in range(60)])
d1 = find(r, "contextCarry")
check("D1 exposure = 60 x 50k x 0.30 / 1e6", d1 is not None and abs(d1["exposureUSD"] - 0.9) < 1e-9, str(d1 and d1["exposureUSD"]))
check("D1 is a lead at 0.9 of 4.5", d1 is not None and d1["isLead"] and abs(d1["sessionValueUSD"] - 4.5) < 1e-9)

_, r = run([rec(i, cr=250_000) for i in range(59)] + [rec(59, cr=250_000, model="claude-fable-5-1")])
d1 = find(r, "contextCarry")
check("one unpriced in-window turn: nil figures, no lead", d1 is not None and d1["exposureUSD"] is None and not d1["isLead"] and not r["priced"])

_, r = run([dict(rec(0, cr=250_000, model="claude-fable-5-1"), timestamp=(NOW - timedelta(days=9)).isoformat())] + [rec(i, cr=250_000) for i in range(1, 61)])
d1 = find(r, "contextCarry")
check("an unpriced turn outside the window keeps the session priced", r is not None and r["priced"] and d1 and d1["exposureUSD"] is not None)

recs = [rec(i, cr=200_000) for i in range(5)] + [rec(5, model="<synthetic>", cwd="/x/zero")] + [rec(6, cc=200_000, at=T0 + timedelta(hours=3))] + [rec(i, cr=200_000, at=T0 + timedelta(hours=3, minutes=i)) for i in range(7, 12)]
_, r = run(recs)
d2 = find(r, "cacheRewrite")
check("a zero-usage synthetic record is neither boundary nor model switch", d2 is not None and d2["finding"]["dominantCause"] == "idleOver1h" and d2["finding"]["events"] == 1, str(d2 and d2["finding"]))

recs = [dict(rec(0, model="<synthetic>"), cwd="/x/zero-usage-project")] + [rec(i, cr=250_000, cwd="/Users/SECRET_PARENT/work/proj") for i in range(1, 61)]
_, r = run(recs)
d1 = find(r, "contextCarry")
check("project comes from turns, as the cwd basename only", d1 is not None and d1["project"] == "proj" and "SECRET_PARENT" not in json.dumps(r), str(d1 and d1["project"]))
check("D1 finding carries its effective floor", d1 is not None and d1["finding"]["floorTokens"] == 200_000)

_, r = run([rec(i, inp=100_000) for i in range(9)] + [rec(9, cc=100_000)])
check("a first cache fill after uncached turns is not a D2 rewrite", find(r, "cacheRewrite") is None, str(r and r["found"]))

_, r = run([rec(i, cr=190_000) for i in range(400)] + [rec(i, cr=250_000) for i in range(400, 450)])
d1 = find(r, "contextCarry")
check("priced D1 above leadMinUSD but below leadMinShare is not a lead",
      d1 is not None and abs(d1["exposureUSD"] - 0.75) < 1e-9 and abs(d1["sessionValueUSD"] - 26.55) < 1e-9 and not d1["isLead"],
      str(d1 and (d1["exposureUSD"], d1["sessionValueUSD"], d1["isLead"])))

recs = ([rec(i, cr=100_000) for i in range(2)] + [rec(i, cr=100_000, tools=("Read",)) for i in range(2, 5)] + [rec(5, cr=150_000)]
        + [rec(6, cr=100_000)] + [rec(i, cr=100_000, tools=("Grep",)) for i in range(7, 10)] + [rec(10, cr=150_000)]
        + [rec(i, cr=150_000) for i in range(11, 18)])
_, r = run(recs)
d3 = find(r, "explorationBurst")
check("D3 does not re-charge growth that dropped before a later burst", d3 is not None and abs(d3["exposureUSD"] - 7 * 50_000 * 0.30 / 1e6) < 1e-9, str(d3 and d3["exposureUSD"]))

_, r = run([rec(i, cr=150_000, cc=60_000, inp=40_000) for i in range(60)])
d1 = find(r, "contextCarry")
want = 60 * (10_000 * 3.75 + 40_000 * 3.0) / 1e6
check("D1 prices above-floor tokens by band (write and input above a 150k read prefix)", d1 is not None and abs(d1["exposureUSD"] - want) < 1e-9, str(d1 and (d1["exposureUSD"], want)))

recs = ([rec(i, cr=200_000) for i in range(4)] + [rec(4, cc=200_000, model="claude-fable-5-1")] + [rec(5, cr=200_000, model="claude-fable-5-1")]
        + [rec(6, cc=200_000, at=T0 + timedelta(hours=3))] + [rec(i, cr=200_000, at=T0 + timedelta(hours=3, minutes=i)) for i in range(7, 12)])
_, r = run(recs)
d2 = find(r, "cacheRewrite")
check("unpriced D2: dominant cause by tokens then fixed order (modelSwitch first)", d2 is not None and d2["finding"]["dominantCause"] == "modelSwitch" and d2["exposureUSD"] is None, str(d2 and d2["finding"]))

recs = ([rec(i, cr=100_000) for i in range(2)] + [rec(i, cr=100_000, tools=("Read",)) for i in range(2, 5)] + [rec(5, cr=150_000)]
        + [rec(6, cr=120_000)] + [rec(i, cr=120_000, tools=("Grep",)) for i in range(7, 10)] + [rec(10, cr=170_000)]
        + [rec(i, cr=170_000) for i in range(11, 18)])
_, r = run(recs)
d3 = find(r, "explorationBurst")
check("D3 keeps only the part of an earlier burst's growth still in context", d3 is not None and abs(d3["exposureUSD"] - (5 * 20_000 + 7 * 70_000) * 0.30 / 1e6) < 1e-9, str(d3 and d3["exposureUSD"]))

d = tempfile.mkdtemp(); pth = os.path.join(d, "t.jsonl")
with open(pth, "w") as f:
    f.write(json.dumps(rec(0, cr=10)) + "\n" + "[1, 2]\n" + json.dumps(rec(1, cr=20)) + "\n" + json.dumps(rec(2, cr=30)))
s_ = o.samples_of(pth)
check("unterminated last line is ignored and a non-object line is skipped", [t["u"][3] for t in s_] == [10, 20], str([t["u"][3] for t in s_]))

recs = [rec(i, cr=250_000) for i in range(60)] + [dict(rec(60, cr=5_000), isSidechain=True)] + [rec(i, cr=250_000) for i in range(61, 62)]
_, r = run(recs)
d1 = find(r, "contextCarry")
check("an inline sidechain record is not a turn and does not split the segment", d1 is not None and d1["finding"]["turnsAboveFloor"] == 61 and d1["turns"] == 61, str(d1 and (d1["finding"], d1["turns"])))

s_, _ = run([dict(rec(0, cr=10), timestamp="2026-11-02T21:00:00")])
check("a timestamp without a zone is undated", s_[0]["at"] is None, str(s_[0]["at"]))
s_, _ = run([rec(0, cr=10) | {"message": dict(rec(0)["message"], usage={"input_tokens": "abc", "output_tokens": "12", "cache_creation_input_tokens": 3.9, "cache_read_input_tokens": True})}])
check("usage values parse like jsonInt", s_[0]["u"] == [0, 12, 3, 1], str(s_[0]["u"]))

recs = [rec(i, cr=229_000) for i in range(12)] + [rec(12, cc=60_000)] + [rec(i, cr=60_000) for i in range(13, 20)]
_, r = run(recs)
check("compactionIsNotARewrite: a post-compaction write above both D2 bars is not D2", r is not None and find(r, "cacheRewrite") is None, str(r and r["found"]))

home = tempfile.mkdtemp(); proj = os.path.join(home, ".claude", "projects", "-p")
os.makedirs(os.path.join(proj, "sess", "subagents"))
def write(path, records, mtime):
    with open(path, "w") as f:
        for x in records: f.write(json.dumps(x) + "\n")
    os.utime(path, (mtime, mtime))
local_start = datetime(2026, 10, 28, 0, 30).astimezone()
write(os.path.join(proj, "main.jsonl"),
      [rec(0, cr=1, at=(local_start - timedelta(hours=1)).astimezone(timezone.utc)),
       rec(1, cr=10, at=local_start.astimezone(timezone.utc)),
       rec(2, cr=100, out=5, rid="dup"), rec(2, cr=100, out=7, rid="dup")] + [rec(i, cr=1000) for i in range(3, 13)],
      NOW.timestamp())
write(os.path.join(proj, "sess", "subagents", "agent-1.jsonl"), [rec(i, cr=250_000, tools=("Read",)) for i in range(60)], NOW.timestamp())
write(os.path.join(proj, "stale.jsonl"), [rec(0, cr=7)], NOW.timestamp() - 9 * 86400)
write(os.path.join(proj, "agent-old.jsonl"), [dict(rec(i, cr=250_000, tools=("Read",)), isSidechain=True) for i in range(60)], NOW.timestamp())
rep_ = o.report(home, NOW)
tot = rep_["claudeTotal"]
check("report(): window starts at local midnight across the DST change", rep_["window"]["start"] == "2026-10-28T00:00:00-07:00", rep_["window"]["start"])
check("report(): totals include subagents, fold duplicates, drop out-of-window and stale files",
      tot == dict(input=0, output=7, cacheCreation=0, cacheRead=10 + 100 + 10 * 1000 + 2 * 60 * 250_000), str(tot))
check("report(): a subagents/ file is not a session; an all-sidechain file has no turns and counts as skipped", rep_["analyzedSessions"] == 1 and rep_["skippedSmallSessions"] == 1 and all(x["sessionID"] == "main" for x in rep_["suggestions"]), str((rep_["analyzedSessions"], rep_["skippedSmallSessions"])))
check("report(): emits the thresholds it used", rep_["thresholds"] == o.DEFAULTS)

print("RESULT", "PASS" if not failures else f"{len(failures)} FAILED")
sys.exit(1 if failures else 0)
