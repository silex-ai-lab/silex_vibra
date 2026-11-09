#!/usr/bin/env python3
"""Second implementation of the incident rules, for comparing counts.

Written from docs/PLAN-2026-11-09-agent-incidents.md, not from the Swift. It
reads real transcripts and prints counts only: never a command, a path or a key.

usage: incident_oracle.py [--days N] [--compare swift.json] [--write-breakdown]
"""
import argparse
import collections
import glob
import json
import os
import re
import sys
import time

HOME = os.environ.get("VIBRA_HOME") or os.path.expanduser("~")
DENIED = ("The user doesn't want to", "Permission for this action")
NEVER_STARTED = DENIED + (
    "Permission to use", "Claude requested permissions", "Not started:",
    "[Tool call did not complete", "<tool_use_error>",
)
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
SCRATCH = ("/tmp/", "/var/folders/")
STATE_ROOTS = (os.path.join(HOME, ".claude/projects"),)
CRED_DIRS = {".ssh": "sshKey", ".aws": "awsCredentials"}
CRED_PATHS = {
    ".netrc": "netrc", ".git-credentials": "netrc", ".npmrc": "packageToken", ".pypirc": "packageToken",
    ".config/pip/pip.conf": "packageToken", ".config/gh/hosts.yml": "gitHubCLI", ".config/gh/hosts.yaml": "gitHubCLI",
    ".claude/.credentials.json": "agentCredential", ".codex/auth.json": "agentCredential",
}
EXCLUDED_NAMES = {".env.example", ".env.sample", ".env.template", "known_hosts", "authorized_keys"}
EXCLUDED_PATHS = {os.path.join(HOME, ".ssh/config"), os.path.join(HOME, ".aws/config")}
READERS = {
    "cat": ("nbestuvAET", set(), set(), "all"),
    "less": ("RNSd", set(), set(), "all"),
    "more": ("RNSd", set(), set(), "all"),
    "source": ("", set(), set(), "first"),
    ".": ("", set(), set(), "first"),
    "base64": ("dD", {"-i", "--input"}, {"-o", "--output", "-b", "--break"}, "all"),
    "head": ("qvfF", set(), {"-n", "-c"}, "all"),
    "tail": ("qvfF", set(), {"-n", "-c"}, "all"),
    "cp": ("afinprRvLPH", set(), {"-S", "-t"}, "butlast"),
    "scp": ("rpqC346BOTvA", set(), {"-P", "-l", "-o", "-c", "-J", "-F", "-i"}, "butlast"),
    "grep": ("rRnilLHhsvwcqEFIo", {"-f", "--file"}, {"-e", "-A", "-B", "-C", "-m", "-g", "--include", "--exclude"}, "afterfirst"),
    "rg": ("rRnilLHhsvwcqEFIo", {"-f", "--file"}, {"-e", "-A", "-B", "-C", "-m", "-g", "--include", "--exclude"}, "afterfirst"),
}
WRAPPER_OPTIONS = {
    "sudo": ({"-u", "-g", "-p", "-C", "-U", "-r", "-t"}, {"-E", "-H", "-n", "-S", "-k", "-A", "-b", "-i", "-s"}),
    "env": ({"-u"}, {"-i", "-0", "-v"}),
    "time": (set(), {"-p"}),
}


def normalize(raw, cwd):
    if not raw:
        return None
    value = raw
    for prefix in ("~", "$HOME", "${HOME}"):
        if value == prefix:
            value = HOME
        elif value.startswith(prefix + "/"):
            value = HOME + value[len(prefix):]
    if not value.startswith("/"):
        if not cwd or not cwd.startswith("/"):
            return None
        value = cwd + "/" + value
    path = os.path.normpath(value)
    for prefix in ("/private/var", "/private/tmp"):
        if path == prefix or path.startswith(prefix + "/"):
            path = path[len("/private"):]
    return path


def within(path, root):
    return path == root or path.startswith(root + "/")


def credential_class(path):
    name = os.path.basename(path)
    if name in EXCLUDED_NAMES or name.endswith(".pub") or path in EXCLUDED_PATHS:
        return None
    if name == ".env" or name.startswith(".env."):
        return "dotEnv"
    for folder, cls in CRED_DIRS.items():
        if within(path, os.path.join(HOME, folder)):
            return cls
    for rel, cls in CRED_PATHS.items():
        if path == os.path.join(HOME, rel):
            return cls
    return None


