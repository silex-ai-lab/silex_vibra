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
expect("claude replayed use counted once", [l for l in out if l.startswith("change")], ["change agent=claudeCode n=1"])

print("\n".join(failures) if failures else f"OK {len(shared['classify'])} classify and {len(shared['summary'])} summary cases and contracts")
sys.exit(1 if failures else 0)
