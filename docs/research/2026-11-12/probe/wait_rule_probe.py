"""Counts-only checks of the wait rules' assumptions (plan v0.4: Codex folded under the v0.4 rules). Prints tag names, record types and counts; never text."""
import collections, glob, hashlib, json, os, re, time

CUT = time.time() - 30 * 86400
CLAUDE_TAGS = {"command-name", "command-message", "command-args", "local-command-stdout", "local-command-stderr",
               "local-command-caveat", "system-reminder", "task-notification", "bash-input", "bash-stdout", "bash-stderr"}
CODEX_TAGS = {"environment_context", "turn_aborted", "user_instructions"}
CODEX_TAGS_V04 = CODEX_TAGS | {"heartbeat", "task-notification", "user_shell_command", "realtime_delegation", "command-name", "command-message", "command-args", "local-command-stdout"}
DISPATCH = re.compile(r"Dispatch `?[\w.-]+`?:")


def strip(text, tags):
    for t in tags:
        text = re.sub(r"<%s(\s[^>]*)?>[\s\S]*?</%s>" % (re.escape(t), re.escape(t)), "", text)
    return text.strip()


def lead_tag(s):
    m = re.match(r"<([A-Za-z_][\w-]*)", s)
    return m.group(1) if m else None


def files(root):
    return [f for f in glob.glob(os.path.expanduser(root) + "/**/*.jsonl", recursive=True) if os.path.getmtime(f) > CUT]


out = collections.Counter()
uuid_files = collections.defaultdict(set)
for f in files("~/.claude/projects"):
    sub = "/subagents/" in f
    first, scheduled, entry = True, False, None
    human_prompts, dialogs, uses = 0, 0, {}
    for line in open(f, errors="ignore"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        entry = entry or r.get("entrypoint")
        if sub and r.get("type") in ("user", "assistant") and r.get("isSidechain") is not True:
            out[("claude", "subagent file record without isSidechain")] += 1
        if r.get("type") == "assistant" and (r.get("message") or {}).get("stop_reason") == "end_turn" and not r.get("isSidechain"):
            uuid_files[r.get("uuid")].add(f)
        if r.get("type") == "assistant" and not r.get("isSidechain"):
            out[("claude", "stop_reason", (r.get("message") or {}).get("stop_reason"))] += 1
            for b in (r.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    uses[b.get("id")] = b.get("name")
        if r.get("type") == "user" and not r.get("isSidechain") and isinstance((r.get("message") or {}).get("content"), list):
            pd = r.get("permissionDecision") or {}
            for b in r["message"]["content"]:
                if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("tool_use_id") in uses:
                    if uses[b["tool_use_id"]] == "AskUserQuestion" or str(pd.get("source", "")).startswith("user"):
                        dialogs += 1
        if r.get("type") != "user":
            continue
        c = (r.get("message") or {}).get("content")
        if first and isinstance(c, str):
            first, scheduled = False, "<scheduled-task" in c
        if scheduled or entry == "sdk-cli" or r.get("isMeta") or r.get("isSidechain"):
            continue
        if isinstance(c, list):
            if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
                continue
            c = "\n".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
        if not isinstance(c, str):
            continue
        raw = c.strip()
        typed = re.sub(r"</?pasted_content[^>]*>", "", strip(raw, CLAUDE_TAGS)).strip()
        if not typed:
            out[("claude", "dropped wrapper-only", lead_tag(raw))] += 1
            continue
        if typed.startswith("[Request interrupted by user"):
            continue
        tag = lead_tag(typed)
        kind = "dispatch" if DISPATCH.match(typed) else "human"
        human_prompts += kind == "human"
        out[("claude", "prompt", kind, "leading tag " + (tag or "-"))] += 1
    if not sub and human_prompts == 0 and dialogs:
        out[("claude", "transcripts with no human prompt but human-answered dialogs")] += 1
        out[("claude", "human-answered dialogs in those transcripts")] += dialogs
out[("claude", "end_turn uuids in more than one file")] = sum(1 for v in uuid_files.values() if len(v) > 1)

prompt_files = collections.defaultdict(set)
for f in files("~/.codex/sessions"):
    meta, kind_s, auto, dispatched, started_since_complete = None, None, False, False, True
    opened, recs = None, []
    for line in open(f, errors="ignore"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        t = r.get("type"); p = r.get("payload") if isinstance(r.get("payload"), dict) else {}
        recs.append((t, p.get("type"), p.get("role")))
        if t == "session_meta" and kind_s is None:
            s = p.get("source")
            kind_s = "subagent" if isinstance(s, dict) and "subagent" in s else ("exec" if p.get("originator") == "codex_exec" else "attended")
        if kind_s != "attended":
            continue
        if t == "event_msg" and p.get("type") == "task_started":
            trig = (p.get("turn_attribution") or {}).get("turn_trigger") or "user"
            auto = trig.startswith("automation")
            started_since_complete = True
            out[("codex", "task_started trigger", trig[:24])] += 1
            if auto:
                if opened is not None: out[("codex", "wait cleared by", "automation task_started")] += 1
                opened, dispatched = None, True
        if t == "event_msg" and p.get("type") == "task_complete":
            if not dispatched: opened = len(recs)
            auto, started_since_complete = False, False
        elif t == "event_msg" and p.get("type") == "turn_aborted":
            if opened is not None: out[("codex", "wait cleared by", "turn_aborted")] += 1
            opened, auto = None, False
        elif opened is not None and t == "response_item" and (p.get("type") in ("function_call", "custom_tool_call", "reasoning") or (p.get("type") == "message" and p.get("role") == "assistant")):
            out[("codex", "wait cleared by", p.get("type"))] += 1; opened = None
        if t == "response_item" and p.get("type") == "message" and p.get("role") == "user":
            blocks = [b.get("text", "") for b in p.get("content") or [] if b.get("type") == "input_text"]
            blocks = [b for b in blocks if not (b.strip().startswith("<") and lead_tag(b.strip()) in CODEX_TAGS_V04 and b.strip().endswith("</%s>" % lead_tag(b.strip())))
                      and not b.strip().startswith("# AGENTS.md instructions")]
            typed = "\n".join(blocks).strip()
            if not typed:
                continue
            prompt_files[(r.get("timestamp"), hashlib.sha256(typed.encode()).hexdigest())].add(f)
            kind = "automation" if auto else ("dispatch" if DISPATCH.match(typed) else "human")
            out[("codex", "prompt", kind, "leading tag " + (lead_tag(typed) or "-"))] += 1
            if kind == "human" and not started_since_complete:
                out[("codex", "human prompt with no task_started since the last task_complete")] += 1
            if opened is not None and kind == "human":
                out[("codex", "turn wait closed")] += 1
            dispatched = kind != "human"
            opened = None
    if opened is not None and kind_s == "attended":
        out[("codex", "open at end")] += 1
out[("codex", "prompts (time, text hash) in more than one file")] = sum(1 for v in prompt_files.values() if len(v) > 1)
for k, v in sorted(out.items(), key=lambda kv: tuple(str(x) for x in kv[0])):
    print(v, *k)
