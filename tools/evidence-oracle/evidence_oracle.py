#!/usr/bin/env python3 -I
"""Second implementation of Delivery Evidence, for comparison with the app.

    python3 -I evidence_oracle.py [--days N] [--home DIR] [--agreement]

Prints the same lines as `Vibra --evidence-stats`, counts only, so the two can
be compared with `diff`. It catches implementation errors, not errors in the
rules, because both sides follow docs/PLAN-2026-11-08-delivery-evidence.md.

--agreement instead compares the runner summary with the real exit status, on
checks whose exit status alone decides.
"""
import collections, glob, json, os, re, shlex, sys, time
from datetime import datetime

FAIL = re.compile(
    r"Test run with \d+ tests?.*failed|with [1-9]\d* issues?|Executed \d+ tests?, with [1-9]\d* failure|\b[1-9]\d* failed\b"
    r"|\b[1-9]\d* errors?\b|test result: FAILED|^FAIL\b|error: fatal|Tests:\s+[1-9]\d* failed|\*\*\* \[|BUILD FAILED|TEST FAILED|Segmentation fault|signal code \d+",
    re.M,
)
PASS = {
    "test": re.compile(
        r"Test run with [1-9]\d* tests?.*passed|Executed [1-9]\d* tests?, with 0 failures|\b[1-9]\d* passed\b"
        r"|test result: ok\. [1-9]\d* passed|^ok\s+\S+\s+(\d+\.\d+s|\(cached\))|Tests:\s+[1-9]\d* passed|TEST SUCCEEDED",
        re.M,
    ),
    "build": re.compile(r"Build complete!|BUILD SUCCEEDED"),
    "lint": re.compile(r"All checks passed|Success: no issues"),
}
TAIL = 6000
EDITS = ("Edit", "Write", "MultiEdit", "NotebookEdit")
DOC_EXT = {"md", "mdx", "txt", "rst", "png", "jpg", "jpeg", "gif", "svg", "pdf"}
TEMP = ("/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/")
NEVER_RAN = ("The user doesn't want to", "Permission to use", "Permission for this action",
             "Claude requested permissions", "Not started:", "[Tool call did not complete", "<tool_use_error>")
NOT_A_CHECK = {"--version", "-version", "-V", "--help", "-h", "-usage", "--show-bin-path", "--collect-only", "--co",
               "-list", "--list", "--list-tests", "--listTests", "-showBuildSettings", "-showsdks", "-showdestinations",
               "-showTestPlans", "-resolvePackageDependencies", "--no-run", "--dry-run", "-dry-run", "--just-print",
               "--fixtures", "--markers", "--setup-plan", "--setup-only", "--showConfig", "--print-config", "--init",
               "--show-files", "--show-settings", "--exit-zero", "--if-present", "--passWithNoTests"}
NOT_A_CHECK_FOR = {"make": {"-n", "-q"}, "go": {"-n", "-c"}, "tsc": {"-v"}, "eslint": {"-v"}, "swift": {"list"}, "vitest": {"list"}}
RUN_VALUE_OPTIONS = {"--with", "--with-editable", "--with-requirements", "--python", "-p", "--extra", "--group",
                     "--only-group", "--project", "--directory", "--package", "--env-file", "--index", "--default-index"}
RUN_ALONE_OPTIONS = {"--no-project", "--no-sync", "-q", "--quiet", "-v", "--verbose", "--offline", "--frozen", "--locked",
                     "--isolated", "--all-extras", "--all-groups", "--no-dev", "--dev", "--active", "--exact"}
CONTROL = {"exit", "return", "trap", "set", "setopt", "eval", "exec", "source", ".", "function", "case", "if", "then",
           "else", "elif", "fi", "for", "while", "until", "do", "done", "{", "}", "!"}
