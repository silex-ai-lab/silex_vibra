"""Compare `Vibra --report --json` with perf_oracle.py on the same snapshot and clock.

    python3 -I compare.py [--total-only] <vibra.json> <oracle.json>

Prints counts and mismatches keyed by file stem only. Exit 0 only when the
Claude Code total matches exactly and every fired suggestion matches.
"""
import json, sys

args = [a for a in sys.argv[1:] if a != "--total-only"]
total_only = "--total-only" in sys.argv[1:]
vibra, oracle = (json.load(open(p)) for p in args[:2])
bad = 0

claude = next((a for a in vibra["agents"] if a["agent"] == "claudeCode"), None)
got = claude["usage"] if claude else {}
for k, v in oracle["claudeTotal"].items():
    if got.get(k) != v:
        bad += 1; print(f"TOTAL MISMATCH {k}: vibra={got.get(k)} oracle={v}")
print("claude total tokens: vibra", sum(got.values()) if got else None, "oracle", sum(oracle["claudeTotal"].values()))

if total_only:
    print("RESULT", "MATCH" if bad == 0 else f"{bad} MISMATCHES")
    sys.exit(0 if bad == 0 else 1)

perf = vibra["perf"]
if perf.get("thresholds") != oracle["thresholds"]:
    bad += 1; print("THRESHOLDS MISMATCH: vibra", perf.get("thresholds"), "oracle", oracle["thresholds"])
for k in ("analyzedSessions", "unpricedSessions", "skippedSmallSessions"):
    if perf[k] != oracle[k]:
        bad += 1; print(f"COUNT MISMATCH {k}: vibra={perf[k]} oracle={oracle[k]}")

def key_vibra(s):
    (detector, finding), = s["finding"].items()
    return (s["sessionID"], detector), finding

def same_usd(a, b): return a is None and b is None or (a is not None and b is not None and abs(a - b) < 0.005)

v, o = {}, {}
for s in perf["suggestions"]:
    k, f = key_vibra(s)
    if k in v: bad += 1; print("DUPLICATE IN VIBRA", k[0][:8], k[1])
    v[k] = (f, s)
for s in oracle["suggestions"]:
    k = (s["sessionID"], s["detector"])
    if k in o: bad += 1; print("DUPLICATE IN ORACLE", k[0][:8], k[1])
    o[k] = s
for k in sorted(set(v) | set(o)):
    if k not in v: bad += 1; print("MISSING IN VIBRA", k[0][:8], k[1]); continue
    if k not in o: bad += 1; print("EXTRA IN VIBRA", k[0][:8], k[1]); continue
    (vf, vs), os_ = v[k], o[k]
    if vf != os_["finding"]: bad += 1; print("FINDING", k[0][:8], k[1], vf, os_["finding"])
    for field in ("turns", "isLead"):
        if vs[field] != os_[field]: bad += 1; print("FIELD", field, k[0][:8], k[1], vs[field], os_[field])
    if vs["project"] != os_["project"]: bad += 1; print("FIELD project", k[0][:8], k[1], "(values withheld)")
    for field in ("exposureUSD", "sessionValueUSD"):
        if not same_usd(vs.get(field), os_[field]): bad += 1; print("USD", field, k[0][:8], k[1], vs.get(field), os_[field])
print(f"suggestions: vibra={len(v)} oracle={len(o)} leads vibra={sum(s['isLead'] for _, s in v.values())} oracle={sum(s['isLead'] for s in o.values())}")
print("RESULT", "MATCH" if bad == 0 else f"{bad} MISMATCHES")
sys.exit(0 if bad == 0 else 1)
