import CryptoKit
import Foundation

/// Resolves a path the way every path rule in this feature does: expand a
/// leading `~`, `$HOME` or `${HOME}` against `VibraPaths.home`, resolve a
/// relative path against `cwd`, standardize, and fold `/private/var` and
/// `/private/tmp` onto their public names. Symlinks are never resolved.
///
/// Pure. A path that cannot be resolved, or a relative path with no `cwd`,
/// returns nil and the caller makes no finding.
enum IncidentPaths {
    static func absolute(_ raw: String, cwd: String?) -> String? {
        guard !raw.isEmpty else { return nil }
        let home = VibraPaths.home.path
        var value = raw
        if value == "~" || value == "$HOME" || value == "${HOME}" {
            value = home
        } else if value.hasPrefix("~/") {
            value = home + value.dropFirst(1)
        } else if value.hasPrefix("$HOME/") {
            value = home + value.dropFirst(5)
        } else if value.hasPrefix("${HOME}/") {
            value = home + value.dropFirst(7)
        }
        if !value.hasPrefix("/") {
            guard let cwd, cwd.hasPrefix("/") else { return nil }
            value = cwd + "/" + value
        }
        return stripPrivate(URL(fileURLWithPath: value).standardizedFileURL.path)
    }

    private static func stripPrivate(_ path: String) -> String {
        for prefix in ["/private/var", "/private/tmp"] where path == prefix || path.hasPrefix(prefix + "/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    static func isWithin(_ path: String, root: String) -> Bool {
        if root == "/" { return path.hasPrefix("/") }
        return path == root || path.hasPrefix(root + "/")
    }

    /// The scratch prefixes `EvidenceExtractor` already ignores.
    static func isScratch(_ path: String) -> Bool {
        ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"]
            .contains(where: path.hasPrefix)
    }

    /// A session and destination family share one write finding. `sibling`
    /// is under the parent of the workspace, unless that parent is home or the
    /// root, where it would mean everything.
    static func writeFamily(of path: String, workspace root: String) -> String {
        let parent = (root as NSString).deletingLastPathComponent
        if parent != "/", parent != VibraPaths.home.path, isWithin(path, root: parent) {
            return "session-write-outside-sibling"
        }
        return "session-write-outside-elsewhere"
    }

    /// The agents' own state. One list, so a second root is one edit.
    static let agentStateRoots = ["~/.claude/projects"]

    static func isAgentState(_ path: String) -> Bool {
        agentStateRoots.contains { root in
            guard let resolved = absolute(root, cwd: "/") else { return false }
            return isWithin(path, root: resolved)
        }
    }
}

/// `git push` with an unconditional force and no dry run. A bare
/// `--force-with-lease` is the safe form and never reaches the force test.
/// Short options may be clustered, as in `-fu`.
func isForcePush(_ words: [String]) -> Bool {
    guard let first = words.first, first.split(separator: "/").last.map(String.init) == "git" else { return false }
    var index = 1
    while index < words.count, words[index] == "-C" || words[index] == "-c" {
        index += 2
    }
    guard index < words.count, words[index] == "push" else { return false }
    var force = false
    for word in words[(index + 1)...] {
        if word == "--dry-run" { return false }
        if word == "--force" { force = true }
        if word.hasPrefix("+"), word.count > 1 { force = true }
        if word.hasPrefix("-"), !word.hasPrefix("--"), word.count > 1 {
            if word.contains("n") { return false }
            if word.contains("f") { force = true }
        }
    }
    return force
}

// MARK: - Claude Code

/// Folds one Claude Code transcript, in order, and returns incidents as they
/// complete. Mirrors `EvidenceExtractor`: a call is classified when it opens,
/// so only enums, dates and one in-memory fingerprint wait for the result.
struct ClaudeIncidentExtractor: IncidentExtractor {
    /// The two verified user-refusal prefixes. The rest of `neverRan` are tool
    /// errors and interruptions, not denials.
    private static let deniedPrefixes = ["The user doesn't want to", "Permission for this action"]
    /// Result prefixes for a call that never started: no finding, of any kind.
    private static let neverStarted = [
        "The user doesn't want to",
        "Permission to use",
        "Permission for this action",
        "Claude requested permissions",
        "Not started:",
        "[Tool call did not complete",
        "<tool_use_error>",
    ]
    private static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
    private static let maxFingerprints = 256
    private static let maxPending = 256
    private static let maxSeen = 1024

