"""Synthetic contract tests for evidence_oracle.py. Run: python3 -I oracle_selftest.py"""
import json, os, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import evidence_oracle as o

failures = []


def expect(name, got, want):
    if got != want:
        failures.append(f"{name}: got {got!r}, want {want!r}")


cases = [
    ("swift test", ("test", True)),
    ("cd x && swift test", ("test", True)),
    ("swift test && echo ok", ("test", True)),
    ("swift test 2>&1", ("test", True)),
    ("swift test 2>&1 | tail -5", ("test", False)),
    ("swift test | grep FAIL", ("test", False)),
    ("set -o pipefail; swift test | tail", ("test", True)),
    ("swift test; echo done", ("test", False)),
    ("swift test || true", ("test", False)),
    ("swift test\necho done", ("test", False)),
    ("swift test\n", ("test", True)),
    ('git commit -m "make test"', None),
    ("echo 'a; swift test'", None),
    ("cat <<EOF\nswift test\nEOF", None),
    ("FOO=1 timeout 60 pytest -q", ("test", True)),
    ("(cd x && swift test)", ("test", True)),
    (".venv/bin/pytest", ("test", True)),
    ("npm run typecheck", ("lint", True)),
    ("swift build && swift test | tail", ("test", False)),
    ("swift build && make test", ("test", True)),
    ("uv run pytest", ("test", True)),
    ("uv run --with x --python 3.12 pytest -q", ("test", True)),
    ("timeout 600 uv run --extra dev python -m pytest", ("test", True)),
    ("uv run script.py", None),
    ("for x in a; do swift test; done", ("test", False)),
    ("cat x | pytest", None),
    ("make bench", None),
    ("npm install", None),
]
for script, want in cases:
    expect(script, o.classify(script), want)

expect("summary pass", o.summary("Test run with 3 tests in 1 suite passed after 0.1 seconds."), True)
expect("summary fail", o.summary("Test run with 3 tests in 1 suite failed after 0.1 seconds with 1 issue."), False)
expect("summary undecided", o.summary("nothing useful"), None)
expect("summary fail beats pass", o.summary("2 passed\n1 failed"), False)
expect("summary reads the tail only", o.summary("1 failed\n" + "x" * 7000), None)

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
expect("claude replayed use counted once", [l for l in out if l.startswith("change")], ["change agent=claudeCode n=1"])

print("\n".join(failures) if failures else f"OK {len(cases)} classify cases and contracts")
sys.exit(1 if failures else 0)
