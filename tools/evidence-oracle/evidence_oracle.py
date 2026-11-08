#!/usr/bin/env python3 -I
"""Second implementation of Delivery Evidence, for comparison with the app.

    python3 -I evidence_oracle.py [--days N] [--home DIR] [--agreement]

Prints the same lines as `Vibra --evidence-stats`, counts only, so the two can
be compared with `diff`. It catches implementation errors, not errors in the
rules, because both sides follow docs/PLAN-2026-11-08-delivery-evidence.md.

--agreement instead compares the runner summary with the real exit status, on
checks whose exit status is visible.
"""
import collections, glob, json, os, re, shlex, sys, time
from datetime import datetime

FAIL = re.compile(
    r"Test run with \d+ tests?.*failed|with [1-9]\d* issues?|Executed \d+ tests?, with [1-9]\d* failure|\b[1-9]\d* failed\b"
    r"|test result: FAILED|^FAIL\b|error: fatal|Tests:\s+[1-9]\d* failed|\*\*\* \[|BUILD FAILED|exit[=: ]+[1-9]",
    re.M,
)
PASS = re.compile(
    r"Test run with \d+ tests?.*passed|Executed \d+ tests?, with 0 failures|\b\d+ passed\b|test result: ok|^ok\s+\S+"
    r"|Tests:\s+\d+ passed|Build complete!|BUILD SUCCEEDED|exit[=: ]+0\b|All checks passed|Success: no issues",
    re.M,
)
TAIL = 6000
DOC_EXT = {"md", "mdx", "txt", "rst", "png", "jpg", "jpeg", "gif", "svg", "pdf"}
TEMP = ("/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/")
REJECTED = "The user doesn't want to proceed"
RANK = {"test": 0, "build": 1, "lint": 2}
PM = {"npm", "pnpm", "yarn", "bun"}


def split_script(script):
    """[(segment, separator after it)], splitting outside quotes."""
    out, cur, i, quote, n, heredoc = [], [], 0, None, len(script), False

    def flush(sep):
        text = "".join(cur).strip()
        cur.clear()
        if text:
            out.append([text, sep])
        elif out and sep and out[-1][1] is None:
            out[-1][1] = sep

    while i < n:
        ch = script[i]
        if quote:
            cur.append(ch)
            if ch == "\\" and quote == '"' and i + 1 < n:
                cur.append(script[i + 1])
                i += 1
            elif ch == quote:
                quote = None
            i += 1
            continue
        if ch in "'\"":
            quote = ch
            cur.append(ch)
        elif ch == "\\" and i + 1 < n:
            cur.append(ch)
            cur.append(script[i + 1])
            i += 1
        elif script.startswith("<<", i):
            heredoc = True
            cur.append("<<")
            i += 1
        elif script.startswith("&&", i):
            flush("&&")
            i += 1
        elif script.startswith("||", i):
            flush("||")
            i += 1
        elif ch == ";":
            flush(";")
        elif ch == "|":
            flush("|")
        elif ch == "&":
            if (i > 0 and script[i - 1] == ">") or script.startswith("&>", i):
                cur.append(ch)
            else:
                flush("&")
        elif ch == "\n":
            flush("\n")
            if heredoc:
                return out
        else:
            cur.append(ch)
        i += 1
    flush(None)
    return out


def runner(segment):
    try:
        toks = shlex.split(segment, comments=True)
    except ValueError:
        toks = segment.split()
    toks = [t.rstrip(")") for t in toks]
    while toks:
        head = toks[0]
        if head.startswith("("):
            toks = ([head.lstrip("(")] if head.lstrip("(") else []) + toks[1:]
        elif re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", head) or head in ("env", "time", "command", "npx", "bunx", "do", "then"):
            toks = toks[1:]
        elif head == "timeout" and len(toks) > 1:
            toks = toks[2:]
        elif head == "pnpm" and toks[1:2] == ["exec"]:
            toks = toks[2:]
        elif head in ("uv", "poetry") and toks[1:2] == ["run"]:
            # Options before the program can take values (`--with x`), so any
            # later position may start the program.
            return next((k for k in (match_runner(toks[i:]) for i in range(2, len(toks))) if k), None)
        else:
            break
    return match_runner(toks) if toks else None


