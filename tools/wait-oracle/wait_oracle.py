#!/usr/bin/env python3
"""Independent oracle for `Vibra --wait-stats` (docs/PLAN-2026-11-13-wait-minutes.md).

Reads the same transcripts as Vibra (VIBRA_HOME or HOME), honours TZ and
VIBRA_NOW, and prints the same lines. It shares no code with the Swift
implementation; the plan's spec is the only contract. Output carries counts
and durations only, never an id, path or text.

Run: python3 -I tools/wait-oracle/wait_oracle.py [--days N | --from YYYY-MM-DD --to YYYY-MM-DD]
"""
import datetime
import json
import os
import re
import sys
import time
import unicodedata
from fractions import Fraction

CAP_MS = 7_200_000
BUCKETS = ("1", "2-3", "4-7", "8+")

CLAUDE_WRAPPERS = {
    "command-name", "command-message", "command-args",
    "local-command-stdout", "local-command-stderr", "local-command-caveat",
    "system-reminder", "task-notification",
    "bash-input", "bash-stdout", "bash-stderr",
    "artifact-content-authored-by-others",
}
CODEX_WRAPPERS = {
    "environment_context", "turn_aborted", "user_instructions",
    "heartbeat", "task-notification", "user_shell_command",
    "command-name", "command-message", "command-args", "local-command-stdout",
}

TIMESTAMP = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]+))?(Z|[+-][0-9]{2}:[0-9]{2})")
MAX_DAYS = 36_500
FIRST_YEAR, LAST_YEAR = 1970, 9998
DISPATCH = re.compile(r"Dispatch `?[\w.-]+`?:")
SCHEDULED = re.compile(r'^\s*<scheduled-task name="([A-Za-z0-9._-]{1,64})"')
PASTES = re.compile(r"</?pasted_content[^>]*>")
COMMAND_ELEMENT = re.compile(r"<command-name>[\s\S]*?</command-name>")


# ---- time ---------------------------------------------------------------

def epoch_ms(value):
    """Integer ms from the timestamp string itself, or None."""
    if not isinstance(value, str):
        return None
    m = TIMESTAMP.fullmatch(value)
    if not m:
        return None
    year, month, day, hour, minute, second = (int(m.group(i)) for i in range(1, 7))
    try:
        datetime.date(year, month, day)
    except ValueError:
        return None
    if hour > 23 or minute > 59 or second > 59:
        return None
    offset = 0
    zone = m.group(8)
    if zone != "Z":
        oh, om = int(zone[1:3]), int(zone[4:6])
        if oh > 23 or om > 59:
            return None
        offset = (oh * 3600 + om * 60) * (-1 if zone[0] == "-" else 1)
    days = (datetime.date(year, month, day) - datetime.date(1970, 1, 1)).days
    fraction = int((m.group(7) or "")[:3].ljust(3, "0"))
    return (days * 86400 + hour * 3600 + minute * 60 + second - offset) * 1000 + fraction


def parse_window(argv, now_ms):
    """(lo, hi) or raises ValueError with the usage message."""
    def flag(name):
        if name not in argv:
            return None
        i = argv.index(name)
        return [argv[i + 1] if i + 1 < len(argv) else None]

    days, frm, to = flag("--days"), flag("--from"), flag("--to")
    if days is not None and (frm is not None or to is not None):
        raise ValueError("use --days or --from/--to, not both")
    if frm is not None or to is not None:
        if frm is None or to is None or frm[0] is None or to[0] is None:
            raise ValueError("--from and --to go together, each with a date")
        first, last = local_date(frm[0]), local_date(to[0])
        if first is None or last is None:
            raise ValueError("dates must be real YYYY-MM-DD dates from %d to %d" % (FIRST_YEAR, LAST_YEAR))
        if first > last:
            raise ValueError("--from must not be after --to")
        lo, hi = local_midnight_ms(first), local_midnight_ms(last + datetime.timedelta(days=1))
        if lo is None or hi is None:
            raise ValueError("a date (or the day after --to) does not exist in the local time zone")
        return lo, hi
    n = 30
    if days is not None:
        text = days[0]
        if text is None or not re.fullmatch(r"[0-9]+", text) or not 1 <= int(text) <= MAX_DAYS:
            raise ValueError("--days takes a whole number from 1 to %d" % MAX_DAYS)
        n = int(text)
    return now_ms - n * 86_400_000, now_ms + 1