def split_script(script):
    """Words of each simple command, and whether it is one foreground command."""
    commands, words, word, i, separators = [], [], None, 0, []
    heredocs = []

    def end_word():
        nonlocal word
        if word is not None:
            words.append(word)
            word = None

    def end_command(sep):
        nonlocal words
        end_word()
        if words:
            commands.append(words)
            separators.append(sep)
        words = []

    n = len(script)
    while i < n:
        c = script[i]
        if c == "\\" and i + 1 < n:
            if script[i + 1] != "\n":
                word = (word or "") + script[i + 1]
            i += 2
        elif c == "'":
            j = script.find("'", i + 1)
            j = n if j < 0 else j
            word = (word or "") + script[i + 1:j]
            i = j + 1
        elif c == '"':
            i += 1
            word = word or ""
            while i < n and script[i] != '"':
                if script[i] == "\\" and i + 1 < n:
                    i += 1
                word += script[i]
                i += 1
            i += 1
        elif c == "#" and word is None:
            while i < n and script[i] != "\n":
                i += 1
        elif c == "\n":
            end_command("nl")
            i += 1
            for delimiter in heredocs:
                while i < n:
                    j = script.find("\n", i)
                    j = n if j < 0 else j
                    line = script[i:j]
                    i = j + 1
                    if line.strip() == delimiter:
                        break
            heredocs = []
        elif c == "<" and script[i:i + 2] == "<<" and script[i:i + 3] != "<<<":
            end_word()
            i += 2
            if i < n and script[i] == "-":
                i += 1
            while i < n and script[i] in " \t":
                i += 1
            m = re.match(r"""['"]?([A-Za-z0-9_.-]+)['"]?""", script[i:])
            if m:
                heredocs.append(m.group(1))
                i += m.end()
        elif c in " \t":
            end_word()
            i += 1
        elif script[i:i + 2] in ("&&", "||"):
            end_command(script[i:i + 2])
            i += 2
        elif c == ";" or c == "|":
            end_command(c)
            i += 1
        elif c == "&" and script[i + 1:i + 2] != ">" and (not word or not word[-1:] in (">", "<")):
            end_command("&")
            i += 1
        else:
            word = (word or "") + c
            i += 1
    end_command("end")
    sole = len(commands) == 1 and separators[0] != "&"
    return [unwrap(c) for c in commands], sole


def unwrap(words):
    i = 0
    while i < len(words):
        name = os.path.basename(words[i])
        if name in WRAPPER_OPTIONS:
            values, flags = WRAPPER_OPTIONS[name]
            i += 1
            while i < len(words) and words[i].startswith("-") and words[i] != "-":
                option = words[i].split("=", 1)[0]
                if option in values:
                    i += 1 if "=" in words[i] else 2
                elif option in flags:
                    i += 1
                else:
                    break
        elif name in ("command", "nohup"):
            i += 1
        elif re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[i]):
            i += 1
        else:
            return words[i:]
    return []


def strip_redirects(words):
    kept, i = [], 0
    while i < len(words):
        m = re.match(r"^[0-9&]*(>>|>|<)(.*)$", words[i])
        if not m:
            kept.append(words[i])
            i += 1
        else:
            i += 2 if m.group(2) == "" else 1
    return kept


def operands(args, spec):
    flags, inputs, skips, mode = spec
    values, has_pattern, has_t, i = [], False, False, 0
    while i < len(args):
        word = args[i]
        if word == "--":
            values += [(w, True) for w in args[i + 1:]]
            break
        if word.startswith("--") and len(word) > 2:
            name, eq, inline = word.partition("=")
            if name in inputs:
                if eq:
                    values.append((inline, False))
                elif i + 1 < len(args):
                    values.append((args[i + 1], False))
                    i += 1
                else:
                    return None
                has_pattern = has_pattern or name == "--file"
                i += 1
            elif name in skips:
                i += 1 if eq else 2
            else:
                return None
        elif word.startswith("-") and word != "-":
            option = word[:2]
            if word[1:].isdigit() and mode == "all" and "-n" in skips:
                i += 1
            elif len(word) >= 2 and all(ch in flags for ch in word[1:]):
                i += 1
            elif option in inputs:
                if len(word) > 2:
                    values.append((word[2:], False))
                    i += 1
                elif i + 1 < len(args):
                    values.append((args[i + 1], False))
                    i += 2
                else:
                    return None
                has_pattern = has_pattern or option == "-f"
            elif option in skips:
                has_pattern = has_pattern or option == "-e"
                has_t = has_t or option == "-t"
                i += 1 if len(word) > 2 else 2
            else:
                return None
        else:
            values.append((word, True))
            i += 1
    positional = [index for index, value in enumerate(values) if value[1]]
    if mode == "first":
        counted = set(positional[:1])
    elif mode == "butlast":
        counted = set(positional) if has_t else set(positional[:-1])
    elif mode == "afterfirst":
        counted = set(positional) if has_pattern else set(positional[1:])
    else:
        counted = set(positional)
    return [value[0] for index, value in enumerate(values) if not value[1] or index in counted]


