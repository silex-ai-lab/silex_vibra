#!/usr/bin/env python3
"""Writes the shared `--wait-stats` fixture trees (synthetic records only).

Run: python3 -I tools/wait-oracle/make_fixtures.py
Output: Tests/VibraCoreTests/Fixtures/waits/<scenario>/home/... . The expected
outputs live in Tests/VibraCoreTests/Fixtures/waits/scenarios.json, written by
hand from the plan's spec, never from a run of either implementation.
"""
import json
import os
import shutil

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "Tests", "VibraCoreTests", "Fixtures", "waits")
CWD = "/Users/test/app"


def T(day, hms):
    return "2026-11-%sT%sZ" % (day, hms)


def cu(ts, content, **extra):
    r = {"type": "user", "timestamp": ts, "sessionId": "s", "cwd": CWD, "message": {"role": "user", "content": content}}
    r.update(extra)
    return r


def ca(ts, mid, stop, content=None, **extra):
    r = {"type": "assistant", "timestamp": ts, "sessionId": "s", "cwd": CWD,
         "message": {"id": mid, "role": "assistant", "stop_reason": stop, "content": content or [{"type": "text", "text": "ok"}]}}
    r.update(extra)
    return r


def use(tid, name, inp=None):
    return {"type": "tool_use", "id": tid, "name": name, "input": inp or {}}


def res(ts, ids, decision=None, content="done"):
    r = cu(ts, [{"type": "tool_result", "tool_use_id": i, "content": content} for i in ids])
    if decision is not None:
        r["permissionDecision"] = decision
    return r


USER_OK = {"decision": "accept", "source": "user_temporary", "grantScope": "once"}
USER_NO = {"decision": "reject", "source": "user_reject"}
CONFIG_OK = {"decision": "accept", "source": "config", "reasonType": "classifier"}


def xm(ts, payload_type=None, kind="event_msg", **payload):
    if payload_type is not None:
        payload["type"] = payload_type
    return {"type": kind, "timestamp": ts, "payload": payload}


def xuser(ts, *texts):
    return xm(ts, "message", "response_item", role="user", content=[{"type": "input_text", "text": t} for t in texts])


def xmeta(ts, source="cli", originator="codex-tui", sid="x"):
    return xm(ts, None, "session_meta", id=sid, session_id=sid, cwd=CWD, originator=originator, source=source)


def started(ts, trigger="user"):
    return xm(ts, "task_started", turn_attribution={"turn_trigger": trigger})


