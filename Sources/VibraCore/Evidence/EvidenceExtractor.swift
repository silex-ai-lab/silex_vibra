import Foundation

public struct EvidenceFold: Sendable, Equatable {
    public var events: [EvidenceEvent]
    public var sawToolRecords: Bool

    public init(events: [EvidenceEvent] = [], sawToolRecords: Bool = false) {
        self.events = events
        self.sawToolRecords = sawToolRecords
    }
}

/// Reduces one transcript to change and check events, fed every batch of that
/// transcript in order.
///
/// Command text, file paths and tool output are read, mapped to enums and a
/// date, and dropped inside `fold`. Nothing an extractor keeps or returns may
/// carry any of them.
public protocol EvidenceExtractor {
    mutating func fold(_ lines: [String])
    /// Settles calls that never got a result.
    mutating func finish() -> EvidenceFold
}

private let documentationExtensions: Set<String> = [
    "md", "mdx", "txt", "rst", "png", "jpg", "jpeg", "gif", "svg", "pdf",
]
private let scratchPrefixes = ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"]

/// `String.contains` is the hot cost on a 100 MB transcript, so this searches
/// the UTF-8 bytes directly.
func lineContains(_ line: String, _ needle: String) -> Bool {
    var needle = needle
    return needle.withUTF8 { n in
        var line = line
        return line.withUTF8 { memmem($0.baseAddress, $0.count, n.baseAddress, n.count) != nil }
    }
}

func isCodePath(_ path: String) -> Bool {
    if scratchPrefixes.contains(where: path.hasPrefix) { return false }
    return !documentationExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
}

// MARK: - Test paths

private let testDirectories: Set<String> = [
    "test", "tests", "__tests__", "spec", "specs", "Tests", "testing",
]
private let neverTestDirectories: Set<String> = [
    "fixtures", "Fixtures", "testdata", "test_data", "__snapshots__",
]

/// A changed path is a test path when a directory component below the workspace
/// root names one, or its file name fits a test naming convention. Components
/// at or above the root never count, or a checkout under `~/code/testing`
/// would turn every file into a test.
///
/// The root is the `cwd` in effect at the edit, so a mid-session `cd` moves it
/// with the agent. A path outside the root, or any path when no root is known,
/// is decided by its file name alone.
func isTestPath(_ rawPath: String, root rawRoot: String?) -> Bool {
    let root = rawRoot.flatMap { IncidentPaths.absolute($0, cwd: nil) }
    let path = IncidentPaths.absolute(rawPath, cwd: rawRoot) ?? rawPath
    if let root, let below = components(below: root, of: path) {
        let directories = below.dropLast()
        if directories.contains(where: neverTestDirectories.contains) { return false }
        if directories.contains(where: testDirectories.contains) { return true }
    }
    let name = (path as NSString).lastPathComponent
    let range = NSRange(name.startIndex..., in: name)
    return testFileName.firstMatch(in: name, range: range) != nil
}

private func components(below root: String, of path: String) -> [String]? {
    if root == "/" { return path.split(separator: "/").map(String.init) }
    guard path.hasPrefix(root + "/") else { return nil }
    return path.dropFirst(root.count + 1).split(separator: "/").map(String.init)
}

// MARK: - Pattern counts

/// Counted per edit, in the extractor, and dropped: no text survives the fold.
///
/// The patterns are normative and pinned against an independent oracle, so
/// they are copied character for character and never "tidied".
func patternCounts(in text: String) -> PatternCounts {
    let counted = uncommented(text)
    let range = NSRange(counted.startIndex..., in: counted)
    func count(_ pattern: NSRegularExpression) -> Int { pattern.numberOfMatches(in: counted, range: range) }
    return PatternCounts(
        assertion: count(assertionPattern),
        skip: count(skipPattern),
        focus: count(focusPattern),
        expectedFailure: count(expectedFailurePattern),
        testFunction: count(testFunctionPattern))
}

