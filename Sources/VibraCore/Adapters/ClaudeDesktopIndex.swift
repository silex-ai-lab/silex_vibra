import Foundation

/// What the Claude desktop app knows about one of its Code sessions.
public struct DesktopSessionInfo: Equatable, Sendable {
    /// The desktop app's own id (`local_...`), which its deep link accepts.
    public let localID: String
    /// The title shown in the Claude UI sidebar, when it has one.
    public let title: String?
    /// Archived in the Claude UI: the user put it away, so Vibra does too.
    public let isArchived: Bool

    public init(localID: String, title: String?, isArchived: Bool) {
        self.localID = localID
        self.title = title
        self.isArchived = isArchived
    }
}

/// Live state Claude Code publishes for a running session in
/// `~/.claude/sessions/<pid>.json`: `busy`, `idle`, or `waiting` (with
/// `waitingFor`, e.g. "permission prompt"). Exact where the transcript can only
/// be inferred from - a permission prompt writes nothing to the transcript.
public struct ClaudeLiveStatus: Equatable, Sendable {
    public let status: String?
    public let waitingFor: String?

    public init(status: String?, waitingFor: String?) {
        self.status = status
        self.waitingFor = waitingFor
    }
}

/// Reads the Claude desktop app's per-session metadata:
/// `~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_<id>.json`.
///
/// Each file links the desktop session to the Claude Code transcript Vibra
/// already reads (`cliSessionId`), and carries the sidebar title and whether
/// it is archived. That is what lets a Claude UI session stay listed after the
/// desktop app parks its process - it is still open in the app and resumable -
/// and be opened there with no process at all.
///
/// Only those four fields are kept. The files also hold MCP server configs and
/// prompt snapshots, which are never retained or surfaced.
public final class ClaudeDesktopIndex: @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    /// path -> (modification date, parsed entry). A file is re-parsed only when
    /// it changes: they are large, and a refresh runs on every transcript write.
    private var cache: [String: (Date, (String, DesktopSessionInfo)?)] = [:]

    public init(root: URL = VibraPaths.home
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")) {
        self.root = root
    }

    /// Every desktop session, keyed by its Claude Code session id.
    public func load() -> [String: DesktopSessionInfo] {
        let files = sessionFiles()
        lock.lock()
        defer { lock.unlock() }

        var seen = Set<String>()
        var result: [String: DesktopSessionInfo] = [:]
        for url in files {
            let path = url.path
            seen.insert(path)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let entry: (String, DesktopSessionInfo)?
            if let cached = cache[path], cached.0 == modified {
                entry = cached.1
            } else {
                entry = (try? Data(contentsOf: url)).flatMap(Self.parse)
                cache[path] = (modified, entry)
            }
            if let (cliID, info) = entry { result[cliID] = info }
        }
        for path in cache.keys where !seen.contains(path) { cache.removeValue(forKey: path) }
        return result
    }

    /// Two levels down (account, then organization), `local_*.json` only.
    private func sessionFiles() -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for account in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for org in (try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? [] {
                for file in (try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: nil)) ?? []
                where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                    out.append(file)
                }
            }
        }
        return out
    }

    /// (cliSessionId, info) from one metadata file, or nil if it is not one.
    /// The local id is held to the shape the desktop app's deep link accepts.
    public static func parse(_ data: Data) -> (String, DesktopSessionInfo)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cliID = obj["cliSessionId"] as? String, !cliID.isEmpty,
              let localID = obj["sessionId"] as? String,
              localID.range(of: #"^local_[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil
        else { return nil }
        let title = (obj["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cliID, DesktopSessionInfo(
            localID: localID,
            title: (title?.isEmpty ?? true) ? nil : title,
            isArchived: obj["isArchived"] as? Bool ?? false
        ))
    }
}