def local_date(text):
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", text) or not FIRST_YEAR <= int(text[:4]) <= LAST_YEAR:
        return None
    try:
        return datetime.date(int(text[:4]), int(text[5:7]), int(text[8:]))
    except ValueError:
        return None


def local_midnight_ms(date):
    """The first instant of that local day, or None when the day does not exist in this time zone."""
    seconds = int(time.mktime((date.year, date.month, date.day, 0, 0, 0, 0, 0, -1)))
    back = time.localtime(seconds)
    return seconds * 1000 if (back.tm_year, back.tm_mon, back.tm_mday) == (date.year, date.month, date.day) else None


# ---- reading --------------------------------------------------------------

def jsonl_lines(path):
    """Complete, non-empty, valid UTF-8 lines only, as IncrementalLineReader returns them.
    A file that cannot be read yields nothing, as Vibra's reader does, and its path is never printed."""
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError:
        return
    for raw in data.split(b"\n")[:-1]:
        if not raw:
            continue
        try:
            yield raw.decode("utf-8")
        except UnicodeDecodeError:
            continue


def record_of(line):
    try:
        value = json.loads(line)
    except ValueError:
        return None
    return value if isinstance(value, dict) else None


def tree_jsonl(root):
    out = []
    for directory, subdirs, files in os.walk(root, followlinks=False):
        subdirs[:] = [d for d in subdirs if not os.path.islink(os.path.join(directory, d))]
        out += [os.path.join(directory, f) for f in files if f.endswith(".jsonl")]
    return out


def sources(home, lo):
    cutoff = lo / 1000 - 86400
    claude = tree_jsonl(os.path.join(home, ".claude/projects"))
    codex = [f for f in tree_jsonl(os.path.join(home, ".codex/sessions")) if os.path.basename(f).startswith("rollout-")]
    for agent, files in (("claudeCode", claude), ("codex", codex)):
        for f in sorted(files):
            try:
                if os.stat(f).st_mtime >= cutoff:
                    yield agent, f
            except OSError:
                continue


# ---- History's rule ---------------------------------------------------------

def is_swift_space(c):
    """Foundation's whitespacesAndNewlines: Unicode Z* categories, U+0009-U+000D, U+0085 and
    U+200B. Python's str.strip() also removes U+001C-U+001F, which Swift keeps."""
    return c in "\t\n\x0b\x0c\r\x85\u200b" or unicodedata.category(c) in ("Zs", "Zl", "Zp")


def trim(text):
    i, j = 0, len(text)
    while i < j and is_swift_space(text[i]):
        i += 1
    while j > i and is_swift_space(text[j - 1]):
        j -= 1
    return text[i:j]


def strip_wrappers(text, tags):
    for tag in tags:
        text = re.sub(r"<%s(\s[^>]*)?>[\s\S]*?</%s>" % (re.escape(tag), re.escape(tag)), "", text)
    return trim(text)


def is_injected_wrapper(text, tags):
    trimmed = trim(text)
    if not trimmed.startswith("<") or ">" not in trimmed:
        return False
    parts = [p for p in trimmed[1:trimmed.index(">")].split(" ") if p]
    name = parts[0] if parts else ""
    return name in tags and trimmed.endswith("</%s>" % name)


def lstrip_spaces(text):
    i = 0
    while i < len(text) and (text[i] in "\t\u200b" or unicodedata.category(text[i]) == "Zs"):
        i += 1
    return text[i:]


def normalized(text):
    t = trim(text)
    return t if t else None


