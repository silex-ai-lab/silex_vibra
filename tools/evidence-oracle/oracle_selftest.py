"""Synthetic contract tests for evidence_oracle.py. Run: python3 -I oracle_selftest.py"""
import json, os, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import evidence_oracle as o

failures = []


def expect(name, got, want):
    if got != want:
        failures.append(f"{name}: got {got!r}, want {want!r}")


shared = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../Tests/VibraCoreTests/Fixtures/evidence-cases.json")))
for item in shared["classify"]:
    want = (item["kind"], item["proof"]) if item["kind"] else None
    expect(item["script"], o.classify(item["script"]), want)
for item in shared["summary"]:
    expect(item["tail"], o.summary(item["tail"], item["kind"]), item["verdict"])

expect("doc is no change", o.counts_as_change("/r/README.md"), False)
expect("temp is no change", o.counts_as_change("/private/tmp/a.py"), False)
expect("code is change", o.counts_as_change("/r/a.swift"), True)
expect("no extension is change", o.counts_as_change("/r/Makefile"), True)


def claude_line(stamp, blocks, role="assistant"):
    return json.dumps({"type": role, "sessionId": "s1", "timestamp": stamp, "message": {"role": role, "content": blocks}})


T = "2026-11-08T10:%02d:00.000Z"
home = tempfile.mkdtemp()
root = os.path.join(home, ".claude/projects/p")
os.makedirs(os.path.join(root, "s1/subagents"))
with open(os.path.join(root, "s1.jsonl"), "w") as f:
    use = {"type": "tool_use", "id": "e1", "name": "Edit", "input": {"file_path": "/r/a.swift"}}
    f.write(claude_line(T % 1, [use]) + "\n")
    f.write(claude_line(T % 1, [use]) + "\n")
    f.write(claude_line(T % 2, [{"type": "tool_result", "tool_use_id": "e1", "content": "ok"}], "user") + "\n")
with open(os.path.join(root, "s1/subagents/agent-a.jsonl"), "w") as f:
    f.write(claude_line(T % 3, [{"type": "tool_use", "id": "b1", "name": "Bash", "input": {"command": "swift test | tail"}}]) + "\n")
    f.write(claude_line(T % 4, [{"type": "tool_result", "tool_use_id": "b1", "is_error": False, "content": "12 passed"}], "user") + "\n")
out = o.run(home, 100000, False)
expect("claude case", [l for l in out if l.startswith("case")], ["case agent=claudeCode case=checkedAfterLastChange n=1"])
expect("claude check", [l for l in out if l.startswith("check")], ["check agent=claudeCode kind=test result=passed.runnerSummary n=1"])
expect("claude replayed use counted once", [l for l in out if l.startswith("change")], ["change agent=claudeCode target=source n=1"])

# Test paths, rooted at the workspace (plan v0.4, "Test path").
H, R = "/Users/test", "/Users/test/app"
for raw, cwd, want in [
    (R + "/src/main.py", R, False), (R + "/tests/test_x.py", R, True), (R + "/conftest.py", R, True),
    (R + "/tests/fixtures/a.py", R, False), (R + "/test_data/x.py", R, False), (R + "/tests/helpers.py", R, True),
    ("/other/tests/helpers.py", R, False), ("/other/tests/test_y.py", R, True), ("/x/tests/helpers.py", None, False),
    ("src/a_test.go", R, True), ("Sources/AppTests.swift", R, True), ("web/a.spec.tsx", R, True),
    (R + "/Tests/VibraCoreTests/Fixtures/x.swift", R, False), (R + "/specs/a.rb", R, True),
]:
    expect(f"test path {raw} @ {cwd}", o.is_test_path(raw, cwd, H), want)

# Normative regex table: pinned non-matches and matches (plan v0.4 task 2).
for text in ["wait(", "exit(", "split(", "x.shoulder", "latest(", "asser", "button.disabled", "iter().skip(1)",
             "stream.skip(n)", "re.test(x)", "require.resolve(", 'qs.only("id")', "model.fit(x)"]:
    expect(f"no match {text}", {f: n for f, n in o.pattern_counts(text).items() if n}, {})
for fam, text in [("assertion", "require.NoError(t, err)"), ("skip", '@Test(.disabled("x"))'), ("skip", "it.skip("),
                  ("skip", "self.skipTest("), ("focus", "test.only("), ("focus", "fit("), ("expectedFailure", "test.failing("),
                  ("expectedFailure", "XCTExpectFailure"), ("testFunction", "def test_a"), ("assertion", "#expect(a)")]:
    expect(f"match {fam} {text}", o.pattern_counts(text)[fam], 1)
expect("commented-out assertion is not counted", o.pattern_counts("// assert(x)\n  # assert y\n#expect(z)")["assertion"], 1)


