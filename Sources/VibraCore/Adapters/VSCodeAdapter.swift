import Foundation

/// Reads GitHub Copilot Chat sessions (Ask, Edit and Agent mode) from Visual
/// Studio Code and VS Code Insiders.
///
/// VS Code keeps one file per chat session, as an append-only mutation log:
/// - `<User>/workspaceStorage/<id>/chatSessions/<session>.jsonl` for a chat in
///   a window with a folder or workspace open, and
/// - `<User>/globalStorage/emptyWindowChatSessions/<session>.jsonl` for a chat
///   in an empty window.
///
/// Each line is one entry (VS Code's `ObjectMutationLog`): `kind` 0 is a full
/// snapshot `v`; 1 sets the value at key path `k` to `v`; 2 truncates the
/// array at `k` to `i` (when given) and then appends `v`; 3 deletes `k`. VS
/// Code rewrites the file as a single snapshot when the log grows, which the
/// ingest layer sees as a truncated file and restarts from byte zero.
///
/// Replaying the log for real would mean holding every response in memory.
/// The adapter instead replays it onto a reduced state that keeps only what a
/// session row needs - title, folder, and per request its timestamps, model,
/// token counts and `modelState` - and drops every mutation below those. Message
/// text and response bodies are parsed only to be discarded, never kept.
///
/// `modelState.value` is VS Code's own verdict on the latest reply, so nothing
/// has to be inferred from timing: 0 in progress, 1 complete, 2 cancelled,
/// 3 failed, 4 waiting on a confirmation (a tool or terminal command to approve).
public struct VSCodeAdapter: AgentAdapter {
    public let kind: AgentKind = .vsCode

    private let userDirectories: [URL]

    /// `userDirectories` are VS Code `User` directories - one per edition.
    public init(userDirectories: [URL] = VibraPaths.vsCodeUserDirectories) {
        self.userDirectories = userDirectories
    }

