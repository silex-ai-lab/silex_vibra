"""Prevalence of 'test file edited between a failed and a passing test run'.
Counts only. No path, command or text is printed.
    python3 -I tamper_probe.py <repo> [--days N]
"""
import collections, json, os, re, sys, time
repo = sys.argv[1]
sys.path.insert(0, os.path.join(repo, "tools/evidence-oracle"))
import evidence_oracle as o

TEST_DIR = re.compile(r"(^|/)(tests?|__tests__|spec|specs|Tests|testing|test_data|fixtures?)/")
TEST_FILE = re.compile(r"(^|/)(test_[^/]+\.py|[^/]+_test\.(py|go|rs|rb)|[^/]+\.(test|spec)\.[jt]sx?|[^/]+Tests?\.(swift|java|kt)|conftest\.py)$")
def is_test(p): return bool(TEST_DIR.search(p) or TEST_FILE.search(p))

def fold_claude(path):
    uses, results, order = {}, {}, []
    for line in open(path, errors="replace"):
        try: r = json.loads(line)
        except Exception: continue
        m = r.get("message")
        if not isinstance(m, dict) or not isinstance(m.get("content"), list): continue
        for b in m["content"]:
            if not isinstance(b, dict): continue
            if b.get("type") == "tool_use" and b.get("id") not in uses and r.get("timestamp"):
                uses[b["id"]] = (b.get("name"), b.get("input") or {}, r["timestamp"]); order.append(b["id"])
            elif b.get("type") == "tool_result":
                results.setdefault(b.get("tool_use_id"), (b.get("is_error") is True, o.body(b.get("content"))))
    ev = []
    for i in order:
        name, inp, stamp = uses[i]
        err, text = results.get(i, (False, None))
        if text is None or (err and text.startswith(o.NEVER_RAN)): continue
        if name in o.EDITS:
            p = inp.get("file_path") or inp.get("notebook_path")
            if isinstance(p, str) and not err and o.counts_as_change(p):
                ev.append((o.when(stamp), "change", is_test(p)))
        elif name == "Bash" and isinstance(inp.get("command"), str):
            c = o.classify(inp["command"])
            if c and c[0] == "test":
                proof = "none" if inp.get("run_in_background") is True else c[1]
                ev.append((o.when(stamp), "check", o.result_of(proof, o.claude_exit(err, text), text, "test", [], "claudeCode")))
    return ev

def fold_codex(path):
    ev = []
    for line in open(path, errors="replace"):
        if '"item_completed"' not in line: continue
        try: r = json.loads(line)
        except Exception: continue
        p = r.get("payload"); stamp = r.get("timestamp")
        if r.get("type") != "event_msg" or not isinstance(p, dict) or p.get("type") != "item_completed" or not stamp: continue
        it = p.get("item")
        if not isinstance(it, dict): continue
        if it.get("type") == "CommandExecution" and isinstance(it.get("command"), list) and it.get("status") in ("completed", "failed"):
            cmd = it["command"]; script = cmd[2] if len(cmd) >= 3 and cmd[1] in ("-lc", "-c") else " ".join(map(str, cmd))
            c = o.classify(script)
            if c and c[0] == "test":
                ev.append((o.when(stamp), "check", o.result_of(c[1], it.get("exit_code"), it.get("aggregated_output") or "", "test", [], "codex")))
        elif it.get("type") == "FileChange" and isinstance(it.get("changes"), dict) and it.get("status") == "completed":
            for k in it["changes"]:
                if o.counts_as_change(str(k)): ev.append((o.when(stamp), "change", is_test(str(k))))
    return ev

days = int(sys.argv[sys.argv.index("--days") + 1]) if "--days" in sys.argv else 30
home = os.path.expanduser("~"); cut = time.time() - days * 86400
C = collections.Counter()
for agent, sessions, fold in [("claudeCode", o.claude_sessions(home, cut), fold_claude), ("codex", o.codex_sessions(home, cut), fold_codex)]:
    for files in sessions:
        ev = sorted(e for f in files for e in fold(f))
        C[f"{agent} sessions"] += 1
        tests = [e for e in ev if e[1] == "check"]
        if tests: C[f"{agent} sessions_with_test_check"] += 1
        hit_any = hit_only = False
        for idx, e in enumerate(ev):
            if e[1] != "check" or not e[2].startswith("failed"): continue
            # next test check after this failure
            nxt = next((x for x in ev[idx+1:] if x[1] == "check"), None)
            if not nxt: continue
            between = [x for x in ev if x[1] == "change" and e[0] < x[0] < nxt[0]]
            if nxt[2].startswith("passed"):
                C[f"{agent} fail_then_pass"] += 1
                t = [x for x in between if x[2]]
                if t:
                    C[f"{agent} fail_then_pass_with_test_edit"] += 1; hit_any = True
                    if len(t) == len(between):
                        C[f"{agent} fail_then_pass_only_test_edits"] += 1; hit_only = True
        if hit_any: C[f"{agent} sessions_with_test_edit_recovery"] += 1
        if hit_only: C[f"{agent} sessions_with_only_test_edit_recovery"] += 1
        C[f"{agent} test_file_changes"] += sum(1 for e in ev if e[1] == "change" and e[2])
        C[f"{agent} changes"] += sum(1 for e in ev if e[1] == "change")
print(f"window_days={days} run_at={time.strftime('%Y-%m-%dT%H:%M:%S')}")
for k in sorted(C): print(f"{k} n={C[k]}")