class ClaudeHistory:
    def __init__(self):
        self.saw_first, self.scheduled, self.entrypoint = False, False, None

    def question(self, r):
        """The normalized question text, or None."""
        if self.entrypoint is None and isinstance(r.get("entrypoint"), str):
            self.entrypoint = r["entrypoint"]
        msg = r.get("message")
        if r.get("type") != "user" or not isinstance(msg, dict):
            return None
        content = msg.get("content")
        if not self.saw_first and isinstance(content, str):
            self.saw_first = True
            self.scheduled = SCHEDULED.search(content) is not None
        if self.scheduled or self.entrypoint == "sdk-cli":
            return None
        if r.get("isMeta") is True or r.get("isSidechain") is True:
            return None
        if isinstance(content, str):
            raw = content
        elif isinstance(content, list) and all(isinstance(b, dict) for b in content):
            if any(b.get("type") == "tool_result" for b in content):
                return None
            raw = "\n".join(b["text"] for b in content if b.get("type") == "text" and isinstance(b.get("text"), str))
        else:
            return None
        typed = trim(PASTES.sub("", strip_wrappers(raw, CLAUDE_WRAPPERS)))
        if typed.startswith("[Request interrupted by user"):
            return None
        text = normalized(typed)
        if text is None or epoch_ms(r.get("timestamp")) is None:
            return None
        return text


class CodexHistory:
    def __init__(self):
        self.originator, self.subagent, self.saw_meta = None, False, False

    def question(self, r):
        payload = r.get("payload")
        if not isinstance(payload, dict):
            return None
        kind = r.get("type")
        if kind == "session_meta":
            if self.originator is None and isinstance(payload.get("originator"), str):
                self.originator = payload["originator"]
            if not self.saw_meta:
                self.saw_meta = True
                self.subagent = isinstance(payload.get("source"), dict) and "subagent" in payload["source"]
            return None
        blocks = payload.get("content")
        if (kind != "response_item" or payload.get("type") != "message" or payload.get("role") != "user"
                or self.originator == "codex_exec" or self.subagent or not isinstance(blocks, list)
                or not all(isinstance(b, dict) for b in blocks)):
            return None
        texts = [b["text"] for b in blocks if b.get("type") == "input_text" and isinstance(b.get("text"), str)]
        kept = [t for t in texts if not is_injected_wrapper(t, CODEX_WRAPPERS)
                and not lstrip_spaces(t).startswith("# AGENTS.md instructions")]
        text = normalized("\n".join(kept))
        if text is None or epoch_ms(r.get("timestamp")) is None:
            return None
        return text


# ---- waits ------------------------------------------------------------------

class Fold:
    def __init__(self):
        self.waits = []          # (kind, start, end, answer)
        self.events = []
        self.has_prompt = False
        self.open_since = None


def dict_list(value):
    """A JSON array whose every element is an object, else None."""
    return value if isinstance(value, list) and all(isinstance(b, dict) for b in value) else None


def text_of(content):
    if isinstance(content, str):
        return content
    blocks = dict_list(content)
    if blocks is not None:
        return "\n".join(b["text"] for b in blocks if b.get("type") == "text" and isinstance(b.get("text"), str))
    return None


def is_single_element(text, tag):
    t = trim(text)
    return (is_injected_wrapper(t, {tag}) and t.count("</%s>" % tag) == 1
            and t.count("<%s>" % tag) + t.count("<%s " % tag) == 1)


def claude_fold(lines):
    f, history = Fold(), ClaudeHistory()
    open_ms, open_resp, dispatched = None, None, False
    uses, seen = {}, set()
    for line in lines:
        r = record_of(line)
        if r is None:
            continue
        question = history.question(r)
        t = epoch_ms(r.get("timestamp"))
        if t is None or r.get("isSidechain") is True or r.get("isMeta") is True:
            continue
        kind = r.get("type")
        msg = r.get("message") if isinstance(r.get("message"), dict) else {}
        if kind == "assistant":
            rid = msg.get("id") if isinstance(msg.get("id"), str) else None
            end_turn = msg.get("stop_reason") == "end_turn"
            if rid is not None and rid == open_resp:
                if end_turn:
                    open_ms = t
            elif end_turn and not dispatched:
                open_ms, open_resp = t, rid
            else:
                open_ms, open_resp = None, None
            for b in dict_list(msg.get("content")) or []:
                if b.get("type") == "tool_use" and isinstance(b.get("id"), str):
                    if b["id"] not in seen:
                        seen.add(b["id"])
                        uses[b["id"]] = (t, b.get("name"))
            continue
        if kind != "user":
            continue
        content = msg.get("content")
        blocks = dict_list(content)
        if blocks is not None and any(b.get("type") == "tool_result" for b in blocks):
            decision = r.get("permissionDecision") if isinstance(r.get("permissionDecision"), dict) else {}
            verdict = decision.get("decision")
            answer = verdict if verdict in ("accept", "reject") and isinstance(verdict, str) else "unknown"
            source = decision.get("source")
            for b in blocks:
                tid = b.get("tool_use_id")
                if b.get("type") != "tool_result" or not isinstance(tid, str) or tid not in uses:
                    continue
                start, name = uses.pop(b["tool_use_id"])
                if name == "AskUserQuestion":
                    f.waits.append(("question", start, t, answer))
                elif isinstance(source, str) and source.startswith("user"):
                    f.waits.append(("approval", start, t, answer))
            continue
        if question is not None:
            if DISPATCH.match(question):
                open_ms, open_resp, dispatched = None, None, True
                continue
            f.has_prompt = True
        else:
            text = text_of(content)
            if text is None:
                continue
            s = trim(text)
            command = ((s.startswith("<command-name>") or s.startswith("<command-message>"))
                       and COMMAND_ELEMENT.search(s) is not None) or s.startswith("<bash-input>")
            if not command:
                continue
        f.events.append(t)
        if open_ms is not None:
            f.waits.append(("turn", open_ms, t, None))
        open_ms, open_resp, dispatched = None, None, False
    f.open_since = open_ms
    return f