    private struct Denial {
        let serial: Int
        let name: String
        let fingerprint: String
        let at: Date
        var stale = false
    }

    private struct Call {
        let name: String
        let at: Date
        let fingerprint: String
        let toolClass: ToolClass?
        let isShell: Bool
        let soleForeground: Bool
        let backgrounded: Bool
        let credential: (kind: IncidentKind, credentialClass: CredentialClass)?
        let forcePush: Bool
        let writeFamily: String?
        var denialSerial: Int?
        var denialAt: Date?
    }

    private var sessionID: String?
    private var cwd: String?
    private var permissionMode: String?
    private var firstStamp: Date?
    private var unrestrictedSeen = false
    private var awaitingUnrestrictedDate = false
    private var dotEnvReported = false
    private var nextSerial = 0
    private var denials: [Denial] = []
    private var pending: [String: Call] = [:]
    private var pendingOrder: [String] = []
    private var seen: Set<String> = []
    private var seenOrder: [String] = []

    // MARK: Fold

    mutating func fold(_ lines: [String]) -> [ExtractedIncident] {
        var out: [ExtractedIncident] = []
        for line in lines {
            guard wantsLine(line), let record = jsonObject(line) else { continue }
            let stamp = (record["timestamp"] as? String).flatMap(parseISODate)
            if firstStamp == nil, let stamp { firstStamp = stamp }
            if sessionID == nil, let id = record["sessionId"] as? String ?? record["session_id"] as? String, !id.isEmpty {
                sessionID = id
            }
            if let path = record["cwd"] as? String, !path.isEmpty { cwd = path }

            // A permission-mode record carries `sessionId` and `permissionMode`
            // but no timestamp; an older shape calls the field `mode`. Other
            // records can carry `permissionMode` with a timestamp.
            if let mode = record["permissionMode"] as? String { permissionMode = mode }
            if record["type"] as? String == "permission-mode", let mode = record["mode"] as? String {
                permissionMode = mode
            }

            if awaitingUnrestrictedDate, let firstStamp {
                awaitingUnrestrictedDate = false
                out += unrestricted(at: firstStamp)
            }
            if permissionMode == "bypassPermissions", !unrestrictedSeen {
                if let at = stamp ?? firstStamp {
                    out += unrestricted(at: at)
                } else {
                    awaitingUnrestrictedDate = true
                }
            }

            if let error = record["error"] as? String, error == "authentication_failed",
               record["isApiErrorMessage"] as? Bool == true,
               let uuid = record["uuid"] as? String, !uuid.isEmpty, !seen.contains(uuid) {
                rememberSeen(uuid)
                if let at = stamp ?? firstStamp {
                    out += emit(.authFailure, .authError, .transcriptRecord,
                                at: at, completedAt: at, anchor: uuid)
                }
            }

            // A human-authored user record between a denial and a retry marks
            // every waiting denial stale: the retry would then have been asked
            // for and allowed, which is what the guidance says.
            if !denials.isEmpty, Self.isHumanAuthored(record) {
                for index in denials.indices { denials[index].stale = true }
            }

            guard let blocks = (record["message"] as? [String: Any])?["content"] as? [[String: Any]] else {
                continue
            }
            for block in blocks {
                switch block["type"] as? String {
                case "tool_use": open(block, at: stamp)
                case "tool_result": out += close(block, at: stamp)
                default: continue
                }
            }
        }
        return out
    }

