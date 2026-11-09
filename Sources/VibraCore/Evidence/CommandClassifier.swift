import Foundation

/// Decides whether a shell command line runs a test, build or lint command,
/// and whether the line's exit status belongs to that check alone.
///
/// Only one simple command qualifies. A parser cannot follow `exit`, subshells,
/// `set -e` or functions, and across `&&` Claude Code's `is_error` follows the
/// last command's rules: `check && grep x` is not an error when `grep` or the
/// check exits 1.
///
/// Pure. It sees command text and returns two enums, so nothing it reads can
/// outlive the call. `tools/evidence-oracle` runs the same case file.
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

    /// These report on the tool, or exit 0 without checking anything.
    private static let notAChecking: Set<String> = [
        "--version", "-version", "-V", "--help", "-h", "-usage", "--show-bin-path", "--collect-only", "--co",
        "-list", "--list", "--list-tests", "--listTests", "-showBuildSettings", "-showsdks", "-showdestinations",
        "-showTestPlans", "-resolvePackageDependencies", "--no-run", "--dry-run", "-dry-run", "--just-print",
        "--fixtures", "--markers", "--setup-plan", "--setup-only", "--showConfig", "--print-config", "--init",
        "--show-files", "--show-settings", "--exit-zero", "--if-present", "--passWithNoTests",
        "--show-codecov-path", "--skip-build", "--ignore-errors", "--recon", "--clearCache", "--install-types",
        "--fix-only", "--add-noqa", "--clean", "--dry", "--listFilesOnly", "--noCheck", "--collectonly",
        "--fixtures-per-test", "--cache-show", "--env-info", "-enumerate-tests",
    ]
    /// The same words mean something else to other tools: `pytest -n 4` runs.
    private static let notACheckingFor: [String: Set<String>] = [
        "make": ["-n", "-q", "-i"], "go": ["-n", "-c"], "tsc": ["-v"], "eslint": ["-v"], "swift": ["list", "-l"],
        "vitest": ["list", "init"], "ruff": ["--diff"], "xcodebuild": ["clean"],
    ]

    /// Wrappers dropped from the front of a segment. A value is how many
    /// words follow the wrapper and go with it.
    private static let wrappers: [String: Int] = [
        "env": 0, "time": 0, "command": 0, "timeout": 1, "npx": 0, "bunx": 0,
        "do": 0, "then": 0, "if": 0, "elif": 0, "else": 0, "while": 0, "until": 0,
    ]
    private static let runWrappers: [[String]] = [["uv", "run"], ["poetry", "run"]]
    private static let runOptionsTakingValue: Set<String> = [
        "--with", "--with-editable", "--with-requirements", "--python", "-p", "--extra", "--group",
        "--only-group", "--project", "--directory", "--package", "--env-file", "--index", "--default-index",
    ]
    private static let runOptionsAlone: Set<String> = [
        "--no-project", "--no-sync", "-q", "--quiet", "-v", "--verbose", "--offline", "--frozen", "--locked",
        "--isolated", "--all-extras", "--all-groups", "--no-dev", "--dev", "--active", "--exact",
    ]
    /// These change what a command does, or end the shell before it runs.
    private static let controlWords: Set<String> = [
        "exit", "return", "trap", "set", "setopt", "eval", "exec", "source", ".", "function", "case", "if", "then",
        "else", "elif", "fi", "for", "while", "until", "do", "done", "{", "}", "!",
    ]

    static func classify(script: String) -> (kind: CheckKind, soleCommand: Bool)? {
        let segments = split(script)
        var kinds: [CheckKind] = []
        for (index, segment) in segments.enumerated() {
            if index > 0, segments[index - 1].separator == .pipe { continue }
            if let kind = checkKind(of: segment.words) { kinds.append(kind) }
        }
        guard let strongest = CheckKind.allCases.first(where: kinds.contains) else { return nil }
        return (strongest, isSoleSimpleCommand(segments))
    }

    private static func isSoleSimpleCommand(_ segments: [Segment]) -> Bool {
        guard segments.count == 1, segments[0].separator == nil,
              let first = segments[0].words.first, !controlWords.contains(first)
        else { return false }
        return !segments[0].words.contains { $0.contains("(") || $0.contains(")") || $0.contains("`") }
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
                if first == "npx" || first == "bunx" {
                    while let option = words.first, option.hasPrefix("-") {
                        guard option == "-y" || option == "--yes" else { return nil }
                        words.removeFirst()
                    }
                }
            } else if words.count > 1, [basename(first), words[1]] == ["pnpm", "exec"] {
                words.removeFirst(2)
            } else if words.count > 1, runWrappers.contains([basename(first), words[1]]) {
                return match(afterRunOptions(Array(words.dropFirst(2))))
            } else {
                break
            }
        }
        return match(words)
    }

    /// An option this does not know may take a value that looks like a
    /// program, so it ends the search with no program.
    private static func afterRunOptions(_ words: [String]) -> [String] {
        var index = 0
        while index < words.count, words[index].hasPrefix("-") {
            let name = words[index].split(separator: "=", maxSplits: 1).first.map(String.init) ?? words[index]
            if runOptionsTakingValue.contains(name) {
                index += words[index].contains("=") ? 1 : 2
            } else if runOptionsAlone.contains(name) {
                index += 1
            } else {
                return []
            }
        }
        return Array(words.dropFirst(index))
    }

    private static func match(_ rawWords: [String]) -> CheckKind? {
        guard let rawFirst = rawWords.first, !rawFirst.contains(")") else { return nil }
        let words = rawWords.map { String($0.reversed().drop { $0 == ")" }.reversed()) }
        let name = basename(rawFirst)
        guard notAChecking.isDisjoint(with: words), notACheckingFor[name]?.isDisjoint(with: words) ?? true else { return nil }
        let normalized = [name] + words.dropFirst()
        return runners.first { runner in
            normalized.starts(with: runner.prefix)
                && runner.requires.map { normalized.dropFirst(runner.prefix.count).contains($0) } ?? true
        }?.kind
    }

    private static func basename(_ word: String) -> String {
        let name = word.split(separator: "/").last.map(String.init) ?? word
        return name.range(of: #"^python[0-9.]*$"#, options: .regularExpression) != nil ? "python" : name
    }

    private static func delimiter(in chars: [Character], after start: Int) -> (word: String, stripsTabs: Bool) {
        var i = start
        let stripsTabs = i < chars.count && chars[i] == "-"
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
        return (word, stripsTabs)
    }

    /// The index just past the delimiter's own line, or the end when it never closes.
    private static func indexAfterHeredoc(
        in chars: [Character], from start: Int, delimiter: (word: String, stripsTabs: Bool)
    ) -> Int {
        var lineStart = start
        while lineStart < chars.count {
            let lineEnd = chars[lineStart...].firstIndex(of: "\n") ?? chars.count
            let line = String(chars[lineStart..<lineEnd])
            if (delimiter.stripsTabs ? String(line.drop { $0 == "\t" }) : line) == delimiter.word {
                return min(lineEnd + 1, chars.count)
            }
            lineStart = lineEnd + 1
        }
        return chars.count
    }

    /// `open` is the index of the opening parenthesis of `$(`, `<(` or `>(`.
    private static func indexAfterSubstitution(in chars: [Character], open: Int) -> Int {
        var depth = 0
        var quote: Character?
        var i = open
        while i < chars.count {
            let c = chars[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "'" || c == "\"" {
                quote = c
            } else if c == "(" {
                depth += 1
            } else if c == ")" {
                depth -= 1
                if depth == 0 { return i + 1 }
            }
            i += 1
        }
        return chars.count
    }

    private static func indexAfterBacktick(in chars: [Character], open: Int) -> Int {
        var i = open + 1
        while i < chars.count, chars[i] != "`" { i += chars[i] == "\\" ? 2 : 1 }
        return min(i + 1, chars.count)
    }

    /// Quote-aware, one pass. A heredoc's body is dropped, because it is data
    /// and not commands, and parsing resumes after its closing delimiter. A
    /// substitution stays inside its word: its exit status is not the line's.
    private static func split(_ script: String) -> [Segment] {
        var segments: [Segment] = []
        var current = Segment()
        var word = ""
        var hasWord = false
        var quote: Character?
        var heredocDelimiter: (word: String, stripsTabs: Bool)?
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
        func take(through end: Int) {
            word.append(contentsOf: String(chars[i..<end]))
            hasWord = true
            i = end
        }

        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if let q = quote {
                if q == "\"", c == "$", next == "(" {
                    take(through: indexAfterSubstitution(in: chars, open: i + 1))
                    continue
                }
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
                if hasWord || !current.words.isEmpty { endSegment(.newline) }
                if let delimiter = heredocDelimiter {
                    heredocDelimiter = nil
                    i = indexAfterHeredoc(in: chars, from: i + 1, delimiter: delimiter)
                    continue
                }
            case "$" where next == "'":
                var end = i + 2
                while end < chars.count, chars[end] != "'" { end += chars[end] == "\\" ? 2 : 1 }
                take(through: min(end + 1, chars.count))
                continue
            case "$" where next == "(":
                take(through: indexAfterSubstitution(in: chars, open: i + 1))
                continue
            case "<" where next == "(", ">" where next == "(":
                take(through: indexAfterSubstitution(in: chars, open: i + 1))
                continue
            case "`":
                take(through: indexAfterBacktick(in: chars, open: i))
                continue
            case ";":
                endSegment(.semicolon)
            case "|":
                let previous: Character? = i > 0 ? chars[i - 1] : nil
                if next == "|" { i += 1; endSegment(.or) }
                else if previous == ">" { word.append(c); hasWord = true }
                else { if next == "&" { i += 1 }; endSegment(.pipe) }
            case "&":
                let previous: Character? = i > 0 ? chars[i - 1] : nil
                if next == "&" { i += 1; endSegment(.and) }
                else if next == ">" || previous == ">" || previous == "<" { word.append(c); hasWord = true }
                else { endSegment(.background) }
            case "<" where next == "<":
                if i + 2 < chars.count, chars[i + 2] == "<" {
                    take(through: i + 3)
                    continue
                }
                heredocDelimiter = delimiter(in: chars, after: i + 2)
                take(through: i + 2)
                continue
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