def codex_turn_is_automation(payload):
    attribution = payload.get("turn_attribution") if isinstance(payload.get("turn_attribution"), dict) else {}
    trigger = attribution.get("turn_trigger") if isinstance(attribution.get("turn_trigger"), str) else "user"
    return trigger.startswith("automation")


def codex_fold(lines):
    f, history = Fold(), CodexHistory()
    open_ms, dispatched, automation = None, False, False
    for line in lines:
        r = record_of(line)
        if r is None:
            continue
        question = history.question(r)
        t = epoch_ms(r.get("timestamp"))
        payload = r.get("payload") if isinstance(r.get("payload"), dict) else {}
        if t is None:
            continue
        kind, ptype = r.get("type"), payload.get("type")
        if kind == "event_msg" and ptype == "task_started":
            automation = codex_turn_is_automation(payload)
            if automation:
                open_ms, dispatched = None, True
            continue
        if kind == "event_msg" and ptype == "task_complete":
            if not dispatched:
                open_ms = t
            automation = False
            continue
        if kind == "event_msg" and ptype == "turn_aborted":
            open_ms, automation = None, False
            continue
        if kind == "response_item" and (ptype in ("function_call", "custom_tool_call", "reasoning")
                                        or (ptype == "message" and payload.get("role") == "assistant")):
            open_ms = None
            continue
        if question is not None:
            if automation or DISPATCH.match(question):
                open_ms, dispatched = None, True
                continue
            f.has_prompt = True
        elif (kind == "response_item" and ptype == "message" and payload.get("role") == "user" and not automation
              and dict_list(payload.get("content")) is not None
              and any(b.get("type") == "input_text" and isinstance(b.get("text"), str)
                      and is_single_element(b["text"], "user_shell_command") for b in payload["content"])):
            pass
        else:
            continue
        f.events.append(t)
        if open_ms is not None:
            f.waits.append(("turn", open_ms, t, None))
        open_ms, dispatched = None, False
    f.open_since = open_ms
    return f


# ---- stats --------------------------------------------------------------------

def bucket(ordinal):
    return "1" if ordinal == 1 else "2-3" if ordinal <= 3 else "4-7" if ordinal <= 7 else "8+"


def capped(w):
    return min(max(w[2] - w[1], 0), CAP_MS)


def union_ms(intervals):
    total, cur_lo, cur_hi = 0, None, None
    for lo, hi in sorted(intervals):
        if hi <= lo:
            continue
        if cur_hi is None or lo > cur_hi:
            if cur_hi is not None:
                total += cur_hi - cur_lo
            cur_lo, cur_hi = lo, hi
        else:
            cur_hi = max(cur_hi, hi)
    if cur_hi is not None:
        total += cur_hi - cur_lo
    return total


def quantiles(values):
    xs = sorted(values)
    out = []
    for k in (1, 2, 3):
        h = Fraction((len(xs) - 1) * k, 4)
        f = int(h)
        q = Fraction(xs[f]) + ((h - f) * (xs[f + 1] - xs[f]) if f + 1 < len(xs) else 0)
        out.append(q)
    return out