WORD_WRAPPERS = {"env", "time", "command", "npx", "bunx", "do", "then", "if", "elif", "else", "while", "until"}
RANK = {"test": 0, "build": 1, "lint": 2}
PM = {"npm", "pnpm", "yarn", "bun"}


def after_paren(script, i):
    depth, quote = 0, None
    while i < len(script):
        c = script[i]
        if quote:
            quote = None if c == quote else quote
        elif c in "'\"":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(script)


def after_backtick(script, i):
    i += 1
    while i < len(script) and script[i] != "`":
        i += 2 if script[i] == "\\" else 1
    return min(i + 1, len(script))


def heredoc_word(script, i):
    strips = script[i:i + 1] == "-"
    m = re.match(r"""-?[ \t]*((?:'[^']*'|"[^"]*"|[^\s;|&<>()])*)""", script[i:])
    return re.sub(r"""['"\\]""", "", m.group(1)), strips


def after_heredoc(script, i, delimiter):
    word, strips = delimiter
    while i < len(script):
        end = script.find("\n", i)
        end = len(script) if end < 0 else end
        line = script[i:end]
        if (line.lstrip("\t") if strips else line) == word:
            return min(end + 1, len(script))
        i = end + 1
    return len(script)


def tokenize(script):
    """[[words, separator after them]], quote-aware, with substitutions kept inside their word."""
    segs, words, word, has, quote, i, n, heredoc = [], [], "", False, None, 0, len(script), None

    def close_word():
        nonlocal word, has, words
        if has:
            words.append(word)
        word, has = "", False

    def close_seg(sep):
        nonlocal words
        close_word()
        segs.append([words, sep])
        words = []

    while i < n:
        c = script[i]
        nxt = script[i + 1] if i + 1 < n else ""
        prev = script[i - 1] if i else ""
        if quote:
            if quote == '"' and c == "$" and nxt == "(":
                end = after_paren(script, i + 1)
                word, i = word + script[i:end], end
                continue
            if c == quote:
                quote = None
            elif c == "\\" and quote == '"' and nxt:
                word += nxt
                i += 1
            else:
                word += c
            i += 1
        elif c in "'\"":
            quote, has = c, True
            i += 1
        elif c == "\\":
            if nxt == "\n":
                i += 2
            elif nxt:
                word, has = word + nxt, True
                i += 2
            else:
                i += 1
        elif c == "#" and not has:
            while i < n and script[i] != "\n":
                i += 1
        elif c in " \t":
            close_word()
            i += 1
        elif c == "\n":
            if has or words:
                close_seg("\n")
            i += 1
            if heredoc is not None:
                i, heredoc = after_heredoc(script, i, heredoc), None
        elif c == "$" and nxt == "'":
            j = i + 2
            while j < n and script[j] != "'":
                j += 2 if script[j] == "\\" else 1
            end = min(j + 1, n)
            word, has, i = word + script[i:end], True, end
        elif (c == "$" or c in "<>") and nxt == "(":
            end = after_paren(script, i + 1)
            word, has, i = word + script[i:end], True, end
        elif c == "`":
            end = after_backtick(script, i)
            word, has, i = word + script[i:end], True, end
        elif c == ";":
            close_seg(";")
            i += 1
        elif c == "|":
            if nxt == "|":
                close_seg("||")
                i += 2
            elif prev == ">":
                word, has = word + c, True
                i += 1
            else:
                close_seg("|")
                i += 2 if nxt == "&" else 1
        elif c == "&":
            if nxt == "&":
                close_seg("&&")
                i += 2
            elif nxt == ">" or prev in "<>" and prev:
                word, has = word + c, True
                i += 1
            else:
                close_seg("&")
                i += 1
        elif script.startswith("<<<", i):
            word, has = word + "<<<", True
            i += 3
        elif script.startswith("<<", i):
            heredoc = heredoc_word(script, i + 2)
            word, has = word + "<<", True
            i += 2
        else:
            word, has = word + c, True
            i += 1
    close_word()
    if words:
        segs.append([words, None])
    while segs and not segs[-1][0]:
        segs.pop()
    if segs and segs[-1][1] != "&":
        segs[-1][1] = None
    return segs


