"""For Claude Code fail->pass test recoveries, classify the test-file edits between them.
Counts only; no text printed.  python3 -I weaken_probe.py <repo> [--days N]"""
import collections, json, os, re, sys, time
sys.argv_repo = sys.argv[1]
sys.path.insert(0, os.path.join(sys.argv[1], "tools/evidence-oracle")); sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import evidence_oracle as o
from tamper_probe_lib import is_test
ASSERT = re.compile(r"\bassert\w*\b|XCTAssert\w*|#expect\b|#require\b|\bexpect\(|\.should\b|\bassert_eq!|\bassert!|t\.(Error|Fatal)f?\(|require\.\w+\(")
SKIP = re.compile(r"pytest\.mark\.(skip|xfail)|\.skip\(|\bxit\(|\bxdescribe\(|\.only\(|XCTSkip|@Disabled|\.disabled\b|t\.Skip|#\[ignore\]|@unittest\.skip|\.todo\(|withKnownIssue")
TESTFN = re.compile(r"\bdef test_\w+|\bfunc test\w+|@Test\b|\bit\(|\btest\(|#\[test\]|func Test\w+\(")
def kinds(name, inp):
    old = inp.get("old_string", "") if name == "Edit" else ""
    new = inp.get("new_string", "") if name == "Edit" else inp.get("content", "")
    if name == "MultiEdit":
        old = "\n".join(e.get("old_string", "") for e in inp.get("edits", []) if isinstance(e, dict))
        new = "\n".join(e.get("new_string", "") for e in inp.get("edits", []) if isinstance(e, dict))
    out = set()
    if name == "Write": out.add("write_whole_file")
    a0, a1 = len(ASSERT.findall(old)), len(ASSERT.findall(new))
    if a1 < a0: out.add("fewer_assertions")
    if len(SKIP.findall(new)) > len(SKIP.findall(old)): out.add("skip_added")
    if len(TESTFN.findall(new)) < len(TESTFN.findall(old)): out.add("fewer_tests")
    if not out: out.add("other")
    return out
days = int(sys.argv[sys.argv.index("--days") + 1]) if "--days" in sys.argv else 30
cut = time.time() - days * 86400; C = collections.Counter()
for files in o.claude_sessions(os.path.expanduser("~"), cut):
    ev = []
    for path in files:
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
        for i in order:
            name, inp, stamp = uses[i]; err, text = results.get(i, (False, None))
            if text is None or err: continue
            if name in o.EDITS:
                p = inp.get("file_path") or inp.get("notebook_path")
                if isinstance(p, str) and o.counts_as_change(p):
                    ev.append((o.when(stamp), "change", is_test(p), kinds(name, inp) if is_test(p) else set()))
            elif name == "Bash" and isinstance(inp.get("command"), str):
                c = o.classify(inp["command"])
                if c and c[0] == "test":
                    ev.append((o.when(stamp), "check", o.result_of(c[1], o.claude_exit(False, text), text, "test", [], "claudeCode"), None))
    ev.sort(key=lambda e: e[0])
    for idx, e in enumerate(ev):
        if e[1] != "check" or not e[2].startswith("failed"): continue
        nxt = next((x for x in ev[idx+1:] if x[1] == "check"), None)
        if not nxt or not nxt[2].startswith("passed"): continue
        between = [x for x in ev if x[1] == "change" and e[0] < x[0] < nxt[0]]
        t = [x for x in between if x[2]]
        if not t: continue
        scope = "only_test_edits" if len(t) == len(between) else "mixed"
        ks = set().union(*(x[3] for x in t))
        C[f"recovery scope={scope}"] += 1
        for k in sorted(ks): C[f"recovery scope={scope} edit_kind={k}"] += 1
        if ks & {"fewer_assertions", "skip_added", "fewer_tests"}: C[f"recovery scope={scope} weakening_any"] += 1
print(f"window_days={days} run_at={time.strftime('%Y-%m-%dT%H:%M:%S')}")
for k in sorted(C): print(f"{k} n={C[k]}")