/// Drops every line that is entirely a comment: an assertion commented out with
/// `//` counts as removed, while `#expect`, `#require`, `#[test]` and
/// `#[ignore]` survive because `#` is followed by a non-space.
///
/// The strip is the plan's pattern verbatim, so it agrees with the oracle on
/// exotic whitespace too.
private let commentLine = regex(#"^\s*(?://|/\*|\*|#(?:\s|$))"#)

/// Splits on the `\n` scalar, not on the `"\n"` Character: in Swift `"\r\n"` is
/// one Character, so `split(separator: "\n")` would leave a CRLF edit as a
/// single line and a leading comment would delete the whole edit. The oracle
/// splits on the scalar too, and a trailing `\r` stays on the line.
private func uncommented(_ text: String) -> String {
    text.components(separatedBy: "\n")
        .filter { line in
            let range = NSRange(line.startIndex..., in: line)
            return commentLine.firstMatch(in: line, range: range) == nil
        }
        .joined(separator: "\n")
}

private let assertionPattern = regex(
    #"\bassert\w*\b|\bXCTAssert\w*|#expect\b|#require\b|\bexpect\(|\.should\b|\bt\.(?:Error|Fatal)f?\(|\brequire\.[A-Z]\w*\("#)
private let skipPattern = regex(
    #"pytest\.mark\.skip\w*|\b(?:it|test|describe|context|suite|pytest|this)\.skip\(|\.skipTest\(|(?<![.\w])xit\(|(?<![.\w])xdescribe\(|\bXCTSkip\w*|@Disabled\b|\.disabled\(|\bt\.Skip\w*\(|#\[ignore\]|@unittest\.skip\w*"#)
private let focusPattern = regex(
    #"\b(?:it|test|describe|context|suite)\.only\(|(?<![.\w])fit\(|(?<![.\w])fdescribe\("#)
private let expectedFailurePattern = regex(
    #"pytest\.mark\.xfail\b|\bwithKnownIssue\b|\bXCTExpectFailure\b|@unittest\.expectedFailure\b|\b(?:it|test)\.failing\("#)
private let testFunctionPattern = regex(
    #"\bdef test_\w*|\bfunc test\w*|@Test\b|(?<![.\w])it\(|(?<![.\w])test\(|#\[test\]|\bfunc Test\w+\("#)
private let testFileName = regex(
    #"^(?:test_.*\.py|.*_test\.(?:py|go|rs|rb)|.*\.test\.(?:js|jsx|ts|tsx)|.*\.spec\.(?:js|jsx|ts|tsx)|.*Test\.(?:swift|java|kt)|.*Tests\.(?:swift|java|kt)|conftest\.py)$"#)

/// A malformed literal is a programmer error that the pattern tests exercise.
private func regex(_ pattern: String) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern)
}

/// What a finished tool call reported about its process.
enum ObservedExit: Sendable {
    case zero, nonZero
    /// The tool failed or killed it, so the status says nothing about the check.
    case errored
    case notReported
    /// Still running when the result was written.
    case notFinished

    /// Codes the shell or the agent produced: not found, not executable,
    /// timed out, killed.
    private static let notFromTheCheck: Set<Int> = [124, 126, 127, 130, 137, 143]

    init(code: Int) {
        self = code == 0 ? .zero : Self.notFromTheCheck.contains(code) ? .errored : .nonZero
    }
}

/// An exit status decides only when the check is the whole command. Whatever
/// it leaves open goes to the runner's summary, and a call that did not exit
/// cleanly can confirm a failure from one but never a pass: a partial summary
/// does not contradict the status.
func checkResult(soleCommand: Bool, exit: ObservedExit, outputTail: String, kind: CheckKind) -> CheckResult {
    if RunnerSummary.ranNothing(outputTail: outputTail) { return .unknown }
    let summary = RunnerSummary.verdict(outputTail: outputTail, kind: kind)
    switch exit {
    case .notFinished:
        return .unknown
    case .nonZero where soleCommand:
        return .failed(.exitStatus)
    case .nonZero, .errored:
        return summary == false ? .failed(.runnerSummary) : .unknown
    case .zero where soleCommand:
        return .passed(.exitStatus)
    case .zero, .notReported:
        switch summary {
        case true?: return .passed(.runnerSummary)
        case false?: return .failed(.runnerSummary)
        case nil: return .unknown
        }
    }
}

// MARK: - Claude Code

/// Claude Code: a `tool_use` block in an assistant record, answered by a
/// `tool_result` block in a later user record, possibly in a later batch.
///
/// A call is classified when it opens, so only enums and a date wait for the
/// result. Ids repeat in transcripts, so each tracked id is opened once and a
/// replayed record cannot reopen a finished call.
struct ClaudeEvidenceExtractor: EvidenceExtractor {
    private enum Pending {
        case check(CheckKind, soleCommand: Bool, at: Date)
        case edit(at: Date, target: CodeChangeTarget)
    }

    private static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
    /// Error results for a call that never started.
    private static let neverRan = [
        "The user doesn't want to", "Permission to use", "Permission for this action", "Claude requested permissions",
        "Not started:", "[Tool call did not complete", "<tool_use_error>",
    ]

    private var pending: [String: Pending] = [:]
    private var tracked: Set<String> = []
    private var result = EvidenceFold()

    mutating func fold(_ lines: [String]) {
        for line in lines {
            // Most of a transcript's bytes are results of calls that were
            // never tracked, so a result is parsed only when its id is waiting.
            guard lineContains(line, "\"tool_use\"")
                    || (!pending.isEmpty && lineContains(line, "\"tool_result\"")
                        && pending.keys.contains(where: { lineContains(line, $0) })),
                  let record = jsonObject(line),
                  let blocks = (record["message"] as? [String: Any])?["content"] as? [[String: Any]]
            else { continue }
            let stamp = (record["timestamp"] as? String).flatMap(parseISODate)
            let cwd = record["cwd"] as? String
            for block in blocks {
                switch block["type"] as? String {
                case "tool_use": open(block, at: stamp, cwd: cwd)
                case "tool_result": close(block, at: stamp)
                default: continue
                }
            }
        }
    }

    private mutating func open(_ block: [String: Any], at stamp: Date?, cwd: String?) {
        guard let id = block["id"] as? String, let stamp, !tracked.contains(id),
              let name = block["name"] as? String,
              let input = block["input"] as? [String: Any]
        else { return }
        if name == "Bash" {
            guard let command = input["command"] as? String else { return }
            result.sawToolRecords = true
            guard let found = CommandClassifier.classify(script: command) else { return }
            tracked.insert(id)
            let sole = found.soleCommand && input["run_in_background"] as? Bool != true
            pending[id] = .check(found.kind, soleCommand: sole, at: stamp)
        } else if Self.editTools.contains(name) {
            guard let path = (input["file_path"] ?? input["notebook_path"]) as? String else { return }
            result.sawToolRecords = true
            guard isCodePath(path) else { return }
            tracked.insert(id)
            pending[id] = .edit(at: stamp, target: Self.target(name: name, input: input, path: path, root: cwd))
        }
    }

    private mutating func close(_ block: [String: Any], at completedAt: Date?) {
        guard let id = block["tool_use_id"] as? String, let call = pending.removeValue(forKey: id) else { return }
        let text = Self.text(of: block["content"])
        let isError = block["is_error"] as? Bool ?? false
        guard !(isError && Self.neverRan.contains(where: text.hasPrefix)) else { return }
        switch call {
        case .edit(let at, let target):
            if !isError {
                result.events.append(.codeChange(CodeChange(at: at, completedAt: completedAt, target: target)))
            }
        case .check(let kind, let sole, let at):
            let outcome = checkResult(
                soleCommand: sole, exit: Self.observedExit(isError: isError, text: text), outputTail: text, kind: kind)
            result.events.append(.check(ObservedCheck(at: at, completedAt: completedAt, kind: kind, result: outcome)))
        }
    }

    /// Classified when the call opens: the counts are what the text said then,
    /// and only numbers and a key wait for the result.
    private static func target(
        name: String, input: [String: Any], path: String, root: String?
    ) -> CodeChangeTarget {
        guard isTestPath(path, root: root) else { return .source }
        let key = PathKey(path: IncidentPaths.absolute(path, cwd: root) ?? path)
        switch name {
        case "Edit":
            guard input["replace_all"] as? Bool != true else { return .test(path: key, before: nil, after: nil) }
            return .test(
                path: key,
                before: (input["old_string"] as? String).map(patternCounts(in:)),
                after: (input["new_string"] as? String).map(patternCounts(in:)))
        case "MultiEdit":
            guard let edits = input["edits"] as? [[String: Any]], !edits.isEmpty,
                  !edits.contains(where: { $0["replace_all"] as? Bool == true })
            else { return .test(path: key, before: nil, after: nil) }
            return .test(
                path: key,
                before: joined(edits, "old_string").map(patternCounts(in:)),
                after: joined(edits, "new_string").map(patternCounts(in:)))
        default:
            // Write and NotebookEdit replace text this transcript never shows.
            return .test(path: key, before: nil, after: nil)
        }
    }

    private static func joined(_ edits: [[String: Any]], _ key: String) -> String? {
        var parts: [String] = []
        for edit in edits {
            guard let text = edit[key] as? String else { return nil }
            parts.append(text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// `is_error` also marks timeouts and aborts. Only a result that opens with
    /// "Exit code N" reports what the process returned. The background note can
    /// follow partial output, so it is searched for rather than matched at the start.
    private static func observedExit(isError: Bool, text: String) -> ObservedExit {
        if text.hasPrefix("Command running in background") || text.hasPrefix("Command was manually backgrounded")
            || text.contains("Command was moved to the background") {
            return .notFinished
        }
        guard isError else { return .zero }
        guard text.hasPrefix("Exit code "), !text.contains("Command timed out after"), !text.contains("Command killed:"),
              let code = Int(text.dropFirst("Exit code ".count).prefix { $0 == "-" || $0.isNumber })
        else { return .errored }
        return ObservedExit(code: code)
    }

    private static func text(of content: Any?) -> String {
        switch content {
        case let string as String: return string
        case let blocks as [[String: Any]]: return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        default: return ""
        }
    }

    mutating func finish() -> EvidenceFold {
        for case .check(let kind, _, let at) in pending.values {
            result.events.append(.check(ObservedCheck(at: at, completedAt: nil, kind: kind, result: .unknown)))
        }
        pending = [:]
        return result
    }
}

// MARK: - Codex

/// Codex: one `item_completed` event per finished command or file change.
/// A command carries its own exit code, duration and output, so no state
/// crosses a record. The workspace root does cross records: `session_meta` and
/// `turn_context` each name the current `cwd`, and an edit is read relative to
/// the latest one before it.
struct CodexEvidenceExtractor: EvidenceExtractor {
    private var cwd: String?
    private var result = EvidenceFold()

    mutating func fold(_ lines: [String]) {
        for line in lines {
            // The substring test is only a prefilter: a file named `session_meta`
            // puts that token in a FileChange's own JSON, and that change must
            // still be read. The record's type decides.
            let mayBeMetadata = lineContains(line, "\"session_meta\"") || lineContains(line, "\"turn_context\"")
            guard mayBeMetadata
                    || (lineContains(line, "\"item_completed\"")
                        && (lineContains(line, "\"CommandExecution\"") || lineContains(line, "\"FileChange\""))),
                  let record = jsonObject(line)
            else { continue }
            let type = record["type"] as? String
            if type == "session_meta" || type == "turn_context" {
                if let payload = record["payload"] as? [String: Any],
                   let path = payload["cwd"] as? String, !path.isEmpty {
                    cwd = path
                }
                continue
            }
            guard type == "event_msg",
                  let payload = record["payload"] as? [String: Any],
                  payload["type"] as? String == "item_completed",
                  let item = payload["item"] as? [String: Any],
                  let stamp = (record["timestamp"] as? String).flatMap(parseISODate)
            else { continue }
            switch item["type"] as? String {
            case "CommandExecution": command(item, completedAt: stamp)
            case "FileChange": change(item, at: stamp)
            default: continue
            }
        }
    }

    private mutating func command(_ item: [String: Any], completedAt stamp: Date) {
        guard let argv = item["command"] as? [String] else { return }
        result.sawToolRecords = true
        guard ["completed", "failed"].contains(item["status"] as? String) else { return }
        let script = argv.count >= 3 && ["-lc", "-c"].contains(argv[1]) ? argv[2] : argv.joined(separator: " ")
        guard let found = CommandClassifier.classify(script: script) else { return }
        let duration = item["duration"] as? [String: Any]
        let seconds = Double(jsonInt(duration?["secs"])) + Double(jsonInt(duration?["nanos"])) / 1e9
        let exit = (item["exit_code"] as? NSNumber).map { ObservedExit(code: $0.intValue) } ?? .notReported
        let outcome = checkResult(
            soleCommand: found.soleCommand, exit: exit, outputTail: item["aggregated_output"] as? String ?? "", kind: found.kind)
        result.events.append(.check(ObservedCheck(
            at: stamp.addingTimeInterval(-seconds), completedAt: stamp, kind: found.kind, result: outcome)))
    }

    private mutating func change(_ item: [String: Any], at stamp: Date) {
        guard let changes = item["changes"] as? [String: Any] else { return }
        result.sawToolRecords = true
        guard item["status"] as? String == "completed" else { return }
        let paths = changes.keys.filter(isCodePath)
        guard !paths.isEmpty else { return }
        var target = CodeChangeTarget.source
        // One test path is enough to make the change a test edit; the key comes
        // from the first of them in sorted order so a set never picks at random.
        for path in paths.sorted() where isTestPath(path, root: cwd) {
            target = .test(
                path: PathKey(path: IncidentPaths.absolute(path, cwd: cwd) ?? path), before: nil, after: nil)
            break
        }
        result.events.append(.codeChange(CodeChange(at: stamp, completedAt: stamp, target: target)))
    }

    mutating func finish() -> EvidenceFold { result }
}
