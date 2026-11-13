#!/usr/bin/env python3
"""Selftest for wait_oracle.py: every shared fixture scenario byte for byte,
plus unit cases for the arithmetic. Exit 0 when all pass.

Run: python3 -I tools/wait-oracle/oracle_selftest.py
"""
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import wait_oracle as w  # noqa: E402

FIXTURES = os.environ.get("WAIT_FIXTURES") or os.path.join(HERE, "..", "..", "Tests", "VibraCoreTests", "Fixtures", "waits")
failures = []


def check(name, got, want):
    if got != want:
        failures.append("%s: got %r, want %r" % (name, got, want))


def with_tz(tz, fn):
    old = os.environ.get("TZ")
    os.environ["TZ"] = tz
    time.tzset()
    try:
        return fn()
    finally:
        if old is None:
            del os.environ["TZ"]
        else:
            os.environ["TZ"] = old
        time.tzset()


manifest = json.load(open(os.path.join(FIXTURES, "scenarios.json")))
for sc in manifest["scenarios"]:
    home = os.path.join(FIXTURES, sc["name"], "home")
    code, out, err = with_tz(sc["tz"], lambda: w.run(sc["args"].split(), {"VIBRA_HOME": home}))
    check("scenario %s exit" % sc["name"], (code, err), (0, ""))
    check("scenario %s output" % sc["name"], out, sc["expected"])
    if sc.get("sentinel"):
        check("scenario %s leaks no sentinel" % sc["name"], sc["sentinel"] in out + err, False)

check("ms whole", w.epoch_ms("2026-11-10T00:00:00Z"), 1_794_268_800_000)
check("ms .5", w.epoch_ms("2026-11-10T00:00:00.5Z"), 1_794_268_800_500)
check("ms .123456", w.epoch_ms("2026-11-10T00:00:00.123456Z"), 1_794_268_800_123)
check("ms offset", w.epoch_ms("2026-11-10T02:00:00.000+02:00"), 1_794_268_800_000)
check("ms negative offset", w.epoch_ms("2026-11-09T19:00:00.000-05:00"), 1_794_268_800_000)
for bad in ("2026-02-30T00:00:00Z", "2026-11-10T24:00:00Z", "2026-11-10 00:00:00Z", "2026-11-10T00:00:00", "", None, 5):
    check("ms rejects %r" % (bad,), w.epoch_ms(bad), None)
check("ms leap day", w.epoch_ms("2028-02-29T00:00:00Z") is not None, True)

for argv in (["--days", "0"], ["--days", "x"], ["--days"], ["--from", "2026-11-01"], ["--to", "2026-11-01"],
             ["--from", "2026-11-02", "--to", "2026-11-01"], ["--from", "2026-02-30", "--to", "2026-03-01"],
             ["--from", "2026-1-01", "--to", "2026-11-02"], ["--days", "3", "--from", "2026-11-01", "--to", "2026-11-02"]):
    code, out, err = w.run(argv, {"VIBRA_HOME": "/nonexistent"})
    check("usage %s" % " ".join(argv), (code, out, err.startswith("usage:")), (2, "", True))
check("days window", w.parse_window(["--days", "2"], 1_000_000_000_000), (1_000_000_000_000 - 172_800_000, 1_000_000_000_001))
check("default window", w.parse_window([], 1_000_000_000_000), (1_000_000_000_000 - 30 * 86_400_000, 1_000_000_000_001))
check("dst day is 25 h", with_tz("America/Los_Angeles", lambda: w.parse_window(["--from", "2026-11-01", "--to", "2026-11-01"], 0)),
      (1_793_516_400_000, 1_793_606_400_000))
check("VIBRA_NOW rejected", w.run([], {"VIBRA_NOW": "garbage", "VIBRA_HOME": "/nonexistent"})[0], 2)