def floor_div(q, unit):
    return int(q // unit)


def stats(folds, lo, hi):
    groups = [dict() for _ in range(7)]
    per_agent = {}
    for agent, f in folds:
        if not f.has_prompt:
            continue
        ordinal = {}
        dialog = sorted((i for i, w in enumerate(f.waits) if w[0] != "turn"), key=lambda i: (f.waits[i][1], f.waits[i][2]))
        for n, i in enumerate(dialog, 1):
            ordinal[i] = n
        inside = [(i, w) for i, w in enumerate(f.waits) if lo <= w[2] < hi]
        if not inside and not any(lo <= e < hi for e in f.events):
            continue
        a = per_agent.setdefault(agent, {"sessions": 0, "open": 0, "waits": {}, "over": {}, "secs": {}, "ord": {},
                                         "blocked": [], "within": []})
        a["sessions"] += 1
        a["open"] += f.open_since is not None
        for i, w in inside:
            key = "kind=turn" if w[0] == "turn" else "kind=%s answer=%s" % (w[0], w[3])
            a["waits"][key] = a["waits"].get(key, 0) + 1
            if w[2] - w[1] > CAP_MS:
                a["over"][w[0]] = a["over"].get(w[0], 0) + 1
            a["secs"].setdefault(w[0], []).append(capped(w))
            if w[0] != "turn":
                a["ord"].setdefault((w[0], bucket(ordinal[i])), []).append(capped(w))
        a["blocked"].append(union_ms([(w[1], w[1] + capped(w)) for _, w in inside]))
        a["within"].append(union_ms([(w[1], w[1] + capped(w)) for _, w in inside if w[2] - w[1] <= CAP_MS]))

    def q3(values, unit):
        return " ".join("p%d=%d" % (p, floor_div(q, unit)) for p, q in zip((25, 50, 75), quantiles(values)))

    for agent, a in per_agent.items():
        groups[0]["sessions agent=%s" % agent] = "n=%d" % a["sessions"]
        if a["open"]:
            groups[1]["open agent=%s" % agent] = "n=%d" % a["open"]
        for key, n in a["waits"].items():
            groups[2]["waits agent=%s %s" % (agent, key)] = "n=%d" % n
        for kind, n in a["over"].items():
            groups[3]["over_cap agent=%s kind=%s" % (agent, kind)] = "n=%d" % n
        for kind, values in a["secs"].items():
            groups[4]["seconds agent=%s kind=%s" % (agent, kind)] = "%s n=%d" % (q3(values, 1000), len(values))
        for (kind, b), values in a["ord"].items():
            groups[5]["seconds agent=%s kind=%s ordinal=%s" % (agent, kind, b)] = "%s n=%d" % (q3(values, 1000), len(values))
        for scope, values in (("all", a["blocked"]), ("within_cap", a["within"])):
            groups[6]["blocked agent=%s scope=%s unit=min" % (agent, scope)] = "%s total=%d n=%d" % (
                q3(values, 60000), sum(values) // 60000, len(values))
    lines = []
    for g in groups:
        for key in sorted(g, key=lambda k: k.encode()):
            lines.append("%s %s\n" % (key, g[key]))
    return "".join(lines)


def run(argv, env):
    home = env.get("VIBRA_HOME") or os.path.expanduser("~")
    now_ms = int(time.time() * 1000)
    pinned = env.get("VIBRA_NOW")
    if pinned:
        now_ms = epoch_ms(pinned)
        if now_ms is None:
            return 2, "", "VIBRA_NOW must be an ISO 8601 date-time, got %s\n" % pinned
    try:
        lo, hi = parse_window(argv, now_ms)
    except ValueError as e:
        return 2, "", "usage: wait_oracle.py [--days N | --from YYYY-MM-DD --to YYYY-MM-DD]: %s\n" % e
    folds = []
    for agent, path in sources(home, lo):
        lines = list(jsonl_lines(path))
        folds.append((agent, claude_fold(lines) if agent == "claudeCode" else codex_fold(lines)))
    return 0, stats(folds, lo, hi), ""


def main():
    code, out, err = run(sys.argv[1:], os.environ)
    sys.stdout.write(out)
    sys.stderr.write(err)
    return code


if __name__ == "__main__":
    sys.exit(main())
