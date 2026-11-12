import Foundation

/// The credential table, its match rule, and the per-reader option table that
/// decides which operand of one shell simple command is read.
///
/// Pure. `firstMatch` sees one command's words and the record's `cwd` and
/// returns a class and the resolved path, so nothing it reads can outlive the
/// call.
///
/// Match rule, applied to a resolved absolute path:
/// - it equals a table path;
/// - it lies under a table directory prefix;
/// - or its last component is a table name family at a dot boundary, so the
///   `.env` family matches `.env`, `.env.local` and `.env.production` but not
///   `.envrc`.
///
/// Then the excluded names drop out.
enum CredentialTable {
    struct Hit: Equatable {
        let credentialClass: CredentialClass
        /// Nil for a keychain item, which has no file path.
        let path: String?
    }

    // MARK: - Table

    private enum Entry {
        case path(String)
        case directory(String)
        case family(String)
    }

    private struct Rule {
        let credentialClass: CredentialClass
        let entry: Entry
    }

    private static let rules: [Rule] = [
        Rule(credentialClass: .dotEnv, entry: .family(".env")),
        Rule(credentialClass: .sshKey, entry: .directory("~/.ssh")),
        Rule(credentialClass: .awsCredentials, entry: .directory("~/.aws")),
        Rule(credentialClass: .netrc, entry: .path("~/.netrc")),
        Rule(credentialClass: .netrc, entry: .path("~/.git-credentials")),
        Rule(credentialClass: .packageToken, entry: .path("~/.npmrc")),
        Rule(credentialClass: .packageToken, entry: .path("~/.pypirc")),
        Rule(credentialClass: .packageToken, entry: .path("~/.config/pip/pip.conf")),
        Rule(credentialClass: .gitHubCLI, entry: .path("~/.config/gh/hosts.yml")),
        Rule(credentialClass: .gitHubCLI, entry: .path("~/.config/gh/hosts.yaml")),
        Rule(credentialClass: .agentCredential, entry: .path("~/.claude/.credentials.json")),
        Rule(credentialClass: .agentCredential, entry: .path("~/.codex/auth.json")),
    ]

    /// A template, a public key and the agent's own display settings are not
    /// secrets, and `~/.ssh/config` and `~/.aws/config` hold no credential.
    private static let excludedNames: Set<String> = [
        ".env.example", ".env.sample", ".env.template", "known_hosts", "authorized_keys",
    ]
    private static let excludedPaths = ["~/.ssh/config", "~/.aws/config"]

    /// The class of one resolved absolute path, or nil when the table says it
    /// is not a credential.
    static func credentialClass(ofResolved path: String) -> CredentialClass? {
        let name = (path as NSString).lastPathComponent
        if isExcluded(name: name, path: path) { return nil }
        for rule in rules {
            switch rule.entry {
            case .path(let raw):
                if IncidentPaths.absolute(raw, cwd: "/") == path { return rule.credentialClass }
            case .directory(let raw):
                if let root = IncidentPaths.absolute(raw, cwd: "/"), IncidentPaths.isWithin(path, root: root) {
                    return rule.credentialClass
                }
            case .family(let family):
                if name == family || name.hasPrefix(family + ".") { return rule.credentialClass }
            }
        }
        return nil
    }

    private static func isExcluded(name: String, path: String) -> Bool {
        if excludedNames.contains(name) || name.hasSuffix(".pub") { return true }
        return excludedPaths.contains { IncidentPaths.absolute($0, cwd: "/") == path }
    }

    // MARK: - Reader rule