def base(word):
    name = word.rstrip("/").rsplit("/", 1)[-1]
    return "python" if re.fullmatch(r"python[0-9.]*", name) else name


def match_runner(raw):
    if not raw or ")" in raw[0]:
        return None
    toks = [t.rstrip(")") for t in raw]
    if NOT_A_CHECK & set(toks) or NOT_A_CHECK_FOR.get(base(raw[0]), set()) & set(toks):
        return None
    name, a, b = base(toks[0]), toks[1] if len(toks) > 1 else "", toks[2] if len(toks) > 2 else ""
    if name == "swift" and a in ("test", "build"):
        return a
    if name == "make":
        return {"test": "test", "check": "test", "build": "build", "lint": "lint"}.get(a)
    if name == "xcodebuild":
        return "test" if "test" in toks[1:] else "build"
    if name in ("pytest", "vitest", "jest"):
        return "test"
    if name == "python" and a == "-m" and b in ("pytest", "unittest"):
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


def runner(words):
    toks = list(words)
    while toks:
        head = toks[0]
        if head.startswith("("):
            toks = ([head.lstrip("(")] if head.lstrip("(") else []) + toks[1:]
        elif re.match(r"[A-Za-z_][A-Za-z0-9_]*=", head):
            toks = toks[1:]
        elif base(head) in WORD_WRAPPERS:
            was = head
            toks = toks[1:]
            if was in ("npx", "bunx"):
                while toks and toks[0].startswith("-"):
                    if toks[0] not in ("-y", "--yes"):
                        return None
                    toks = toks[1:]
        elif base(head) == "timeout":
            toks = toks[2:]
        elif base(head) == "pnpm" and toks[1:2] == ["exec"]:
            toks = toks[2:]
        elif base(head) in ("uv", "poetry") and toks[1:2] == ["run"]:
            j = 2
            while j < len(toks) and toks[j].startswith("-"):
                option = toks[j].split("=", 1)[0]
                if option in RUN_VALUE_OPTIONS:
                    j += 1 if "=" in toks[j] else 2
                elif option in RUN_ALONE_OPTIONS:
                    j += 1
                else:
                    return None
            return match_runner(toks[j:])
        else:
            break
    return match_runner(toks)


def proof_of(segs):
    for words, _ in segs:
        if not words or words[0] in CONTROL or any(ch in w for w in words for ch in "()`"):
            return "none"
    seps = [sep for _, sep in segs if sep]
    if not seps:
        return "full"
    return "zeroOnly" if all(sep == "&&" for sep in seps) and segs[-1][1] is None else "none"


def classify(script):
    """(kind, exit proof) or None."""
    segs = tokenize(script)
    kinds = []
    for i, (words, _) in enumerate(segs):
        if i and segs[i - 1][1] == "|":
            continue
        kind = runner(words)
        if kind:
            kinds.append(kind)
    return (min(kinds, key=RANK.get), proof_of(segs)) if kinds else None


def summary(text, kind):
    tail = text.encode("utf-8", "replace")[-TAIL:].decode("utf-8", "replace")
    ends_in_pass = False
    for line in reversed(re.split(r"\r\n|[\n\r\x0b\x0c\x85  ]", tail)):
        if FAIL.search(line):
            return None if ends_in_pass else False
        if PASS[kind].search(line):
            ends_in_pass = True
    return True if ends_in_pass else None


