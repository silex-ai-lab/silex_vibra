import Foundation

/// Decides whether a shell command line runs a test, build or lint command,
/// and whether the line's own exit status can be trusted to describe it.
///
/// Pure. It sees command text and returns two enums, so nothing it reads can
/// outlive the call.
enum CommandClassifier {
    private enum Separator { case and, or, semicolon, pipe, background, newline }

    private struct Segment {
        var words: [String] = []
        var separator: Separator?
    }

    private struct Runner {
        let kind: CheckKind
        let prefix: [String]
        var requires: String?
    }

    /// First match wins, so a `requires` entry precedes the looser entry for
    /// the same tool. `python` stands for `python`, `python3`, `python3.12`.
    /// `{pm}` stands for npm, pnpm, yarn and bun, with or without `run`.
    private static let table: [(kind: CheckKind, command: String, requires: String?)] = [
        (.test, "swift test", nil), (.test, "make test", nil), (.test, "make check", nil),
        (.test, "xcodebuild", "test"), (.test, "pytest", nil), (.test, "python -m pytest", nil),
        (.test, "python -m unittest", nil), (.test, "{pm} test", nil), (.test, "vitest", nil),
        (.test, "jest", nil), (.test, "cargo test", nil), (.test, "go test", nil),
        (.build, "swift build", nil), (.build, "make build", nil), (.build, "xcodebuild", nil),
        (.build, "{pm} build", nil), (.build, "cargo build", nil), (.build, "cargo check", nil),
        (.build, "go build", nil), (.build, "tsc", nil),
        (.lint, "make lint", nil), (.lint, "{pm} lint", nil), (.lint, "{pm} typecheck", nil),
        (.lint, "cargo clippy", nil), (.lint, "go vet", nil), (.lint, "ruff check", nil),
        (.lint, "mypy", nil), (.lint, "eslint", nil),
    ]

    private static let runners: [Runner] = table.flatMap { entry -> [Runner] in
        let words = entry.command.split(separator: " ").map(String.init)
        guard let slot = words.firstIndex(of: "{pm}") else {
            return [Runner(kind: entry.kind, prefix: words, requires: entry.requires)]
        }
        return ["npm", "pnpm", "yarn", "bun"].flatMap { pm -> [Runner] in
            var plain = words
            plain[slot] = pm
            var viaRun = plain
            viaRun.insert("run", at: slot + 1)
            return [plain, viaRun].map { Runner(kind: entry.kind, prefix: $0, requires: entry.requires) }
        }
    }

    /// Wrappers dropped from the front of a segment. A value is how many
    /// words follow the wrapper and go with it.
    private static let wrappers: [String: Int] = [
        "env": 0, "time": 0, "command": 0, "timeout": 1, "npx": 0, "bunx": 0, "do": 0, "then": 0,
    ]
    /// Their options can take values (`--with x`), so any later word may start
    /// the program.
    private static let runWrappers: [[String]] = [["uv", "run"], ["poetry", "run"]]

    static func classify(script: String) -> (kind: CheckKind, exitVisible: Bool)? {
        let segments = split(script)
        var pipefail = false
        var kinds: [CheckKind] = []
        var allVisible = true
        for (index, segment) in segments.enumerated() {
            if segment.words.first == "set", segment.words.contains("pipefail") { pipefail = true }
            if index > 0, segments[index - 1].separator == .pipe { continue }
            guard let kind = checkKind(of: segment.words) else { continue }
            kinds.append(kind)
            let tail = segments[index...].compactMap(\.separator)
            let pipeOK = pipefail
            let visible = tail.allSatisfy { $0 == .and || ($0 == .pipe && pipeOK) }
            if !visible { allVisible = false }
        }
        guard let strongest = CheckKind.allCases.first(where: kinds.contains) else { return nil }
        return (strongest, allVisible)
    }

    private static func checkKind(of rawWords: [String]) -> CheckKind? {
        var words = rawWords
        while let first = words.first {
            if first.hasPrefix("(") {
                words[0] = String(first.drop { $0 == "(" })
                if words[0].isEmpty { words.removeFirst() }
            } else if first.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil {
                words.removeFirst()
            } else if let extra = wrappers[basename(first)] {
                words.removeFirst(min(words.count, 1 + extra))
                if first == "npx" || first == "bunx" { while words.first?.hasPrefix("-") == true { words.removeFirst() } }
            } else if words.count > 1, [basename(first), words[1]] == ["pnpm", "exec"] {
                words.removeFirst(2)
            } else if words.count > 1, runWrappers.contains([basename(first), words[1]]) {
                return words.indices.dropFirst(2).lazy.compactMap { match(Array(words[$0...])) }.first
            } else {
                break
            }
        }
        return match(words)
    }