def first_credential(commands, cwd):
    for words in commands:
        if not words:
            continue
        name = os.path.basename(words[0])
        if name == "security":
            if words[1:2] and words[1] in ("find-generic-password", "find-internet-password"):
                return "keychain", None
            continue
        if name not in READERS:
            continue
        candidates = operands(strip_redirects(words[1:]), READERS[name])
        for raw in candidates or []:
            path = normalize(raw, cwd)
            cls = credential_class(path) if path else None
            if cls:
                return cls, path
    return None


def force_push(words):
    if not words or os.path.basename(words[0]) != "git":
        return False
    i = 1
    while i < len(words) and words[i] in ("-C", "-c"):
        i += 2
    if i >= len(words) or words[i] != "push":
        return False
    force = False
    for word in words[i + 1:]:
        if word == "--dry-run":
            return False
        if word == "--force" or (word.startswith("+") and len(word) > 1):
            force = True
        if word.startswith("-") and not word.startswith("--") and len(word) > 1:
            if "n" in word:
                return False
            if "f" in word:
                force = True
    return force


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and "text" in b)
    return ""


def is_human(record):
    if record.get("type") != "user" or record.get("isMeta") or record.get("isSidechain"):
        return False
    content = (record.get("message") or {}).get("content")
    if isinstance(content, str):
        return True
    return isinstance(content, list) and any(isinstance(b, dict) and b.get("type") == "text" for b in content)


def write_category(path, cwd):
    if path.startswith(HOME + "/"):
        rel = path[len(HOME) + 1:].split("/")
        if rel[0] in (".claude", ".codex", ".config", ".local"):
            return "/".join(rel[:2]) if len(rel) > 1 else rel[0]
        if cwd and os.path.dirname(cwd) and within(path, os.path.dirname(cwd)):
            return "sibling of cwd"
        return "other under home"
    return "outside home"


class Results:
    def __init__(self):
        self.ids = set()
        self.write_categories = collections.Counter()

    def add(self, agent, session, kind, anchor):
        if session:
            self.ids.add((agent, session, kind, anchor))

    def counts(self):
        out = collections.Counter()
        for agent, _session, kind, _anchor in self.ids:
            out[(agent, kind)] += 1
        return out