def match_runner(toks):
    name, a, b = os.path.basename(toks[0]), toks[1] if len(toks) > 1 else "", toks[2] if len(toks) > 2 else ""
    if name == "swift" and a in ("test", "build"):
        return a
    if name == "make" and a in ("test", "check"):
        return "test"
    if name == "make" and a == "build":
        return "build"
    if name == "make" and a == "lint":
        return "lint"
    if name == "xcodebuild":
        return "test" if a == "test" else "build"
    if name in ("pytest", "vitest", "jest"):
        return "test"
    if re.fullmatch(r"python3?", name) and a == "-m" and b in ("pytest", "unittest"):
        return "test"
    if name in PM:
        verb = b if a == "run" else a
        return {"test": "test", "build": "build", "lint": "lint", "typecheck": "lint"}.get(verb)
    if name == "cargo":
        return {"test": "test", "build": "build", "check": "build", "clippy": "lint"}.get(a)
    if name == "go":
        return {"test": "test", "build": "build", "vet": "lint"}.get(a)
    if name == "tsc":
        return "build"
    if name == "ruff" and a == "check":
        return "lint"
    if name in ("mypy", "eslint"):
        return "lint"
    return None


def classify(script):
    """(kind, exit status visible) or None."""
    segs = split_script(script)
    found = []
    pipefail = False
    for i, (text, sep) in enumerate(segs):
        previous_pipe = i > 0 and segs[i - 1][1] == "|"
        kind = None if previous_pipe else runner(text)
        if kind:
            visible = True
            for j in range(i, len(segs)):
                s = segs[j][1]
                has_next = j + 1 < len(segs)
                if s == "|" and not pipefail:
                    visible = False
                elif s == "||":
                    visible = False
                elif s in (";", "&", "\n") and has_next:
                    visible = False
                elif s == "&" and not has_next:
                    visible = False
            found.append((kind, visible))
        if "pipefail" in text:
            pipefail = True
    if not found:
        return None
    return min((k for k, _ in found), key=RANK.get), all(v for _, v in found)


def summary(text):
    tail = text.encode("utf-8", "replace")[-TAIL:].decode("utf-8", "replace")
    if FAIL.search(tail):
        return False
    return True if PASS.search(tail) else None


def when(stamp):
    return datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()


def body(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict))
    return ""


def counts_as_change(path):
    if path.startswith(TEMP):
        return False
    return path.rsplit(".", 1)[-1].lower() not in DOC_EXT if "." in os.path.basename(path) else True


def from_masked(text):
    v = summary(text)
    return "unknown" if v is None else ("passed.runnerSummary" if v else "failed.runnerSummary")


