import Foundation

/// Where a session is actually running.
public struct SessionProcess: Equatable, Sendable {
    public let sessionID: String
    public let pid: Int32
    /// Controlling terminal device, e.g. "ttys001". Nil for a process with no
    /// controlling tty, which cannot be jumped to.
    public let tty: String?
    public let cwd: String?
    /// The Claude desktop app's own id for this session (`local_...`), when
    /// the desktop app started it - a scheduled task or a Code tab. Such a
    /// session has no terminal at all; the desktop app is where it lives.
    public let desktopSessionID: String?

    public init(
        sessionID: String,
        pid: Int32,
        tty: String?,
        cwd: String? = nil,
        desktopSessionID: String? = nil
    ) {
        self.sessionID = sessionID
        self.pid = pid
        self.tty = tty
        self.cwd = cwd
        self.desktopSessionID = desktopSessionID
    }
}

/// Resolves a session id to the live process running it.
///
/// Deliberately exact, never heuristic. Both review seats assumed this would
/// need cwd plus start-time matching, because a working directory does not
/// identify a session — on this machine a Codex and an OpenCode session
/// occupied the same directory simultaneously. It turns out two of the three
/// agents publish the link themselves:
///
/// - Claude Code writes `~/.claude/sessions/<pid>.json` containing both its
///   pid and its sessionId.
/// - Codex holds an open lock at
///   `~/.codex/thread-writer-locks/<sessionId>.lock`, so the holder's pid is
///   discoverable.
///
/// OpenCode publishes no such link, so it is simply not locatable in v1 —
/// which is correct behaviour: no jump beats a wrong jump.
public struct ProcessLocator: Sendable {
    private let claudeSessionsDir: URL
    private let codexLocksDir: URL

    public init(
        claudeSessionsDir: URL = VibraPaths.home.appendingPathComponent(".claude/sessions"),
        codexLocksDir: URL = VibraPaths.home.appendingPathComponent(".codex/thread-writer-locks")
    ) {
        self.claudeSessionsDir = claudeSessionsDir
        self.codexLocksDir = codexLocksDir
    }

    public func locate(sessionID: String, agent: AgentKind) -> SessionProcess? {
        switch agent {
        case .claudeCode: return locateClaude(sessionID: sessionID)
        case .codex: return locateCodex(sessionID: sessionID)
        case .openCode: return nil
        }
    }

    // MARK: - Liveness

    /// Which of `candidates` still have a running process, for the agents
    /// that publish a session->process link. Nil for an agent that publishes
    /// none (OpenCode): not knowing is not the same as knowing it exited.
    ///
    /// Claude Code is one directory read for all candidates. Codex is one
    /// `lsof` per candidate, because its lock file outlives the process and
    /// only an open handle proves it is still running.
    public func liveSessionIDs(agent: AgentKind, candidates: [String]) -> Set<String>? {
        switch agent {
        case .claudeCode:
            var live = Set<String>()
            for url in claudeSessionFiles() {
                guard let data = try? Data(contentsOf: url),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = obj["sessionId"] as? String,
                      let pid = (obj["pid"] as? NSNumber)?.int32Value,
                      ProcessInspector.isAlive(pid)
                else { continue }
                live.insert(id)
            }
            return live
        case .codex:
            return Set(candidates.filter { locateCodex(sessionID: $0) != nil })
        case .openCode:
            return nil
        }
    }

    // MARK: - Claude Code

    /// Reads only `*.json`. The same directory holds `<pid>.<hash>.key` files,
    /// which are secrets: they are never opened, and a test asserts it.
    func claudeSessionFiles() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: claudeSessionsDir,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.pathExtension == "json" }
    }

    private func locateClaude(sessionID: String) -> SessionProcess? {
        for url in claudeSessionFiles() {
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let recordedID = obj["sessionId"] as? String,
                  recordedID == sessionID,
                  let pid = (obj["pid"] as? NSNumber)?.int32Value
            else { continue }

            // A recorded pid may belong to an exited process whose file was
            // never cleaned up, so confirm it is alive before offering a jump.
            guard ProcessInspector.isAlive(pid) else { continue }
            return SessionProcess(
                sessionID: sessionID,
                pid: pid,
                tty: ProcessInspector.tty(of: pid),
                cwd: obj["cwd"] as? String,
                desktopSessionID: desktopSessionID(in: obj)
            )
        }
        return nil
    }

    /// `hostSessionId` of a session the desktop app started. Held to the same
    /// shape the desktop app's own deep-link handler accepts, so nothing else
    /// from the file can end up in a URL Vibra opens.
    func desktopSessionID(in record: [String: Any]) -> String? {
        guard record["entrypoint"] as? String == "claude-desktop",
              let id = record["hostSessionId"] as? String,
              id.range(of: #"^local_[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil
        else { return nil }
        return id
    }

    // MARK: - Codex

    private func locateCodex(sessionID: String) -> SessionProcess? {
        let lock = codexLocksDir.appendingPathComponent("\(sessionID).lock")
        guard FileManager.default.fileExists(atPath: lock.path) else { return nil }
        guard let pid = ProcessInspector.holderOfOpenFile(lock) else { return nil }
        return SessionProcess(
            sessionID: sessionID,
            pid: pid,
            tty: ProcessInspector.tty(of: pid),
            cwd: nil
        )
    }
}