    /// The raw-byte pre-filter. A result is parsed only when it carries a
    /// denial prefix or answers a call that is waiting.
    private func wantsLine(_ line: String) -> Bool {
        // The fallback date for a timestamp-less `permission-mode` record is
        // the first timestamped record in the file, which need not be one of
        // the lines the rules read.
        if firstStamp == nil || awaitingUnrestrictedDate, lineContains(line, "\"timestamp\"") { return true }
        if lineContains(line, "\"tool_use\"") { return true }
        if lineContains(line, "permissionMode") || lineContains(line, "\"permission-mode\"") { return true }
        if lineContains(line, "isApiErrorMessage") { return true }
        if !denials.isEmpty, lineContains(line, "\"user\"") { return true }
        if lineContains(line, "\"tool_result\"") {
            if Self.deniedPrefixes.contains(where: { lineContains(line, $0) }) { return true }
            if !pending.isEmpty, answersPendingCall(line) { return true }
        }
        return false
    }

    /// Reads each `tool_use_id` straight out of the bytes. Searching a long
    /// line once per waiting call was most of the replay's cost.
    private func answersPendingCall(_ line: String) -> Bool {
        var line = line
        let needle = Array("\"tool_use_id\":".utf8)
        return line.withUTF8 { bytes in
            guard let base = bytes.baseAddress else { return false }
            var offset = 0
            while offset < bytes.count,
                  let hit = memmem(base + offset, bytes.count - offset, needle, needle.count) {
                var index = UnsafeRawPointer(hit) - UnsafeRawPointer(base) + needle.count
                while index < bytes.count, bytes[index] == UInt8(ascii: " ") { index += 1 }
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                    offset = index
                    continue
                }
                let start = index + 1
                var end = start
                while end < bytes.count, bytes[end] != UInt8(ascii: "\"") { end += 1 }
                if pending[String(decoding: bytes[start..<end], as: UTF8.self)] != nil { return true }
                offset = end
            }
            return false
        }
    }

    // MARK: Calls

    private mutating func open(_ block: [String: Any], at stamp: Date?) {
        guard let id = block["id"] as? String, !id.isEmpty, let at = stamp,
              !seen.contains(id),
              let name = block["name"] as? String,
              let input = block["input"] as? [String: Any]
        else { return }
        rememberSeen(id)
        let fingerprint = Self.fingerprint(name: name, input: input)
        var denialSerial: Int?
        var denialAt: Date?
        if let match = denials.last(where: { !$0.stale && $0.name == name && $0.fingerprint == fingerprint }) {
            denialSerial = match.serial
            denialAt = match.at
        }
        pending[id] = classify(
            name: name, input: input, at: at, fingerprint: fingerprint,
            denialSerial: denialSerial, denialAt: denialAt)
        pendingOrder.append(id)
        while pendingOrder.count > Self.maxPending {
            let evicted = pendingOrder.removeFirst()
            pending.removeValue(forKey: evicted)
        }
    }

    private func classify(
        name: String, input: [String: Any], at: Date, fingerprint: String,
        denialSerial: Int?, denialAt: Date?
    ) -> Call {
        var toolClass: ToolClass?
        var isShell = false
        var soleForeground = false
        let backgrounded = input["run_in_background"] as? Bool == true
        var credential: (kind: IncidentKind, credentialClass: CredentialClass)?
        var forcePush = false
        var writeFamily: String?

        switch name {
        case "Bash":
            toolClass = .bash
            isShell = true
            if let script = input["command"] as? String {
                let (commands, sole) = CommandClassifier.simpleCommands(in: script)
                soleForeground = sole
                credential = credentialFinding(in: commands, cwd: cwd)
                forcePush = commands.contains(where: isForcePush)
            }
        case "Read":
            toolClass = .read
            if let path = input["file_path"] as? String {
                credential = credentialFinding(atPath: path)
            }
        default:
            if Self.editTools.contains(name) {
                toolClass = name == "Write" ? .write : .edit
                let path = (input["file_path"] ?? input["notebook_path"]) as? String
                if let path { writeFamily = self.outsideWriteFamily(path) }
            }
        }

        return Call(
            name: name, at: at, fingerprint: fingerprint, toolClass: toolClass, isShell: isShell,
            soleForeground: soleForeground, backgrounded: backgrounded, credential: credential,
            forcePush: forcePush, writeFamily: writeFamily,
            denialSerial: denialSerial, denialAt: denialAt)
    }