    public var isAvailable: Bool {
        userDirectories.contains { dir in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    // MARK: - Incremental ingest

    public func sources() throws -> [SourceDescriptor] {
        chatSessionFiles().compactMap { SourceDescriptor.describing($0) }
    }

    public func update(
        source: SourceDescriptor,
        input: SourceInput,
        previous: ParsedState?
    ) throws -> ParsedState {
        guard case .records(let lines, let reset) = input else {
            return ParsedState(sessions: try discoverSessions(), checkpoint: nil)
        }
        var checkpoint: VSCodeChatCheckpoint
        if !reset, let carried = previous?.checkpoint as? VSCodeChatCheckpoint {
            checkpoint = carried
        } else {
            checkpoint = VSCodeChatCheckpoint()
        }
        for line in lines { checkpoint.fold(line) }

        let session = checkpoint.buildSession(
            fileURL: source.url,
            fileModified: source.modified,
            fallbackCwd: Self.workspaceFolder(forSessionFile: source.url),
            edition: Self.edition(ofSessionFile: source.url)
        )
        return ParsedState(sessions: session.map { [$0] } ?? [], checkpoint: checkpoint)
    }

    // MARK: - Full parse

    public func discoverSessions() throws -> [Session] {
        var sessions: [Session] = []
        for file in chatSessionFiles() {
            var checkpoint = VSCodeChatCheckpoint()
            var offset: UInt64 = 0
            let reader = IncrementalLineReader()
            while let result = try? reader.read(url: file, from: offset), result.nextOffset > offset {
                for line in result.lines { checkpoint.fold(line) }
                offset = result.nextOffset
            }
            let session = checkpoint.buildSession(
                fileURL: file,
                fileModified: fileModificationDate(file) ?? Date(timeIntervalSince1970: 0),
                fallbackCwd: Self.workspaceFolder(forSessionFile: file),
                edition: Self.edition(ofSessionFile: file)
            )
            if let session { sessions.append(session) }
        }
        return sessions.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: - Files

    private func chatSessionFiles() -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        for user in userDirectories {
            let empty = user.appendingPathComponent("globalStorage/emptyWindowChatSessions")
            files += jsonlChildren(of: empty)
            let workspaces = user.appendingPathComponent("workspaceStorage")
            for workspace in (try? fm.contentsOfDirectory(at: workspaces, includingPropertiesForKeys: nil)) ?? [] {
                files += jsonlChildren(of: workspace.appendingPathComponent("chatSessions"))
            }
        }
        return files
    }

    private func jsonlChildren(of dir: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return children.filter { $0.pathExtension == "jsonl" }
    }

    /// The folder of the window a chat belongs to, from the `workspace.json`
    /// VS Code keeps beside `chatSessions/`: `folder` for a single folder,
    /// `workspace` for a `.code-workspace` file (its directory is used).
    static func workspaceFolder(forSessionFile file: URL) -> String? {
        let storage = file.deletingLastPathComponent()
        guard storage.lastPathComponent == "chatSessions" else { return nil }
        let manifest = storage.deletingLastPathComponent().appendingPathComponent("workspace.json")
        guard let data = try? Data(contentsOf: manifest),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        if let folder = obj["folder"] as? String { return filePath(fromURI: folder) }
        if let workspace = obj["workspace"] as? String {
            return filePath(fromURI: workspace).map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        }
        return nil
    }

    /// "vscode" or "vscode-insiders", from which `User` directory the file is
    /// under. Recorded as the session's entrypoint so a click opens the
    /// edition the chat lives in.
    static func edition(ofSessionFile file: URL) -> String {
        file.path.contains("/Code - Insiders/User/") ? "vscode-insiders" : "vscode"
    }
}

/// A local `file://` URI as a path, or nil for anything else (a remote or
/// virtual workspace has no folder on this machine).
func filePath(fromURI uri: String) -> String? {
    guard let url = URL(string: uri), url.isFileURL else { return nil }
    return url.path
}

/// The reduced replay state of one VS Code chat session log.
struct VSCodeChatCheckpoint: AdapterCheckpoint {
    struct Request: Equatable {
        var timestampMS: Int?
        var responseTimestampMS: Int?
        var modelState: Int?
        var completedAtMS: Int?
        var modelID: String?
        var promptTokens = 0
        var completionTokens = 0

        init(_ value: Any?) {
            guard let obj = value as? [String: Any] else { return }
            for (key, field) in obj { set(key, field) }
        }

        /// Keeps a request field this adapter reads; ignores the rest.
        mutating func set(_ key: String, _ value: Any?) {
            switch key {
            case "timestamp": timestampMS = optionalInt(value)
            case "responseTimestamp": responseTimestampMS = optionalInt(value)
            case "modelId": modelID = value as? String
            case "promptTokens": promptTokens = jsonInt(value)
            case "completionTokens": completionTokens = jsonInt(value)
            case "modelState":
                let state = value as? [String: Any]
                modelState = optionalInt(state?["value"])
                completedAtMS = optionalInt(state?["completedAt"])
            default: break
            }
        }
    }

    var sessionID: String?
    var creationMS: Int?
    var customTitle: String?
    var workingDirectory: String?
    var requests: [Request] = []

    mutating func fold(_ line: String) {
        guard let entry = jsonObject(line) else { return }
        let path = entry["k"] as? [Any] ?? []
        switch jsonInt(entry["kind"]) {
        case 0:
            self = VSCodeChatCheckpoint()
            for (key, value) in entry["v"] as? [String: Any] ?? [:] { set([key], value) }
        case 1:
            set(path, entry["v"])
        case 2:
            push(path, values: entry["v"] as? [Any] ?? [], truncateTo: optionalInt(entry["i"]))
        case 3:
            set(path, nil)
        default:
            break
        }
    }

    private mutating func set(_ path: [Any], _ value: Any?) {
        guard let head = path.first as? String else { return }
        if path.count == 1 {
            switch head {
            case "sessionId": sessionID = value as? String
            case "creationDate": creationMS = optionalInt(value)
            case "customTitle": customTitle = value as? String
            case "workingDirectory": workingDirectory = value as? String
            case "requests": requests = (value as? [Any] ?? []).map(Request.init)
            default: break
            }
            return
        }
        guard head == "requests", let index = path[1] as? Int, index >= 0 else { return }
        if path.count == 2 {
            if index < requests.count {
                requests[index] = Request(value)
            } else if index == requests.count {
                requests.append(Request(value))
            }
            return
        }
        guard index < requests.count, let field = path[2] as? String else { return }
        if path.count == 3 {
            requests[index].set(field, value)
        } else if field == "modelState", path.count == 4, let sub = path[3] as? String {
            // Defensive: a diff that ever reaches inside modelState.
            if sub == "value" { requests[index].modelState = optionalInt(value) }
            if sub == "completedAt" { requests[index].completedAtMS = optionalInt(value) }
        }
    }

    private mutating func push(_ path: [Any], values: [Any], truncateTo length: Int?) {
        // Only the requests array matters; pushes into a response are content.
        guard path.count == 1, path.first as? String == "requests" else { return }
        if let length, length >= 0, length < requests.count {
            requests.removeLast(requests.count - length)
        }
        requests += values.map(Request.init)
    }

    /// The session row, or nil for a chat nobody has sent anything in - VS Code
    /// itself leaves those out of its session list.
    func buildSession(fileURL: URL, fileModified: Date, fallbackCwd: String?, edition: String) -> Session? {
        guard let last = requests.last else { return nil }

        let lastEvent: LastEventKind
        switch last.modelState {
        case 4: lastEvent = .permissionPrompt
        case 0: lastEvent = .producing
        case 1, 3: lastEvent = .turnComplete
        case 2: lastEvent = .settled
        default:
            // No state recorded yet: the request was just sent.
            lastEvent = last.completedAtMS == nil ? .producing : .turnComplete
        }

        func date(_ ms: Int?) -> Date? { ms.map { Date(timeIntervalSince1970: Double($0) / 1000) } }
        let stamps = requests.flatMap { [$0.timestampMS, $0.responseTimestampMS, $0.completedAtMS] }
            .compactMap(date)
        let started = date(creationMS) ?? stamps.min() ?? fileModified
        let lastActivity = ([fileModified, started] + stamps).max() ?? fileModified

        let usage = TokenUsage(
            input: requests.reduce(0) { $0 + $1.promptTokens },
            output: requests.reduce(0) { $0 + $1.completionTokens }
        )
        let title = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cwd = workingDirectory.flatMap(filePath(fromURI:)) ?? fallbackCwd ?? ""

        return Session(
            id: sessionID ?? fileURL.deletingPathExtension().lastPathComponent,
            agent: .vsCode,
            cwd: cwd,
            model: requests.last(where: { $0.modelID != nil })?.modelID,
            startedAt: started,
            lastActivity: lastActivity,
            usage: usage,
            title: (title?.isEmpty ?? true) ? (cwd.isEmpty ? "Copilot chat" : nil) : title,
            lastEvent: lastEvent,
            entrypoint: edition
        )
    }
}

private func optionalInt(_ value: Any?) -> Int? {
    switch value {
    case let n as Int: return n
    case let n as NSNumber: return n.intValue
    default: return nil
    }
}
