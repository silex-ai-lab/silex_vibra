"""Independent oracle for plan v0.2: the Usage Report's Claude Code totals and D1-D3.

Reimplements the plan's rules in Python so the Swift output can be compared
field by field. Prints JSON with no message text, no tool arguments and no
paths: sessions are keyed by transcript file stem.

    python3 -I perf_oracle.py --root <dir containing .claude/projects> --now 2026-11-03T21:55:32Z
"""
import argparse, glob, json, os, sys
from datetime import datetime, timedelta, timezone

RATES = {
    "claude-opus-5": (15.0, 75.0, 18.75, 1.50),
    "claude-sonnet-5": (3.0, 15.0, 3.75, 0.30),
    "claude-haiku-4-5": (1.0, 5.0, 1.25, 0.10),
}
EXPLORE = {"Read", "Grep", "Glob"}
COMPACTION_MIN_CONTEXT = 50_000
COMPACTION_DROP = 0.5
D2_MISSED_SHARE = 0.5
DEFAULTS = dict(minTurns=10, d1MinTurnsAboveFloor=50, d1CarryFloorTokens=200_000,
                d2MinRewriteTokens=30_000, d3MinBurstTurns=3, leadMinUSD=0.25, leadMinShare=0.10)


def rate(model):
    if not model: return None
    m = model.lower()
    for k, key in (("opus", "claude-opus-5"), ("sonnet", "claude-sonnet-5"), ("haiku", "claude-haiku-4-5")):
        if k in m: return RATES[key]
    return None


def parse_ts(s):
    if not s: return None
    try: return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError: return None