check("q n=1", [int(q) for q in w.quantiles([5000])], [5000, 5000, 5000])
check("q n=2", [float(q) for q in w.quantiles([0, 1000])], [250.0, 500.0, 750.0])
check("q n=4", [float(q) for q in w.quantiles([4000, 1000, 3000, 2000])], [1750.0, 2500.0, 3250.0])
check("q n=5", [float(q) for q in w.quantiles([1, 2, 3, 4, 100])], [2.0, 3.0, 4.0])
check("union overlap", w.union_ms([(0, 10), (5, 20)]), 20)
check("union touching", w.union_ms([(0, 10), (10, 20)]), 20)
check("union nested", w.union_ms([(0, 100), (10, 20)]), 100)
check("union disjoint", w.union_ms([(0, 10), (20, 25)]), 15)
check("union empty", w.union_ms([]), 0)
check("days at the bound", w.parse_window(["--days", "36500"], 10**13)[0], 10**13 - 36500 * 86_400_000)
for argv in (["--days", "36501"], ["--days", "999999999999999999"], ["--days", "\u0663"], ["--from", "2026-11-\u0660\u0661", "--to", "2026-11-02"]):
    check("usage %r" % argv, w.run(argv, {"VIBRA_HOME": "/nonexistent"})[0], 2)
check("ms rejects year 0", w.epoch_ms("0000-01-01T00:00:00Z"), None)
check("ms rejects non-ASCII digits", w.epoch_ms("2026-11-1\u0660T00:00:00Z"), None)
check("single element", [w.is_single_element(t, "user_shell_command") for t in (
    "<user_shell_command>ls</user_shell_command>", " <user_shell_command>ls</user_shell_command>\n",
    "<user_shell_command>a</user_shell_command><user_shell_command>b</user_shell_command>",
    "<user_shell_command>a<user_shell_command>b</user_shell_command>", "<user_shell_command>ls", "ls")],
    [True, True, False, False, False, False])
odd = [json.dumps(r) for r in (
    {"type": "user", "timestamp": "2026-11-10T00:00:00.000Z", "message": {"content": "hi"}},
    {"type": "assistant", "timestamp": "2026-11-10T00:01:00.000Z", "message": {"id": "a", "stop_reason": "tool_use",
     "content": [{"type": "tool_use", "id": "q", "name": "AskUserQuestion"}]}},
    {"type": "user", "timestamp": "2026-11-10T00:02:00.000Z", "permissionDecision": {"decision": [], "source": "user"},
     "message": {"content": [{"type": "tool_result", "tool_use_id": ["q"]}, {"type": "tool_result", "tool_use_id": "q"}]}})]
check("odd decision and id types do not crash", w.claude_fold(odd).waits, [("question", 1794268860000, 1794268920000, "unknown")])
for argv, code in ((["--from", "9998-12-31", "--to", "9998-12-31"], 0), (["--from", "9999-12-31", "--to", "9999-12-31"], 2),
                   (["--from", "1969-12-31", "--to", "1970-01-01"], 2), (["--from", "1970-01-01", "--to", "1970-01-01"], 0)):
    check("date range %s" % argv, w.run(argv, {"VIBRA_HOME": "/nonexistent"})[0], code)
import tempfile, shutil, contextlib, io
tmp = tempfile.mkdtemp()
try:
    secret = os.path.join(tmp, ".claude", "projects", "SENTINEL_PATH_x1", "SENTINEL_SID_y2.jsonl")
    os.makedirs(os.path.dirname(secret))
    open(secret, "w").write('{"type":"user","timestamp":"2026-11-10T00:00:00.000Z","message":{"content":"hi"}}\n')
    os.chmod(secret, 0)
    stderr = io.StringIO()
    with contextlib.redirect_stderr(stderr):
        code, out, err = w.run(["--from", "2026-11-10", "--to", "2026-11-10"], {"VIBRA_HOME": tmp})
    check("unreadable file: exit 0, nothing printed", (code, out, err, stderr.getvalue()), (0, "", "", ""))
finally:
    os.chmod(secret, 0o600)
    shutil.rmtree(tmp)
check("trim keeps U+001F like Swift", (w.trim("\x1f a \u2003"), w.is_injected_wrapper("\x1f<user_shell_command>ls</user_shell_command>", {"user_shell_command"})), ("\x1f a", False))
check("buckets", [w.bucket(n) for n in (1, 2, 3, 4, 7, 8, 30)], ["1", "2-3", "2-3", "4-7", "4-7", "8+", "8+"])

if failures:
    print("\n".join(failures))
    print("FAIL: %d" % len(failures))
    sys.exit(1)
print("OK: %d scenarios and the unit cases pass" % len(manifest["scenarios"]))