def fold_claude(path, truth):
    uses, results, order, saw = {}, {}, [], False
    for line in open(path, errors="replace"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        m = r.get("message")
        if not isinstance(m, dict) or not isinstance(m.get("content"), list):
            continue
        for b in m["content"]:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "tool_use":
                saw = True
                if b.get("id") not in uses:
                    uses[b.get("id")] = (b.get("name"), b.get("input") or {}, r.get("timestamp"))
                    order.append(b.get("id"))
            elif b.get("type") == "tool_result":
                results[b.get("tool_use_id")] = (b.get("is_error") is True, body(b.get("content")))
    events = []
    for i in order:
        name, inp, stamp = uses[i]
        if not stamp:
            continue
        if name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
            p = str(inp.get("file_path") or inp.get("notebook_path") or "")
            if i in results and not results[i][0] and counts_as_change(p):
                events.append((when(stamp), "change", None, None))
        elif name == "Bash":
            c = classify(str(inp.get("command", "")))
            if not c:
                continue
            kind, visible = c
            if i not in results:
                res = "unknown"
            else:
                err, text = results[i]
                if text.startswith(REJECTED):
                    res = "unknown"
                elif visible:
                    res = "failed.exitStatus" if err else "passed.exitStatus"
                    truth.append((err, summary(text), "claudeCode"))
                else:
                    res = from_masked(text)
            events.append((when(stamp), "check", kind, res))
    return events, saw


def fold_codex(path, truth):
    events, saw = [], False
    for line in open(path, errors="replace"):
        if '"item_completed"' not in line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        p = r.get("payload")
        if r.get("type") != "event_msg" or not isinstance(p, dict) or p.get("type") != "item_completed":
            continue
        it = p.get("item")
        stamp = r.get("timestamp")
        if not isinstance(it, dict) or not stamp:
            continue
        if it.get("type") == "CommandExecution":
            saw = True
            cmd = it.get("command") or []
            script = cmd[2] if len(cmd) == 3 and cmd[1] in ("-lc", "-c") else " ".join(map(str, cmd))
            c = classify(script)
            if not c:
                continue
            kind, visible = c
            code, text = it.get("exit_code"), it.get("aggregated_output") or ""
            d = it.get("duration") or {}
            start = when(stamp) - float(d.get("secs", 0)) - float(d.get("nanos", 0)) / 1e9
            if visible and code is not None:
                res = "passed.exitStatus" if code == 0 else "failed.exitStatus"
                truth.append((code != 0, summary(text), "codex"))
            else:
                res = from_masked(text)
            events.append((start, "check", kind, res))
        elif it.get("type") == "FileChange":
            saw = True
            if it.get("status") == "completed" and any(counts_as_change(str(k)) for k in (it.get("changes") or {})):
                events.append((when(stamp), "change", None, None))
    return events, saw


def verdict(events, saw):
    if not saw:
        return "noToolRecordsRecognized"
    changes = [e[0] for e in events if e[1] == "change"]
    checks = [e for e in events if e[1] == "check"]
    if not changes:
        return "noCodeChangeSeen"
    last = max(changes)
    if not [c for c in checks if c[0] <= last] and not [c for c in checks if c[0] > last]:
        return "changedWithoutCheck"
    if not [c for c in checks if c[0] > last]:
        return "changedAfterLastCheck"
    return "checkedAfterLastChange"


def claude_sessions(home, cut):
    root = f"{home}/.claude/projects"
    groups = collections.defaultdict(list)
    for f in glob.glob(f"{root}/**/*.jsonl", recursive=True):
        if "subagents" in os.path.relpath(f, root).split(os.sep)[:-1]:
            continue
        groups[os.path.basename(f)[:-6]].append(f)
    for sid, files in groups.items():
        if max(os.path.getmtime(f) for f in files) < cut:
            continue
        subs = []
        for f in files:
            subs += glob.glob(os.path.join(os.path.dirname(f), sid, "subagents", "**", "*.jsonl"), recursive=True)
        yield files + sorted(subs)


def first_meta(path):
    for line in open(path, errors="replace"):
        if '"session_meta"' in line:
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("type") == "session_meta":
                return r.get("payload") or {}
    return None


def started_at(path):
    for line in open(path, errors="replace"):
        try:
            stamp = json.loads(line).get("timestamp")
        except Exception:
            continue
        if stamp:
            return when(stamp)
    return 0.0


def codex_sessions(home, cut):
    roots, related = {}, collections.defaultdict(list)
    for f in glob.glob(f"{home}/.codex/sessions/**/rollout-*.jsonl", recursive=True):
        meta = first_meta(f)
        if not meta or not meta.get("session_id"):
            continue
        sid = meta["session_id"]
        related[sid].append(f)
        is_sub = isinstance(meta.get("source"), dict) and "subagent" in meta["source"]
        if not is_sub and os.path.getmtime(f) >= cut and (sid not in roots or os.path.getmtime(f) > os.path.getmtime(roots[sid])):
            roots[sid] = f
    for sid, f in roots.items():
        start = started_at(f)
        yield [f] + sorted(x for x in related[sid] if x != f and (x.endswith(f"{sid}.jsonl") or os.path.getmtime(x) >= start))


def run(home, days, agreement):
    cut = time.time() - days * 86400
    lines, truth = collections.Counter(), []
    plans = [("claudeCode", claude_sessions(home, cut), fold_claude), ("codex", codex_sessions(home, cut), fold_codex)]
    for agent, sessions, fold in plans:
        for files in sessions:
            events, saw = [], False
            for f in files:
                e, s = fold(f, truth)
                events += e
                saw = saw or s
            lines[f"sessions agent={agent}"] += 1
            lines[f"case agent={agent} case={verdict(events, saw)}"] += 1
            for e in events:
                if e[1] == "check":
                    lines[f"check agent={agent} kind={e[2]} result={e[3]}"] += 1
                else:
                    lines[f"change agent={agent}"] += 1
    if agreement:
        c = collections.Counter(
            f"{agent} {'exitN' if err else 'exit0'} text={'undecided' if v is None else 'passed' if v else 'failed'}"
            for err, v, agent in truth
        )
        return [f"{v:>6}  {k}" for k, v in sorted(c.items())]
    return [f"{k} n={v}" for k, v in sorted(lines.items())]


def main():
    args = sys.argv[1:]
    days = int(args[args.index("--days") + 1]) if "--days" in args else 14
    home = args[args.index("--home") + 1] if "--home" in args else os.environ.get("VIBRA_HOME") or os.path.expanduser("~")
    print("\n".join(run(home, days, "--agreement" in args)))


if __name__ == "__main__":
    main()