def result_of(proof, code, text, kind, truth, agent):
    """code: 0, a non-zero int, "errored", "unfinished" or None."""
    v = summary(text, kind)
    if code == "unfinished":
        return "unknown"
    if code in (0, None) or code == "errored":
        pass
    if isinstance(code, int) and proof == "full":
        truth.append((code != 0, v, agent))
    if code == 0 and proof != "none":
        return "passed.exitStatus"
    if isinstance(code, int) and code != 0 and proof == "full":
        return "failed.exitStatus"
    if code == "errored" or (isinstance(code, int) and code != 0):
        return "failed.runnerSummary" if v is False else "unknown"
    return "unknown" if v is None else ("passed.runnerSummary" if v else "failed.runnerSummary")


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


def claude_exit(err, text):
    if text.startswith(("Command running in background", "Command was manually backgrounded")) or "Command was moved to the background" in text:
        return "unfinished"
    if not err:
        return 0
    m = re.match(r"Exit code (-?\d+)", text)
    return int(m.group(1)) if m else "errored"


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
                if b.get("id") not in uses and r.get("timestamp"):
                    uses[b.get("id")] = (b.get("name"), b.get("input") or {}, r.get("timestamp"))
                    order.append(b.get("id"))
            elif b.get("type") == "tool_result":
                results.setdefault(b.get("tool_use_id"), (b.get("is_error") is True, body(b.get("content"))))
    events = []
    for i in order:
        name, inp, stamp = uses[i]
        err, text = results.get(i, (False, None))
        if text is not None and err and text.startswith(NEVER_RAN):
            if name == "Bash" and isinstance(inp.get("command"), str) or name in EDITS:
                saw = True
            continue
        if name in EDITS:
            p = inp.get("file_path") or inp.get("notebook_path")
            if not isinstance(p, str):
                continue
            saw = True
            if text is not None and not err and counts_as_change(p):
                events.append((when(stamp), "change", None, None))
        elif name == "Bash":
            if not isinstance(inp.get("command"), str):
                continue
            saw = True
            c = classify(inp["command"])
            if not c:
                continue
            kind, proof = c
            if inp.get("run_in_background") is True:
                proof = "none"
            res = "unknown" if text is None else result_of(proof, claude_exit(err, text), text, kind, truth, "claudeCode")
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
        if it.get("type") == "CommandExecution" and isinstance(it.get("command"), list):
            saw = True
            if it.get("status") not in ("completed", "failed"):
                continue
            cmd = it["command"]
            script = cmd[2] if len(cmd) >= 3 and cmd[1] in ("-lc", "-c") else " ".join(map(str, cmd))
            c = classify(script)
            if not c:
                continue
            kind, proof = c
            d = it.get("duration") or {}
            start = when(stamp) - float(d.get("secs", 0)) - float(d.get("nanos", 0)) / 1e9
            res = result_of(proof, it.get("exit_code"), it.get("aggregated_output") or "", kind, truth, "codex")
            events.append((start, "check", kind, res))
        elif it.get("type") == "FileChange" and isinstance(it.get("changes"), dict):
            saw = True
            if it.get("status") == "completed" and any(counts_as_change(str(k)) for k in it["changes"]):
                events.append((when(stamp), "change", None, None))
    return events, saw


def verdict(events, saw):
    """(case name, (kind, result) of the reported check or None)."""
    if not saw:
        return "noToolRecordsRecognized", None
    changes = [e[0] for e in events if e[1] == "change"]
    checks = [e for e in events if e[1] == "check"]
    if not changes:
        return "noCodeChangeSeen", None
    last = max(changes)
    after = [c for c in checks if c[0] > last]
    if not after:
        return ("changedAfterLastCheck" if checks else "changedWithoutCheck"), None
    latest = [max((c for c in after if c[2] == k), key=lambda c: c[0]) for k in RANK if any(c[2] == k for c in after)]
    pick = next((c for c in latest if c[3].startswith("failed")), latest[0])
    return "checkedAfterLastChange", (pick[2], pick[3])


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
            name, pick = verdict(events, saw)
            lines[f"case agent={agent} case={name}"] += 1
            if pick:
                lines[f"reported agent={agent} kind={pick[0]} result={pick[1]}"] += 1
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