def samples_of(path):
    """Assistant records with usage, folded per message.id (first timestamp, last usage, last non-nil model)."""
    out, pending = [], None
    sidechain = False
    for raw in open(path, "rb"):
        if not raw.endswith(b"\n"): break  # IncrementalLineReader never returns an unterminated tail
        try: r = json.loads(raw.decode("utf-8"))
        except Exception: continue
        if not isinstance(r, dict) or r.get("type") != "assistant": continue
        if r.get("isSidechain") is True: sidechain = True
        m = r.get("message")
        if not isinstance(m, dict) or not isinstance(m.get("usage"), dict): continue
        u = m["usage"]
        s = dict(id=m.get("id"), at=parse_ts(r.get("timestamp")), model=m.get("model"), project=(os.path.basename(r["cwd"].rstrip("/")) or None) if isinstance(r.get("cwd"), str) else None,
                 u=[int(u.get(k) or 0) for k in ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")],
                 tools=[b["name"] for b in (m.get("content") or []) if isinstance(b, dict) and b.get("type") == "tool_use" and isinstance(b.get("name"), str) and b["name"]])
        if pending and s["id"] is not None and s["id"] == pending["id"]:
            pending["u"] = s["u"]; pending["tools"] += s["tools"]
            pending["model"] = s["model"] or pending["model"]; pending["project"] = s["project"] or pending["project"]
            pending["at"] = pending["at"] or s["at"]
            continue
        if pending: out.append(pending)
        if s["id"] is None: out.append(s); pending = None
        else: pending = s
    if pending: out.append(pending)
    return out, sidechain


def ctx(t): return t["u"][0] + t["u"][2] + t["u"][3]


def above_floor_usd(t, floor):
    """Exact price of prompt tokens at positions [floor, c): cached prefix, then new cache writes, then uncached input."""
    r = rate(t["model"]); cr, cc, inp = t["u"][3], t["u"][2], t["u"][0]
    def overlap(lo, hi): return max(0, min(hi, cr + cc + inp) - max(lo, floor))
    return (overlap(0, cr) * r[3] + overlap(cr, cr + cc) * r[2] + overlap(cr + cc, cr + cc + inp) * r[0]) / 1e6
def usd(t):
    r = rate(t["model"]); return None if r is None else sum(a * b for a, b in zip(t["u"], r)) / 1e6


def analyze(stem, samples, in_window, T):
    turns = [t for t in samples if ctx(t) > 0]
    inw = [in_window(t) for t in turns]
    n_in = sum(inw)
    if n_in < T["minTurns"]: return None
    priced = all(rate(t["model"]) is not None for t, w in zip(turns, inw) if w)
    session_value = sum(usd(t) for t, w in zip(turns, inw) if w) if priced else None
    seg_id, s = [], 0
    for i, t in enumerate(turns):
        if i > 0 and ctx(turns[i - 1]) >= COMPACTION_MIN_CONTEXT and ctx(t) < COMPACTION_DROP * ctx(turns[i - 1]): s += 1
        seg_id.append(s)
    project = next((t["project"] for t in turns if t["project"]), "")
    found = []

    def emit(kind, finding, exposure):
        lead = (priced and session_value and session_value > 0 and exposure is not None and exposure > 0
                and exposure >= T["leadMinUSD"] and exposure >= T["leadMinShare"] * session_value)
        found.append(dict(sessionID=stem, project=project, turns=n_in, detector=kind, finding=finding,
                          exposureUSD=exposure, sessionValueUSD=session_value, isLead=bool(lead)))

    floor = T["d1CarryFloorTokens"]
    segs = sorted(set(seg_id))
    q_segs = []; above_total = 0; peak = 0; carry = 0.0
    for sg in segs:
        idx = [i for i in range(len(turns)) if seg_id[i] == sg and inw[i]]
        above = [i for i in idx if ctx(turns[i]) > floor]
        if len(above) >= T["d1MinTurnsAboveFloor"]:
            q_segs.append(sg); above_total += len(above); peak = max(peak, max(ctx(turns[i]) for i in idx))
            if priced: carry += sum(above_floor_usd(turns[i], floor) for i in above)
    if q_segs:
        emit("contextCarry", dict(segments=len(q_segs), turnsAboveFloor=above_total, peakContext=peak, floorTokens=floor), carry if priced else None)

    events = []
    for i in range(1, len(turns)):
        if seg_id[i] != seg_id[i - 1] or not inw[i]: continue
        p, t = turns[i - 1], turns[i]
        base = min(p["u"][2] + p["u"][3], ctx(t)); missed = min(t["u"][2], max(0, base - t["u"][3]))
        if missed < T["d2MinRewriteTokens"] or missed < D2_MISSED_SHARE * base: continue
        gap = (t["at"] - p["at"]).total_seconds() if t["at"] and p["at"] else None
        cause = ("modelSwitch" if t["model"] != p["model"] else
                 "idleOver1h" if gap is not None and gap > 3600 else
                 "idleOver5m" if gap is not None and gap > 300 else "other")
        r = rate(t["model"])
        events.append((cause, missed, None if r is None else missed * (r[2] - r[3]) / 1e6))
    if events:
        by = {}
        for c, m, e in events:
            b = by.setdefault(c, [0, 0, 0.0]); b[0] += 1; b[1] += m; b[2] += e or 0
        order = ("modelSwitch", "idleOver1h", "idleOver5m", "other")
        dominant = max(by, key=lambda c: (by[c][1], -order.index(c)))
        emit("cacheRewrite", dict(events=len(events), rewrittenTokens=sum(m for _, m, _ in events), dominantCause=dominant),
             sum(e for _, _, e in events) if priced else None)

    bursts = []; run = []
    for i, t in enumerate(turns):
        if t["tools"] and set(t["tools"]) <= EXPLORE and (not run or seg_id[i] == seg_id[run[-1]]): run.append(i); continue
        if len(run) >= T["d3MinBurstTurns"]: bursts.append(run)
        run = [i] if t["tools"] and set(t["tools"]) <= EXPLORE else []
    if len(run) >= T["d3MinBurstTurns"]: bursts.append(run)
    bursts = [b for b in bursts if any(inw[i] for i in b)]
    if bursts:
        carried, base = {}, {}
        for b in bursts:
            first, last = b[0], b[-1]
            top = last + 1 if last + 1 < len(turns) and seg_id[last + 1] == seg_id[first] else last
            growth = max(0, ctx(turns[top]) - ctx(turns[first]))
            still = growth
            for j in range(top + 1, len(turns)):
                if seg_id[j] != seg_id[first]: break
                still = max(0, min(still, ctx(turns[j]) - ctx(turns[first])))
                if j < last + 2 or not inw[j]: continue
                carried[j] = carried.get(j, 0) + still
                base[j] = min(base.get(j, ctx(turns[first])), ctx(turns[first]))
        exposure = sum(min(v, max(0, ctx(turns[j]) - base[j])) * rate(turns[j]["model"])[3] for j, v in carried.items()) / 1e6 if priced else None
        emit("explorationBurst", dict(bursts=len(bursts), burstTurns=sum(1 for b in bursts for i in b if inw[i])), exposure)
    return dict(found=found, priced=priced)


def make_window(now, days):
    """ReportWindow: local start of today minus days-1, through local start of today."""
    def day_of(dt):
        return dt.astimezone().replace(hour=0, minute=0, second=0, microsecond=0).replace(tzinfo=None).astimezone()
    end = day_of(now)
    start = (end.replace(tzinfo=None) - timedelta(days=days - 1)).astimezone()
    return start, end, (lambda t: t["at"] is not None and start <= day_of(t["at"]) <= end)


def report(root_home, now, days=7, T=DEFAULTS):
    start, end, in_window = make_window(now, days)
    cutoff = now.timestamp() - (days + 1) * 86400
    root = os.path.join(root_home, ".claude", "projects")
    files = sorted(f for f in glob.glob(root + "/**/*.jsonl", recursive=True) if os.path.getmtime(f) >= cutoff)
    total = [0, 0, 0, 0]
    suggestions = []; analyzed = unpriced = small = 0
    for f in files:
        samples, sidechain = samples_of(f)
        for t in samples:
            if in_window(t): total = [x + y for x, y in zip(total, t["u"])]
        if sidechain or "subagents" in os.path.relpath(f, root).split(os.sep)[:-1]: continue
        res = analyze(os.path.splitext(os.path.basename(f))[0], samples, in_window, T)
        if res is None: small += 1; continue
        analyzed += 1; unpriced += not res["priced"]; suggestions += res["found"]
    return dict(window=dict(days=days, start=start.isoformat(), now=now.isoformat()),
                claudeTotal=dict(input=total[0], output=total[1], cacheCreation=total[2], cacheRead=total[3]),
                analyzedSessions=analyzed, unpricedSessions=unpriced, skippedSmallSessions=small,
                suggestions=sorted(suggestions, key=lambda s: (s["detector"], s["sessionID"])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, help="the VIBRA_HOME directory")
    ap.add_argument("--now", required=True)
    ap.add_argument("--days", type=int, default=7)
    a = ap.parse_args()
    json.dump(report(a.root, parse_ts(a.now), a.days), sys.stdout, indent=1, default=str)


if __name__ == "__main__":
    main()