    private mutating func close(_ block: [String: Any], at stamp: Date?) -> [ExtractedIncident] {
        guard let id = block["tool_use_id"] as? String,
              let call = pending.removeValue(forKey: id)
        else { return [] }
        if let index = pendingOrder.firstIndex(of: id) { pendingOrder.remove(at: index) }

        let text = Self.text(of: block["content"])
        let isError = block["is_error"] as? Bool ?? false
        if isError, Self.neverStarted.contains(where: text.hasPrefix) {
            if Self.deniedPrefixes.contains(where: text.hasPrefix) { rememberDenial(call) }
            return []
        }

        let completedAt = stamp ?? call.at
        let evidence = shellEvidence(call, isError: isError, finished: Self.finished(text))
        var out: [ExtractedIncident] = []

        if let serial = call.denialSerial, !isError,
           let index = denials.firstIndex(where: { $0.serial == serial }) {
            let denial = denials.remove(at: index)
            out += emit(.deniedCallRanLater, .tool(call.toolClass ?? .other), .toolResult,
                        at: call.denialAt ?? denial.at, completedAt: completedAt, anchor: id)
        }
        if let credential = call.credential {
            if credential.kind == .workspaceSecretFileNamed {
                if !dotEnvReported {
                    dotEnvReported = true
                    out += emit(credential.kind, .credential(credential.credentialClass), evidence,
                                at: call.at, completedAt: completedAt, anchor: "session-dotenv")
                }
            } else {
                out += emit(credential.kind, .credential(credential.credentialClass), evidence,
                            at: call.at, completedAt: completedAt, anchor: id)
            }
        }
        if call.forcePush {
            out += emit(.forcePushAttempt, .tool(.bash), evidence,
                        at: call.at, completedAt: completedAt, anchor: id)
        }
        if let family = call.writeFamily, !isError, let toolClass = call.toolClass {
            out += emit(.writeToPathOutsideWorkspace, .tool(toolClass), .toolResult,
                        at: call.at, completedAt: completedAt, anchor: family)
        }
        return out
    }

    // MARK: Findings from one call

    private func credentialFinding(in commands: [[String]], cwd: String?) -> (kind: IncidentKind, credentialClass: CredentialClass)? {
        guard let cwd else { return nil }
        for command in commands {
            guard let hit = CredentialTable.firstMatch(in: command, cwd: cwd) else { continue }
            return credentialFinding(hit)
        }
        return nil
    }

    private func credentialFinding(atPath path: String) -> (kind: IncidentKind, credentialClass: CredentialClass)? {
        guard cwd != nil, let resolved = IncidentPaths.absolute(path, cwd: cwd),
              let credentialClass = CredentialTable.credentialClass(ofResolved: resolved)
        else { return nil }
        return credentialFinding(CredentialTable.Hit(credentialClass: credentialClass, path: resolved))
    }

    private func credentialFinding(_ hit: CredentialTable.Hit) -> (kind: IncidentKind, credentialClass: CredentialClass) {
        let inside = hit.credentialClass == .dotEnv && isInsideWorkspace(hit.path)
        return (inside ? .workspaceSecretFileNamed : .credentialReadAttempt, hit.credentialClass)
    }

