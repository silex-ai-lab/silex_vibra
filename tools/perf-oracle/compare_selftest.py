"""Failure-path tests for compare.py: privacy of output and duplicate rejection."""
import json, os, subprocess, sys, tempfile
here = os.path.dirname(os.path.abspath(__file__))
sug = {"sessionID": "abcdef0123", "project": "SYNTHETIC_PRIVATE_PROJECT", "turns": 12, "exposureUSD": 1.0, "sessionValueUSD": 5.0, "isLead": True}
oracle = {"claudeTotal": {"input": 1, "output": 2, "cacheCreation": 3, "cacheRead": 4}, "analyzedSessions": 1, "unpricedSessions": 0, "skippedSmallSessions": 0,
          "suggestions": [dict(sug, detector="explorationBurst", finding={"bursts": 1, "burstTurns": 3})]}
def vibra(sugs): return {"agents": [{"agent": "claudeCode", "usage": oracle["claudeTotal"]}], "perf": {"analyzedSessions": 1, "unpricedSessions": 0, "skippedSmallSessions": 0, "suggestions": sugs}}
vs = dict(sug, finding={"explorationBurst": {"bursts": 1, "burstTurns": 3}})
def run(v):
    d = tempfile.mkdtemp(); a, b = os.path.join(d, "v.json"), os.path.join(d, "o.json")
    json.dump(v, open(a, "w")); json.dump(oracle, open(b, "w"))
    p = subprocess.run([sys.executable, "-I", os.path.join(here, "compare.py"), a, b], capture_output=True, text=True)
    return p.returncode, p.stdout
fails = 0
def check(name, cond, out=""):
    global fails; fails += not cond; print(("ok   " if cond else "FAIL ") + name, "" if cond else out)
rc, out = run(vibra([vs])); check("identical inputs match", rc == 0 and "RESULT MATCH" in out, out)
rc, out = run(vibra([dict(vs, project="review")])); check("project mismatch fails without printing values", rc == 1 and "SYNTHETIC_PRIVATE_PROJECT" not in out and "review" not in out, out)
rc, out = run(vibra([vs, vs])); check("duplicate key fails", rc == 1 and "DUPLICATE IN VIBRA" in out, out)
rc, out = run(vibra([dict(vs, exposureUSD=1.004)])); check("dollars within half a cent match", rc == 0, out)
rc, out = run(vibra([dict(vs, exposureUSD=1.006)])); check("dollars beyond half a cent fail", rc == 1, out)
def run_total(v):
    d = tempfile.mkdtemp(); a, b = os.path.join(d, "v.json"), os.path.join(d, "o.json")
    json.dump(v, open(a, "w")); json.dump(oracle, open(b, "w"))
    p = subprocess.run([sys.executable, "-I", os.path.join(here, "compare.py"), "--total-only", a, b], capture_output=True, text=True)
    return p.returncode, p.stdout
rc, out = run_total({"agents": [{"agent": "claudeCode", "usage": oracle["claudeTotal"]}]}); check("--total-only matches without a perf key", rc == 0, out)
rc, out = run_total({"agents": [{"agent": "claudeCode", "usage": dict(oracle["claudeTotal"], cacheRead=5)}]}); check("--total-only fails on a total mismatch", rc == 1, out)
print("RESULT", "PASS" if not fails else f"{fails} FAILED"); sys.exit(1 if fails else 0)