    /// The first operand of one already-unwrapped simple command that names a
    /// credential, or nil. `words[0]` is the command word.
    static func firstMatch(in words: [String], cwd: String?) -> Hit? {
        guard let command = words.first else { return nil }
        let name = basename(command)
        if name == "security" {
            let verbs: Set<String> = ["find-generic-password", "find-internet-password"]
            if let verb = words.dropFirst().first, verbs.contains(verb) {
                return Hit(credentialClass: .keychain, path: nil)
            }
            return nil
        }
        guard let reader = readers[name] else { return nil }
        guard let candidates = operands(withoutRedirects(Array(words.dropFirst())), reader) else { return nil }
        for raw in candidates {
            guard !raw.isEmpty else { continue }
            guard let path = IncidentPaths.absolute(raw, cwd: cwd) else { continue }
            if let credentialClass = credentialClass(ofResolved: path) {
                return Hit(credentialClass: credentialClass, path: path)
            }
        }
        return nil
    }

    /// Drops `> file`, `>> file`, `2>file` and `< file`, with the target in
    /// the same word or the next one. A redirect target is not an operand.
    private static func withoutRedirects(_ words: [String]) -> [String] {
        var kept: [String] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let afterDigits = word.drop { $0.isNumber || $0 == "&" }
            let operatorLength = afterDigits.hasPrefix(">>") ? 2 : afterDigits.hasPrefix(">") || afterDigits.hasPrefix("<") ? 1 : 0
            guard operatorLength > 0 else {
                kept.append(word)
                index += 1
                continue
            }
            index += afterDigits.dropFirst(operatorLength).isEmpty ? 2 : 1
        }
        return kept
    }

    private static func basename(_ word: String) -> String {
        word.split(separator: "/").last.map(String.init) ?? word
    }

    // MARK: - Options per reader

    private enum Operands {
        case all
        /// `source` and `.`: only the first operand.
        case first
        /// `cp`, `scp`: every operand except the last, or all with `-t`.
        case allButLast(allWhenT: Bool)
        /// `grep`, `rg`: every operand after the first, or all with `-e`/`-f`.
        case afterFirst(allWithPattern: Bool)
    }

    private struct Reader {
        var bools: Set<String> = []
        /// Options whose value is a file the command reads, so it is matched
        /// against the table like an operand.
        var valueInput: Set<String> = []
        /// Options whose value is a literal or an output destination.
        var valueSkip: Set<String> = []
        var operands: Operands = .all
        /// `head -5`, `tail -20`.
        var bareCount = false
    }

    private static let catReader = Reader(bools: [
        "-n", "-b", "-e", "-s", "-t", "-u", "-v", "-A", "-E", "-T",
    ])
    private static let pagerReader = Reader(bools: ["-R", "-N", "-S", "-d"])
    private static let sourceReader = Reader(operands: .first)
    private static let base64Reader = Reader(
        bools: ["-d", "-D"], valueInput: ["-i", "--input"],
        valueSkip: ["-o", "--output", "-b", "--break"])
    private static let headReader = Reader(
        bools: ["-q", "-v", "-f", "-F"], valueSkip: ["-n", "-c"], bareCount: true)
    private static let cpReader = Reader(
        bools: ["-a", "-f", "-i", "-n", "-p", "-r", "-R", "-v", "-L", "-P", "-H"],
        valueSkip: ["-S", "-t"], operands: .allButLast(allWhenT: true))
    /// `-i` is a deliberate suppression: a deploy key on the command line is
    /// routine, and its path is not what the rule is looking for.
    private static let scpReader = Reader(
        bools: ["-r", "-p", "-q", "-C", "-3", "-4", "-6", "-B", "-O", "-T", "-v", "-A"],
        valueSkip: ["-P", "-l", "-o", "-c", "-J", "-F", "-i"],
        operands: .allButLast(allWhenT: false))
    private static let grepReader = Reader(
        bools: ["-r", "-R", "-n", "-i", "-l", "-L", "-H", "-h", "-s", "-v", "-w", "-c", "-q", "-E", "-F", "-I", "-o"],
        valueInput: ["-f", "--file"],
        valueSkip: ["-e", "-A", "-B", "-C", "-m", "-g", "--include", "--exclude"],
        operands: .afterFirst(allWithPattern: true))

    private static let readers: [String: Reader] = [
        "cat": catReader,
        "less": pagerReader,
        "more": pagerReader,
        "source": sourceReader,
        ".": sourceReader,
        "base64": base64Reader,
        "head": headReader,
        "tail": headReader,
        "cp": cpReader,
        "scp": scpReader,
        "grep": grepReader,
        "rg": grepReader,
    ]

    /// The candidate operands in command-line order, or nil when the command
    /// uses an option this table does not know: a finding is not guessed.
    private static func operands(_ args: [String], _ reader: Reader) -> [String]? {
        var values: [(value: String, positional: Bool)] = []
        var hasPattern = false
        var hasT = false
        var index = 0
        while index < args.count {
            let word = args[index]
            if word == "--" {
                for rest in args[(index + 1)...] { values.append((rest, true)) }
                break
            }
            if word.hasPrefix("--"), word.count > 2 {
                let parts = word.split(separator: "=", maxSplits: 1)
                let name = String(parts[0])
                let inline: String? = parts.count > 1 ? String(parts[1]) : nil
                if reader.bools.contains(name) {
                    index += 1
                    continue
                }
                if reader.valueInput.contains(name) {
                    if let inline {
                        values.append((inline, false))
                    } else if index + 1 < args.count {
                        values.append((args[index + 1], false))
                        index += 1
                    } else {
                        return nil
                    }
                    if name == "--file" { hasPattern = true }
                    index += 1
                    continue
                }
                if reader.valueSkip.contains(name) {
                    if inline == nil {
                        guard index + 1 < args.count else { return nil }
                        index += 1
                    }
                    index += 1
                    continue
                }
                return nil
            }
            if word.hasPrefix("-"), word != "-", word != "--" {
                if reader.bareCount, word.dropFirst().allSatisfy(\.isNumber) {
                    index += 1
                    continue
                }
                if reader.bools.contains(word) {
                    index += 1
                    continue
                }
                if reader.valueInput.contains(word) {
                    guard index + 1 < args.count else { return nil }
                    values.append((args[index + 1], false))
                    if word == "-f" { hasPattern = true }
                    index += 2
                    continue
                }
                if reader.valueSkip.contains(word) {
                    guard index + 1 < args.count else { return nil }
                    if word == "-e" { hasPattern = true }
                    if word == "-t" { hasT = true }
                    index += 2
                    continue
                }
                // A cluster of boolean flags, or a value attached to a short
                // option, as in `grep -rn` or `head -n5`.
                let chars = Array(word.dropFirst())
                if let first = chars.first {
                    let option = "-\(first)"
                    if reader.valueInput.contains(option) || reader.valueSkip.contains(option) {
                        let attached = String(chars.dropFirst())
                        if reader.valueInput.contains(option), !attached.isEmpty {
                            values.append((attached, false))
                        }
                        if option == "-f" { hasPattern = true }
                        if option == "-e" { hasPattern = true }
                        if option == "-t" { hasT = true }
                        index += 1
                        continue
                    }
                    if !chars.isEmpty, chars.allSatisfy({ reader.bools.contains("-\($0)") }) {
                        index += 1
                        continue
                    }
                }
                return nil
            }
            values.append((word, true))
            index += 1
        }

        let positional = values.enumerated().filter { $0.element.positional }.map(\.offset)
        let counted: Set<Int>
        switch reader.operands {
        case .all:
            counted = Set(positional)
        case .first:
            counted = Set(positional.prefix(1))
        case .allButLast(let allWhenT):
            if allWhenT && hasT {
                counted = Set(positional)
            } else {
                counted = Set(positional.dropLast())
            }
        case .afterFirst(let allWithPattern):
            if allWithPattern && hasPattern {
                counted = Set(positional)
            } else {
                counted = Set(positional.dropFirst())
            }
        }
        return values.enumerated()
            .filter { !$0.element.positional || counted.contains($0.offset) }
            .map(\.element.value)
    }
}