    private func isInsideWorkspace(_ path: String?) -> Bool {
        guard let path, let cwd, let root = IncidentPaths.absolute(cwd, cwd: nil) else { return false }
        return IncidentPaths.isWithin(path, root: root)
    }

    /// Nil when the path is inside the workspace or otherwise not a finding.
    private func outsideWriteFamily(_ path: String) -> String? {
        guard let cwd, let root = IncidentPaths.absolute(cwd, cwd: nil),
              let resolved = IncidentPaths.absolute(path, cwd: cwd)
        else { return nil }
        if IncidentPaths.isWithin(resolved, root: root) { return nil }
        if IncidentPaths.isScratch(resolved) { return nil }
        if IncidentPaths.isAgentState(resolved) { return nil }
        return IncidentPaths.writeFamily(of: resolved, workspace: root)
    }

    private static func basename(_ word: String) -> String {
        word.split(separator: "/").last.map(String.init) ?? word
    }

    // MARK: Bounds

    private mutating func rememberSeen(_ id: String) {
        seen.insert(id)
        seenOrder.append(id)
        while seenOrder.count > Self.maxSeen {
            seen.remove(seenOrder.removeFirst())
        }
    }

    private mutating func rememberDenial(_ call: Call) {
        guard !denials.contains(where: { $0.name == call.name && $0.fingerprint == call.fingerprint }) else {
            return
        }
        nextSerial += 1
        denials.append(Denial(
            serial: nextSerial, name: call.name, fingerprint: call.fingerprint, at: call.at))
        if denials.count > Self.maxFingerprints { denials.removeFirst() }
    }

    // MARK: Emission

    private var posture: SessionPosture {
        if permissionMode == "bypassPermissions" { return .claudeBypassPermissions }
        if permissionMode != nil { return .approvalsOn }
        return .unknown
    }

    private mutating func unrestricted(at date: Date) -> [ExtractedIncident] {
        guard !unrestrictedSeen else { return [] }
        unrestrictedSeen = true
        return emit(.unrestrictedSession, .posture(.claudeBypassPermissions), .transcriptRecord,
                    at: date, completedAt: date, anchor: "session")
    }

    /// `toolResult` for a non-shell call, or a sole foreground shell command
    /// that exited 0; `commandLine` for anything else.
    private func shellEvidence(_ call: Call, isError: Bool, finished: Bool) -> FindingEvidence {
        if !call.isShell { return .toolResult }
        return call.soleForeground && !call.backgrounded && !isError && finished
            ? .toolResult : .commandLine
    }

    /// A result that says the command was backgrounded does not prove it
    /// finished, even when the tool call itself returned cleanly.
    private static func finished(_ text: String) -> Bool {
        if text.hasPrefix("Command running in background") { return false }
        if text.hasPrefix("Command was manually backgrounded") { return false }
        if text.contains("Command was moved to the background") { return false }
        return true
    }

    private func emit(
        _ kind: IncidentKind, _ detail: IncidentDetail, _ evidence: FindingEvidence,
        at: Date, completedAt: Date, anchor: String
    ) -> [ExtractedIncident] {
        guard let session = sessionID, !session.isEmpty else { return [] }
        return [ExtractedIncident(
            incident: Incident(
                id: IncidentID(agent: .claudeCode, session: session, kind: kind, anchor: anchor),
                kind: kind, agent: .claudeCode, evidence: evidence,
                at: at, completedAt: completedAt, posture: posture, detail: detail),
            rawSessionID: session)]
    }

    // MARK: Transcript helpers

    /// A person's message: not injected, not a subagent's prompt, and not a
    /// record that only carries tool results.
    private static func isHumanAuthored(_ record: [String: Any]) -> Bool {
        guard record["type"] as? String == "user",
              record["isMeta"] as? Bool != true,
              record["isSidechain"] as? Bool != true
        else { return false }
        switch (record["message"] as? [String: Any])?["content"] {
        case is String: return true
        case let blocks as [[String: Any]]: return blocks.contains { $0["type"] as? String == "text" }
        default: return false
        }
    }