def write(scenario, rel, records, raw_lines=()):
    path = os.path.join(ROOT, scenario, "home", rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        for r in records:
            fh.write(json.dumps(r, sort_keys=True) + "\n")
        for line in raw_lines:
            fh.write(line + "\n")


D = "10"
claude_basic = [
    cu(T(D, "10:00:00.000"), "fix the bug"),
    ca(T(D, "10:00:05.000"), "m1", "end_turn"),
    ca(T(D, "10:00:06.500"), "m1", "end_turn"),
    ca(T(D, "10:00:06.600"), "m1", None),
    {"type": "system", "subtype": "turn_duration", "timestamp": T(D, "10:00:06.700")},
    cu(T(D, "10:05:06.500"), "now the tests"),
    ca(T(D, "10:05:10.000"), "m2", "tool_use", [use("tu1", "AskUserQuestion", {"questions": []})]),
    res(T(D, "10:06:10.000"), ["tu1"], USER_OK),
    res(T(D, "10:06:11.000"), ["tu1"], USER_OK),
    ca(T(D, "10:06:20.000"), "m3", "tool_use", [use("tu2", "Bash")]),
    res(T(D, "10:06:21.000"), ["tu2"], CONFIG_OK),
    ca(T(D, "10:07:00.000"), "m4", "tool_use", [use("tu3", "Bash"), use("tu4", "Bash")]),
    res(T(D, "10:07:30.000"), ["tu3", "tu4"], USER_NO),
    ca(T(D, "10:08:00.000"), "m5", "tool_use", [use("tu1", "AskUserQuestion")]),
    res(T(D, "10:08:30.000"), ["tu1"], USER_OK),
    ca(T(D, "10:09:00.000"), "m6", "end_turn"),
    cu(T(D, "10:10:00.000"), "injected meta text", isMeta=True),
    {"type": "user", "sessionId": "s", "cwd": CWD, "message": {"role": "user", "content": "no timestamp"}},
    cu(T(D, "10:11:00.000"), "<task-notification>job done</task-notification>"),
    ca(T(D, "10:11:05.000"), "m7", "tool_use", [use("tu5", "Read")]),
    res(T(D, "10:11:06.000"), ["tu5"], CONFIG_OK),
    ca(T(D, "10:12:00.000"), "m8", "end_turn"),
    cu(T(D, "10:20:00.000"), "<command-message>review</command-message>\n<command-name>/review</command-name>"),
    ca(T(D, "10:21:00.000"), "m9", "end_turn"),
    ca(T(D, "10:21:30.000"), "meta1", "end_turn", isMeta=True),
    cu(T(D, "10:22:00.000"), "<command-name>/clear</command-name>\n<command-message>clear</command-message>\n<command-args></command-args>"),
    ca(T(D, "10:30:00.000"), "m10", "end_turn"),
]

claude_mixed = [
    cu(T(D, "09:00:00.000"), "start"),
    ca(T(D, "09:01:00.000"), "x1", "end_turn"),
    cu(T(D, "09:05:00.000"), "Dispatch claude-impl-r1: please <command-name>/x</command-name>"),
    ca(T(D, "09:06:00.000"), "x2", "tool_use", [use("tu9", "Bash")]),
    res(T(D, "09:07:00.000"), ["tu9"], USER_OK),
    ca(T(D, "09:08:00.000"), "x3", "end_turn"),
    cu(T(D, "09:10:00.000"), "<bash-input>ls</bash-input>"),
    cu(T(D, "09:10:01.000"), "<local-command-stdout>out</local-command-stdout>"),
    cu(T(D, "09:15:00.000"), [{"type": "text", "text": '<pasted_content id="p1">next</pasted_content>'}]),
    ca(T(D, "09:16:00.000"), "x4", "end_turn"),
    cu(T(D, "09:17:00.000"), "<task-notification>job <command-name>/x</command-name> done</task-notification>"),
    cu(T(D, "09:20:00.000"), "thanks"),
]
seat_only = [
    cu(T(D, "09:00:00.000"), "Dispatch claude-plan-r1: read the prompt"),
    ca(T(D, "09:01:00.000"), "d1", "tool_use", [use("tq", "AskUserQuestion")]),
    res(T(D, "09:02:00.000"), ["tq"], USER_OK),
    ca(T(D, "09:03:00.000"), "d2", "end_turn"),
]
subagent = [dict(r, isSidechain=True) for r in [
    cu(T(D, "09:30:00.000"), "subagent task"),
    ca(T(D, "09:31:00.000"), "y1", "end_turn"),
    cu(T(D, "09:40:00.000"), "more"),
]]
scheduled = [
    cu(T(D, "06:00:00.000"), '<scheduled-task name="nightly">run it</scheduled-task>'),
    ca(T(D, "06:01:00.000"), "z1", "end_turn"),
    cu(T(D, "06:30:00.000"), "follow up"),
]
sdk = [dict(r, entrypoint="sdk-cli") for r in [
    cu(T(D, "07:00:00.000"), "scripted"),
    ca(T(D, "07:01:00.000"), "z2", "end_turn"),
    cu(T(D, "07:30:00.000"), "scripted again"),
]]

codex_main = [
    xmeta(T(D, "08:00:00.000")),
    started(T(D, "08:00:01.000")),
    xuser(T(D, "08:00:02.000"), "<environment_context>x</environment_context>", "do it"),
    xm(T(D, "08:00:03.000"), "reasoning", "response_item", summary=[]),
    xm(T(D, "08:01:00.000"), "task_complete"),
    started(T(D, "08:02:00.000"), "automation_heartbeat_schedule"),
    xuser(T(D, "08:02:01.000"), "<heartbeat>tick</heartbeat>"),
    xm(T(D, "08:02:30.000"), "message", "response_item", role="assistant", content=[]),
    xm(T(D, "08:03:00.000"), "task_complete"),
    started(T(D, "08:10:00.000")),
    xuser(T(D, "08:10:01.000"), "next"),
    xm(T(D, "08:11:00.000"), "task_complete"),
    xm(T(D, "08:11:01.000"), "item_completed"),
    xuser(T(D, "08:15:00.000"), "again"),
    xm(T(D, "08:16:00.000"), "task_complete"),
    xm(T(D, "08:16:30.000"), "turn_aborted"),
    started(T(D, "08:17:00.000")),
    xuser(T(D, "08:17:10.000"), "<user_shell_command>ls</user_shell_command>"),
    xm(T(D, "08:18:00.000"), "task_complete"),
    xm(T(D, "08:18:30.000"), "function_call", "response_item", name="exec"),
    xm(T(D, "08:19:00.000"), "task_complete"),
    xuser(T(D, "08:25:00.000"), "Dispatch q1-codex: go"),
    xm(T(D, "08:26:00.000"), "task_complete"),
    xuser(T(D, "08:30:00.000"), "fin"),
    xm(T(D, "08:31:00.000"), "task_complete"),
]
codex_sub = [xmeta(T(D, "08:00:00.000"), source={"subagent": {"other": "guardian"}}),
             xuser(T(D, "08:00:01.000"), "check this"), xm(T(D, "08:01:00.000"), "task_complete"),
             xuser(T(D, "08:05:00.000"), "and this")]
codex_spawn = [xmeta(T(D, "08:00:00.000"), source={"subagent": {"thread_spawn": {"depth": 1}}}),
               xuser(T(D, "08:00:01.000"), "spawned"), xm(T(D, "08:01:00.000"), "task_complete"),
               xuser(T(D, "08:05:00.000"), "again")]
codex_exec = [xmeta(T(D, "08:00:00.000"), source="exec", originator="codex_exec"),
              xuser(T(D, "08:00:01.000"), "scripted"), xm(T(D, "08:01:00.000"), "task_complete"),
              xuser(T(D, "08:05:00.000"), "scripted again")]
codex_not_rollout = [xmeta(T(D, "08:00:00.000")), xuser(T(D, "08:00:01.000"), "hi"),
                     xm(T(D, "08:01:00.000"), "task_complete"), xuser(T(D, "08:09:00.000"), "there")]

edges = {
    "e1": [cu("2026-11-10T01:00:00.000+02:00", "before"), ca(T("09", "23:30:00.000"), "a1", "end_turn"),
           cu(T(D, "00:00:00.000"), "at lo")],
    "e2": [cu(T(D, "23:00:00.000"), "late"), ca(T(D, "23:59:00.000"), "a2", "end_turn"),
           cu(T("11", "00:00:00.000"), "at hi")],
    "e3": [cu(T("09", "08:00:00.000"), "ask me"),
           ca(T("09", "09:00:00.000"), "a3", "tool_use", [use("tq3", "AskUserQuestion")]),
           res(T(D, "01:00:00.000"), ["tq3"])],
    "e4": [cu(T(D, "02:00:00.5"), "half millisecond"), ca(T(D, "03:00:00.000"), "a4", "end_turn"),
           cu(T(D, "05:00:00.000"), "exactly at cap"), ca(T(D, "05:30:00.000"), "a5", "end_turn"),
           cu(T(D, "07:30:00.001"), "one ms over")],
}

dst = {
    "d1": [cu("2026-11-01T06:00:00.000Z", "before lo"), ca("2026-11-01T06:30:00.000Z", "b1", "end_turn"),
           cu("2026-11-01T07:00:00.000Z", "at local midnight")],
    "d2": [cu("2026-11-02T07:30:00.000Z", "23:30 PST"), ca("2026-11-02T07:40:00.000Z", "b2", "end_turn"),
           cu("2026-11-02T08:00:00.000Z", "at hi")],
    "d3": [cu("2026-11-01T08:10:00.000Z", "inside"), ca("2026-11-01T08:20:00.000Z", "b3", "end_turn"),
           cu("2026-11-01T08:21:00.000Z", "a minute later")],
}

S = "SENTINEL"
sentinel_claude = [dict(r, sessionId=S + "_SID_3a2", cwd="/Users/x/" + S + "_CWD_7c4") for r in [
    cu(T(D, "12:00:00.000"), S + "_PROMPT_5e8 do"),
    ca(T(D, "12:01:00.000"), "s1", "tool_use", [use("tA", "AskUserQuestion", {"q": S + "_INPUT_2b6"})]),
    res(T(D, "12:02:00.000"), ["tA"], USER_OK, content=S + "_RESULT_8d0"),
    ca(T(D, "12:03:00.000"), "s2", "tool_use", [use("tB", "Bash", {"command": S + "_INPUT_2b6"})]),
    res(T(D, "12:04:00.000"), ["tB"], USER_OK, content=S + "_RESULT_8d0"),
    ca(T(D, "12:05:00.000"), "s3", "end_turn", [{"type": "text", "text": S + "_REPLY_1f3"}]),
    cu(T(D, "12:10:00.000"), S + "_PROMPT_5e8 again"),
]]
sentinel_codex = [
    xmeta(T(D, "12:00:00.000"), sid=S + "_SID_3a2"),
    started(T(D, "12:00:00.500")),
    xuser(T(D, "12:00:01.000"), S + "_PROMPT_5e8"),
    xm(T(D, "12:01:00.000"), "task_complete", last_agent_message=S + "_REPLY_1f3"),
    xuser(T(D, "12:03:00.000"), S + "_PROMPT_5e8 more"),
]


def main():
    if os.path.isdir(ROOT):
        for entry in os.listdir(ROOT):
            if os.path.isdir(os.path.join(ROOT, entry)):
                shutil.rmtree(os.path.join(ROOT, entry))
    P = ".claude/projects/-Users-test-app/"
    X = ".codex/sessions/2026/11/10/"
    write("claude-basic", P + "basic.jsonl", claude_basic)
    for scen in ("claude-dispatch", "both"):
        write(scen, P + "mixed.jsonl", claude_mixed)
        write(scen, P + "seat.jsonl", seat_only)
        write(scen, P + "mixed/subagents/agent-1.jsonl", subagent)
        write(scen, P + "scheduled.jsonl", scheduled)
        write(scen, P + "sdk.jsonl", sdk)
    for scen in ("codex-turns", "both"):
        write(scen, X + "rollout-2026-11-10T08-00-00-main.jsonl", codex_main)
        write(scen, X + "rollout-2026-11-10T08-00-00-sub.jsonl", codex_sub)
        write(scen, X + "rollout-2026-11-10T08-00-00-spawn.jsonl", codex_spawn)
        write(scen, X + "rollout-2026-11-10T08-00-00-exec.jsonl", codex_exec)
        write(scen, X + "notes.jsonl", codex_not_rollout)
    for name, recs in edges.items():
        write("window-edges", P + name + ".jsonl", recs)
    for name, recs in dst.items():
        write("dst", P + name + ".jsonl", recs)
    write("sentinel", ".claude/projects/-Users-x-" + S + "_PATH_9f1/" + S + "_SID_3a2.jsonl", sentinel_claude)
    write("sentinel", X + "rollout-2026-11-10T12-00-00-" + S + "_SID_3a2.jsonl", sentinel_codex)
    write("empty", P + "scheduled.jsonl", scheduled)
    write("empty", P + "sdk.jsonl", sdk)
    write("empty", P + "seat.jsonl", seat_only)


if __name__ == "__main__":
    main()