# Clause rule (plan v0.4 "When the clause shows"), one Claude session per case.
def stamp(s):
    return "2026-11-08T10:%02d:%06.3fZ" % (int(s) // 60, s % 60)


def rec(role, s, block, cwd=R):
    r = {"type": role, "sessionId": "s1", "cwd": cwd, "message": {"role": role, "content": [block]}}
    if s is not None:
        r["timestamp"] = stamp(s)
    return json.dumps(r)


class Session:
    def __init__(self):
        self.lines, self.n = [], 0

    def call(self, name, inp, at, done, ok=True, text="ok"):
        self.n += 1
        i = f"c{self.n}"
        self.lines.append(rec("assistant", at, {"type": "tool_use", "id": i, "name": name, "input": inp}))
        if done is not False:
            self.lines.append(rec("user", done, {"type": "tool_result", "tool_use_id": i, "is_error": not ok, "content": text}))
        return self

    def test(self, at, done, passed=True):
        return self.call("Bash", {"command": "swift test"}, at, done, ok=passed, text="ok" if passed else "Exit code 1")

    def build(self, at, done):
        return self.call("Bash", {"command": "swift build"}, at, done)

    def edit(self, at, done, old, new, path=R + "/tests/test_x.py", **extra):
        return self.call("Edit", dict({"file_path": path, "old_string": old, "new_string": new}, **extra), at, done)

    def write(self, at, done, path):
        return self.call("Write", {"file_path": path, "content": "assert a\nassert b"}, at, done)

    def run(self):
        h = tempfile.mkdtemp()
        os.makedirs(os.path.join(h, ".claude/projects/p"))
        with open(os.path.join(h, ".claude/projects/p/s1.jsonl"), "w") as f:
            f.write("\n".join(self.lines) + "\n")
        out = o.run(h, 100000, False)
        return sorted(l.split("effect=")[1].split(" ")[0] for l in out if l.startswith("qualified")), \
            [l for l in out if l.startswith("case")]


A, B = R + "/tests/test_a.py", R + "/tests/test_b.py"
cases = [
    ("fail, assertion removed, pass", Session().test(1, 2, False).edit(3, 4, "assert x", "").test(5, 6), ["fewerAssertionMatches"]),
    ("passed test between F and P", Session().test(1, 2, False).edit(3, 4, "assert x", "").test(5, 6).test(7, 8), []),
    ("unknown test between F and P", Session().test(1, 2, False).edit(3, 4, "assert x", "").test(5, False).test(7, 8), []),
    ("edit made while F ran", Session().test(1, 2, False).edit(1.2, 1.8, "assert x", "").edit(3, 4, "a", "b", path=R + "/src/m.py").test(5, 6), []),
    ("F has no completedAt", Session().test(1, None, False).edit(3, 4, "assert x", "").test(5, 6), []),
    ("edit straddles P", Session().test(1, 2, False).edit(3, 6, "assert x", "").test(5, 7), []),
    ("removal inside, restoration straddles P", Session().test(1, 2, False).edit(3, 4, "assert x", "").edit(4.5, 6, "", "assert x").test(5, 7), []),
    ("second edit straddles F.completedAt", Session().test(1, 2, False).edit(1.5, 2.5, "", "assert x").edit(3, 4, "assert x", "").test(5, 6), []),
    ("assertion moved between files", Session().test(1, 2, False).edit(3, 4, "assert x", "", path=A).edit(3.5, 4, "", "assert x", path=B).test(5, 6), []),
    ("source-only edit", Session().test(1, 2, False).edit(3, 4, "assert x", "", path=R + "/src/m.py").test(5, 6), []),
    ("source edit plus assertion removal", Session().test(1, 2, False).edit(3, 4, "a", "b", path=R + "/src/m.py").edit(3.5, 4, "assert x", "").test(5, 6), ["fewerAssertionMatches"]),
    ("replace_all on the only file", Session().test(1, 2, False).edit(3, 4, "assert x", "", replace_all=True).test(5, 6), []),
    ("string-only change", Session().test(1, 2, False).edit(3, 4, 'msg = "assert(x)"', 'msg = ""').test(5, 6), ["fewerAssertionMatches"]),
    ("skip added then removed", Session().test(1, 2, False).edit(3, 4, "", "@unittest.skip").edit(4.2, 4.5, "@unittest.skip", "").test(5, 6), []),
    ("assertion removed then restored", Session().test(1, 2, False).edit(3, 4, "assert x", "").edit(4.2, 4.5, "", "assert x").test(5, 6), []),
    ("assertion moved within one file", Session().test(1, 2, False).edit(3, 4, "assert x\ny = 1", "y = 1\nassert x").test(5, 6), []),
    ("Write on the only file", Session().test(1, 2, False).write(3, 4, A).test(5, 6), []),
    ("passed build reported", Session().test(1, 2, False).edit(3, 4, "assert x", "").build(5, 6), []),
    ("two effects in order", Session().test(1, 2, False).edit(3, 4, "assert x", "@unittest.skip").test(5, 6), ["fewerAssertionMatches", "moreSkipMatches"]),
    ("build between F and P keeps adjacency", Session().test(1, 2, False).edit(3, 4, "assert x", "").build(4.5, 4.8).test(5, 6), ["fewerAssertionMatches"]),
    ("assertions moved into a written file", Session().test(1, 2, False).edit(3, 4, "assert x", "", path=A).write(3.5, 4, B).test(5, 6), ["fewerAssertionMatches"]),
]
for name, sess, want in cases:
    expect(f"clause: {name}", sess.run()[0], want)
expect("change at exactly P.at", Session().test(1, 2, False).edit(5, 5.5, "assert x", "").test(5, 6).run()[1],
       ["case agent=claudeCode case=changedAfterLastCheck n=1"])

print("\n".join(failures) if failures else f"OK {len(shared['classify'])} classify and {len(shared['summary'])} summary cases and contracts")
sys.exit(1 if failures else 0)