def claude_file(path, results):
    session, cwd, pending, seen, denied = None, None, {}, set(), []
    with open(path, errors="replace") as handle:
        for line in handle:
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if not isinstance(record, dict):
                continue
            session = session or record.get("sessionId") or record.get("session_id")
            cwd = record.get("cwd") or cwd
            mode = record.get("permissionMode") or (record.get("mode") if record.get("type") == "permission-mode" else None)
            if mode == "bypassPermissions":
                results.add("claudeCode", session, "unrestrictedSession", "session")
            if record.get("isApiErrorMessage") and record.get("error") == "authentication_failed" and record.get("uuid"):
                results.add("claudeCode", session, "authFailure", record["uuid"])
            if denied and is_human(record):
                denied = []
            content = (record.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use" and record.get("timestamp"):
                    call_id, name, args = block.get("id"), block.get("name"), block.get("input")
                    if not call_id or call_id in seen or not name or not isinstance(args, dict):
                        continue
                    seen.add(call_id)
                    key = (name, json.dumps(args, sort_keys=True))
                    pending[call_id] = dict(name=name, args=args, key=key, retried=key in denied, cwd=cwd)
                elif block.get("type") == "tool_result":
                    call = pending.pop(block.get("tool_use_id"), None)
                    if call is None:
                        continue
                    text, is_error = text_of(block.get("content")), bool(block.get("is_error"))
                    if is_error and text.startswith(NEVER_STARTED):
                        if text.startswith(DENIED) and call["key"] not in denied:
                            denied.append(call["key"])
                        continue
                    claude_call(call, block["tool_use_id"], is_error, session, denied, results)


def claude_call(call, call_id, is_error, session, denied, results):
    name, args, cwd = call["name"], call["args"], call["cwd"]
    if call["retried"] and not is_error and call["key"] in denied:
        denied.remove(call["key"])
        results.add("claudeCode", session, "deniedCallRanLater", call_id)
    credential = None
    if name == "Bash" and isinstance(args.get("command"), str) and cwd:
        commands, _ = split_script(args["command"])
        credential = first_credential(commands, cwd)
        if any(force_push(c) for c in commands):
            results.add("claudeCode", session, "forcePushAttempt", call_id)
    elif name == "Read" and cwd:
        path = normalize(args.get("file_path"), cwd)
        cls = credential_class(path) if path else None
        credential = (cls, path) if cls else None
    if credential:
        record_credential(results, "claudeCode", session, call_id, credential, [normalize(cwd, None)])
    if name in EDIT_TOOLS and not is_error and cwd:
        path = normalize(args.get("file_path") or args.get("notebook_path"), cwd)
        if path and outside(path, [normalize(cwd, None)]):
            results.add("claudeCode", session, "writeToPathOutsideWorkspace", call_id)
            results.write_categories[("claudeCode", write_category(path, cwd))] += 1


def outside(path, roots):
    roots = [r for r in roots if r]
    if not roots or any(within(path, r) for r in roots):
        return False
    if path.startswith(SCRATCH) or any(within(path, r) for r in STATE_ROOTS):
        return False
    return True


def record_credential(results, agent, session, call_id, credential, roots):
    cls, path = credential
    if cls == "dotEnv" and any(r and within(path, r) for r in roots):
        results.add(agent, session, "workspaceSecretFileNamed", "session-dotenv")
    else:
        results.add(agent, session, "credentialReadAttempt", call_id)


def codex_file(path, results):
    session, cwd, roots = None, None, []
    with open(path, errors="replace") as handle:
        for line in handle:
            if '"session_meta"' not in line and '"turn_context"' not in line and '"item_completed"' not in line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            payload = record.get("payload")
            if not isinstance(payload, dict):
                continue
            kind = record.get("type")
            if kind == "session_meta":
                session = session or payload.get("session_id") or payload.get("id")
                cwd = cwd or payload.get("cwd")
            elif kind == "turn_context":
                cwd = payload.get("cwd") or cwd
                roots = payload.get("workspace_roots") or roots
                policy = payload.get("sandbox_policy")
                if isinstance(policy, dict) and policy.get("type") == "danger-full-access" and record.get("timestamp"):
                    results.add("codex", session, "unrestrictedSession", "session")
            elif kind == "event_msg" and payload.get("type") == "item_completed" and record.get("timestamp"):
                codex_item(payload.get("item") or {}, session, cwd, roots, results)


def codex_item(item, session, cwd, roots, results):
    item_id = item.get("id")
    if not item_id:
        return
    workspace = [normalize(cwd, None)] + [normalize(r, cwd) for r in roots]
    if item.get("type") == "CommandExecution" and item.get("status") in ("completed", "failed"):
        argv = item.get("command")
        if not isinstance(argv, list) or not argv:
            return
        script = argv[2] if len(argv) >= 3 and argv[1] in ("-lc", "-c") else " ".join(argv)
        commands, _ = split_script(script)
        credential = first_credential(commands, cwd)
        if credential:
            record_credential(results, "codex", session, item_id, credential, workspace)
        if any(force_push(c) for c in commands):
            results.add("codex", session, "forcePushAttempt", item_id)
    elif item.get("type") == "FileChange" and item.get("status") == "completed":
        for key in (item.get("changes") or {}):
            path = normalize(key, cwd)
            if path and outside(path, workspace):
                results.add("codex", session, "writeToPathOutsideWorkspace", item_id)
                results.write_categories[("codex", write_category(path, cwd))] += 1
                return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--compare")
    parser.add_argument("--write-breakdown", action="store_true")
    options = parser.parse_args()
    cutoff = time.time() - options.days * 86400
    results = Results()
    for pattern, reader in (
        (os.path.join(HOME, ".claude/projects/**/*.jsonl"), claude_file),
        (os.path.join(HOME, ".codex/sessions/**/*.jsonl"), codex_file),
    ):
        for path in glob.glob(pattern, recursive=True):
            try:
                if os.path.getmtime(path) >= cutoff:
                    reader(path, results)
            except OSError:
                continue
    counts = results.counts()
    for (agent, kind), count in sorted(counts.items()):
        print(f"oracle {agent} {kind} {count}")
    if options.write_breakdown:
        sessions = {(a, s) for a, s, k, _ in results.ids if k == "writeToPathOutsideWorkspace"}
        print(f"write sessions {len(sessions)}")
        for (agent, category), count in results.write_categories.most_common():
            print(f"write {agent} {category} {count}")
    if options.compare:
        with open(options.compare) as handle:
            rows = json.load(handle)
        swift = collections.Counter((r.get("agent"), r["kind"]) for r in rows if r.get("agent"))
        mismatched = 0
        for key in sorted(set(counts) | set(swift)):
            if counts[key] != swift[key]:
                mismatched += 1
                print(f"DIFF {key[0]} {key[1]} oracle={counts[key]} swift={swift[key]}")
        print(f"compared {len(set(counts) | set(swift))} rows, {mismatched} differ")
        sys.exit(1 if mismatched else 0)


if __name__ == "__main__":
    main()