    private static func match(_ rawWords: [String]) -> CheckKind? {
        let words = rawWords.map { String($0.reversed().drop { $0 == ")" }.reversed()) }
        guard let first = words.first else { return nil }
        let normalized = [basename(first)] + words.dropFirst()
        return runners.first { runner in
            normalized.starts(with: runner.prefix)
                && runner.requires.map { normalized.dropFirst(runner.prefix.count).contains($0) } ?? true
        }?.kind
    }

    private static func basename(_ word: String) -> String {
        let name = word.split(separator: "/").last.map(String.init) ?? word
        return name.range(of: #"^python[0-9.]*$"#, options: .regularExpression) != nil ? "python" : name
    }

    private static func delimiter(in chars: [Character], after start: Int) -> String {
        var i = start
        while i < chars.count, chars[i] == "-" || chars[i] == " " || chars[i] == "\t" { i += 1 }
        var word = ""
        var quote: Character?
        while i < chars.count {
            let c = chars[i]
            if let q = quote {
                if c == q { quote = nil } else { word.append(c) }
            } else if c == "'" || c == "\"" {
                quote = c
            } else if c.isWhitespace || ";|&<>()".contains(c) {
                break
            } else if c != "\\" {
                word.append(c)
            }
            i += 1
        }
        return word
    }

    /// The index just past the delimiter's own line, or the end when it never closes.
    private static func indexAfterHeredoc(in chars: [Character], from start: Int, delimiter: String) -> Int {
        var lineStart = start
        while lineStart < chars.count {
            let lineEnd = chars[lineStart...].firstIndex(of: "\n") ?? chars.count
            let line = String(chars[lineStart..<lineEnd]).trimmingCharacters(in: .whitespaces)
            if line == delimiter { return min(lineEnd + 1, chars.count) }
            lineStart = lineEnd + 1
        }
        return chars.count
    }

    /// Quote-aware, one pass. A heredoc's body is dropped, because it is data
    /// and not commands, and parsing resumes after its closing delimiter.
    private static func split(_ script: String) -> [Segment] {
        var segments: [Segment] = []
        var current = Segment()
        var word = ""
        var hasWord = false
        var quote: Character?
        var heredocDelimiter: String?
        let chars = Array(script)
        var i = 0

        func endWord() {
            if hasWord { current.words.append(word) }
            word = ""
            hasWord = false
        }
        func endSegment(_ separator: Separator) {
            endWord()
            current.separator = separator
            segments.append(current)
            current = Segment()
        }

        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if let q = quote {
                if c == q { quote = nil }
                else if c == "\\", q == "\"", let next { word.append(next); i += 1 }
                else { word.append(c) }
                i += 1
                continue
            }
            switch c {
            case "'", "\"":
                quote = c
                hasWord = true
            case "\\":
                if next == "\n" { i += 1 } else if let next { word.append(next); hasWord = true; i += 1 }
            case "#" where !hasWord:
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            case " ", "\t":
                endWord()
            case "\n":
                endSegment(.newline)
                if let delimiter = heredocDelimiter {
                    heredocDelimiter = nil
                    i = indexAfterHeredoc(in: chars, from: i + 1, delimiter: delimiter)
                    continue
                }
            case ";":
                endSegment(.semicolon)
            case "|":
                if next == "|" { i += 1; endSegment(.or) }
                else { if next == "&" { i += 1 }; endSegment(.pipe) }
            case "&":
                let previous: Character? = i > 0 ? chars[i - 1] : nil
                if next == "&" { i += 1; endSegment(.and) }
                else if next == ">" || previous == ">" || previous == "<" { word.append(c); hasWord = true }
                else { endSegment(.background) }
            case "<":
                if next == "<", i + 2 >= chars.count || chars[i + 2] != "<" {
                    heredocDelimiter = delimiter(in: chars, after: i + 2)
                }
                word.append(c)
                hasWord = true
            default:
                word.append(c)
                hasWord = true
            }
            i += 1
        }
        endWord()
        if !current.words.isEmpty { segments.append(current) }
        while let last = segments.last, last.words.isEmpty { segments.removeLast() }
        if let last = segments.last, last.separator != .background {
            segments[segments.count - 1].separator = nil
        }
        return segments
    }
}