    private static func text(of content: Any?) -> String {
        switch content {
        case let string as String: return string
        case let blocks as [[String: Any]]: return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        default: return ""
        }
    }

    /// The canonical input, hashed so the input itself is dropped with the
    /// call. Sorted keys make two identical inputs hash the same.
    private static func fingerprint(name: String, input: [String: Any]) -> String {
        let canonical = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
        let material = name + "\u{0}" + canonical
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Codex

/// Folds one Codex rollout, in order. The store keeps no denial or auth event,
/// so only the workspace, the posture and the shell and file rules apply.
struct CodexIncidentExtractor: IncidentExtractor {
    private var sessionID: String?
    private var cwd: String?
    private var roots: [String] = []
    private var sandbox = ""
    private var approval = ""
    private var unrestrictedSeen = false
    private var dotEnvReported = false

    mutating func fold(_ lines: [String]) -> [ExtractedIncident] {
        var out: [ExtractedIncident] = []
        for line in lines {
            guard lineContains(line, "\"session_meta\"")
                    || lineContains(line, "\"turn_context\"")
                    || lineContains(line, "\"item_completed\""),
                  let record = jsonObject(line),
                  let type = record["type"] as? String,
                  let payload = record["payload"] as? [String: Any]
            else { continue }
            let stamp = (record["timestamp"] as? String).flatMap(parseISODate)
            switch type {
            case "session_meta":
                if sessionID == nil,
                   let id = payload["session_id"] as? String ?? payload["id"] as? String, !id.isEmpty {
                    sessionID = id
                }
                if cwd == nil, let path = payload["cwd"] as? String, !path.isEmpty { cwd = path }
            case "turn_context":
                if let path = payload["cwd"] as? String, !path.isEmpty { cwd = path }
                if let values = payload["workspace_roots"] as? [String], !values.isEmpty { roots = values }
                if let policy = payload["sandbox_policy"] as? [String: Any],
                   let kind = policy["type"] as? String {
                    sandbox = kind
                }
                if let policy = payload["approval_policy"] as? String { approval = policy }
                if sandbox == "danger-full-access", !unrestrictedSeen, let stamp {
                    unrestrictedSeen = true
                    out += emit(.unrestrictedSession, .posture(.codexDangerFullAccess), .transcriptRecord,
                                at: stamp, completedAt: stamp, anchor: "session")
                }
            case "event_msg":
                guard payload["type"] as? String == "item_completed",
                      let item = payload["item"] as? [String: Any]
                else { continue }
                out += incidents(for: item, at: stamp)
            default:
                continue
            }
        }
        return out
    }

    // MARK: Items

    private mutating func incidents(for item: [String: Any], at stamp: Date?) -> [ExtractedIncident] {
        guard let id = item["id"] as? String, !id.isEmpty, let stamp else { return [] }
        switch item["type"] as? String {
        case "CommandExecution": return command(item, id: id, at: stamp)
        case "FileChange": return change(item, id: id, at: stamp)
        default: return []
        }
    }

    private mutating func command(_ item: [String: Any], id: String, at stamp: Date) -> [ExtractedIncident] {
        guard ["completed", "failed"].contains(item["status"] as? String ?? ""),
              let argv = item["command"] as? [String], !argv.isEmpty
        else { return [] }
        let script = argv.count >= 3 && ["-lc", "-c"].contains(argv[1]) ? argv[2] : argv.joined(separator: " ")
        let (commands, soleForeground) = CommandClassifier.simpleCommands(in: script)
        let exit = (item["exit_code"] as? NSNumber)?.intValue
        let duration = item["duration"] as? [String: Any]
        let seconds = Double(jsonInt(duration?["secs"])) + Double(jsonInt(duration?["nanos"])) / 1e9
        let at = stamp.addingTimeInterval(-seconds)
        let evidence: FindingEvidence = soleForeground && exit == 0 ? .toolResult : .commandLine

        var out: [ExtractedIncident] = []
        if let credential = credentialFinding(in: commands) {
            if credential.kind == .workspaceSecretFileNamed {
                if !dotEnvReported {
                    dotEnvReported = true
                    out += emit(credential.kind, .credential(credential.credentialClass), evidence,
                                at: at, completedAt: stamp, anchor: "session-dotenv")
                }
            } else {
                out += emit(credential.kind, .credential(credential.credentialClass), evidence,
                            at: at, completedAt: stamp, anchor: id)
            }
        }
        if commands.contains(where: isForcePush) {
            out += emit(.forcePushAttempt, .tool(.bash), evidence,
                        at: at, completedAt: stamp, anchor: id)
        }
        return out
    }

    private func change(_ item: [String: Any], id: String, at stamp: Date) -> [ExtractedIncident] {
        guard item["status"] as? String == "completed",
              let changes = item["changes"] as? [String: Any]
        else { return [] }
        for key in changes.keys {
            guard let path = IncidentPaths.absolute(key, cwd: cwd),
                  isOutsideWorkspace(path), let root = workspaceRoots.first
            else { continue }
            return emit(.writeToPathOutsideWorkspace, .tool(.fileChange), .toolResult,
                        at: stamp, completedAt: stamp,
                        anchor: IncidentPaths.writeFamily(of: path, workspace: root))
        }
        return []
    }

    private func credentialFinding(in commands: [[String]]) -> (kind: IncidentKind, credentialClass: CredentialClass)? {
        for command in commands {
            guard let hit = CredentialTable.firstMatch(in: command, cwd: cwd) else { continue }
            let inside = hit.credentialClass == .dotEnv && isInsideWorkspace(hit.path)
            return (inside ? .workspaceSecretFileNamed : .credentialReadAttempt, hit.credentialClass)
        }
        return nil
    }

    private func isInsideWorkspace(_ path: String?) -> Bool {
        guard let path else { return false }
        return workspaceRoots.contains { IncidentPaths.isWithin(path, root: $0) }
    }

    private func isOutsideWorkspace(_ path: String) -> Bool {
        let workspace = workspaceRoots
        guard !workspace.isEmpty else { return false }
        if workspace.contains(where: { IncidentPaths.isWithin(path, root: $0) }) { return false }
        if IncidentPaths.isScratch(path) { return false }
        if IncidentPaths.isAgentState(path) { return false }
        return true
    }

    /// The turn's workspace: the `turn_context` `cwd` plus its
    /// `workspace_roots`, both resolved against the current `cwd`.
    private var workspaceRoots: [String] {
        var values: [String] = []
        if let cwd, let root = IncidentPaths.absolute(cwd, cwd: nil) { values.append(root) }
        for root in roots {
            if let resolved = IncidentPaths.absolute(root, cwd: cwd), !values.contains(resolved) {
                values.append(resolved)
            }
        }
        return values
    }

    // MARK: Emission

    private var posture: SessionPosture {
        if sandbox == "danger-full-access" { return .codexDangerFullAccess }
        if !sandbox.isEmpty { return .sandboxed }
        if !approval.isEmpty { return .approvalsOn }
        return .unknown
    }

    private func emit(
        _ kind: IncidentKind, _ detail: IncidentDetail, _ evidence: FindingEvidence,
        at: Date, completedAt: Date, anchor: String
    ) -> [ExtractedIncident] {
        guard let session = sessionID, !session.isEmpty else { return [] }
        return [ExtractedIncident(
            incident: Incident(
                id: IncidentID(agent: .codex, session: session, kind: kind, anchor: anchor),
                kind: kind, agent: .codex, evidence: evidence,
                at: at, completedAt: completedAt, posture: posture, detail: detail),
            rawSessionID: session)]
    }
}
