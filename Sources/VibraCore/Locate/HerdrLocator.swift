import Foundation

/// One row of the process table: enough to walk ancestry and recognise herdr.
public struct ProcessEntry: Equatable, Sendable {
    public let pid: Int32
    public let ppid: Int32
    /// Normalized ("ttys001"), nil for a process with no controlling terminal.
    public let tty: String?
    /// Full command line as `ps -o args=` prints it.
    public let args: String

    public init(pid: Int32, ppid: Int32, tty: String?, args: String) {
        self.pid = pid
        self.ppid = ppid
        self.tty = tty
        self.args = args
    }
}

/// Where a session sits inside herdr, established from process ancestry.
public struct HerdrRoute: Equatable, Sendable {
    /// The herdr server the session descends from.
    public let serverPID: Int32
    /// Named herdr session, or nil for the default one.
    public let session: String?
    /// The pane's shell: the ancestor whose parent is the server. herdr reports
    /// it per pane as `shell_pid`, which is what makes the pane match exact.
    public let paneShellPID: Int32
    /// The server's own executable, when its command line gives a full path.
    public let executable: String?
}

/// Resolves a process inside herdr to its pane, and finds the terminal windows
/// showing that herdr session.
///
/// Exact at every link, like the rest of jump-back: the pane is the one whose
/// `shell_pid` is the session's ancestor directly below the herdr server, never
/// one guessed from a working directory or a title. Pure functions over a
/// process table and herdr's JSON, so every rule is testable without a live
/// herdr.
public enum HerdrLocator {

    /// Parses `ps -axo pid=,ppid=,tty=,args=`.
    public static func parseProcessTable(_ output: String) -> [Int32: ProcessEntry] {
        var table: [Int32: ProcessEntry] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int32(fields[0]), let ppid = Int32(fields[1])
            else { continue }
            let rawTTY = String(fields[2])
            let tty = (rawTTY == "??" || rawTTY == "?") ? nil : ProcessInspector.normalizeTTY(rawTTY)
            let args = fields[3].trimmingCharacters(in: .whitespaces)
            table[pid] = ProcessEntry(pid: pid, ppid: ppid, tty: tty, args: args)
        }
        return table
    }

    /// Walks up from `pid` to the herdr server it runs under.
    ///
    /// Bounded, like `ProcessInspector.ttyOwner`: a corrupt or cyclic parent
    /// chain must not spin.
    public static func route(from pid: Int32, in table: [Int32: ProcessEntry]) -> HerdrRoute? {
        var child: Int32?
        var current = pid
        for _ in 0..<32 {
            guard let entry = table[current] else { return nil }
            let tokens = tokenize(entry.args)
            if isHerdr(tokens), isServer(tokens) {
                // The session process itself being the server is not a pane.
                guard let shell = child else { return nil }
                let exe = tokens.first.flatMap { $0.hasPrefix("/") ? $0 : nil }
                return HerdrRoute(
                    serverPID: entry.pid,
                    session: sessionName(tokens),
                    paneShellPID: shell,
                    executable: exe
                )
            }
            guard entry.ppid > 1 else { return nil }
            child = current
            current = entry.ppid
        }
        return nil
    }

    /// Controlling terminals of the herdr clients attached to `session`.
    ///
    /// A client is an interactive `herdr` - bare, `--session <name>`, or
    /// `session attach <name>` - with a terminal. One-shot CLI calls such as
    /// `herdr pane list` are not clients, and neither is the server.
    public static func clientTTYs(of session: String?, in table: [Int32: ProcessEntry]) -> [String] {
        table.values
            .sorted { $0.pid > $1.pid } // newest first: most likely the one in use
            .compactMap { entry -> String? in
                guard let tty = entry.tty else { return nil }
                let tokens = tokenize(entry.args)
                guard isHerdr(tokens), !isServer(tokens) else { return nil }
                let rest = strippingSessionFlag(Array(tokens.dropFirst()))
                let attached: String?
                if rest.isEmpty {
                    attached = sessionName(tokens)
                } else if rest.count == 3, rest[0] == "session", rest[1] == "attach" {
                    attached = rest[2] == "default" ? nil : rest[2]
                } else {
                    return nil
                }
                return attached == session ? tty : nil
            }
    }

    // MARK: - herdr JSON

    /// (pane_id, tab_id) of every pane in `herdr pane list` output.
    public static func parsePaneList(_ data: Data) -> [(paneID: String, tabID: String)] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? [String: Any],
              let panes = result["panes"] as? [[String: Any]]
        else { return [] }
        return panes.compactMap { pane in
            guard let paneID = pane["pane_id"] as? String,
                  let tabID = pane["tab_id"] as? String
            else { return nil }
            return (paneID, tabID)
        }
    }

    /// `shell_pid` from `herdr pane process-info` output.
    public static func parseShellPID(_ data: Data) -> Int32? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? [String: Any],
              let info = result["process_info"] as? [String: Any],
              let pid = info["shell_pid"] as? NSNumber
        else { return nil }
        return pid.int32Value
    }

    // MARK: - Command lines

    static func tokenize(_ args: String) -> [String] {
        args.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    static func isHerdr(_ tokens: [String]) -> Bool {
        guard let first = tokens.first else { return false }
        return (first as NSString).lastPathComponent == "herdr"
    }

    /// `herdr server` or `herdr --session x server`. Not `herdr server stop`,
    /// which is a one-shot request to a server, not one.
    static func isServer(_ tokens: [String]) -> Bool {
        strippingSessionFlag(Array(tokens.dropFirst())) == ["server"]
    }

    static func sessionName(_ tokens: [String]) -> String? {
        guard let i = tokens.firstIndex(of: "--session"), i + 1 < tokens.count else { return nil }
        let name = tokens[i + 1]
        return name == "default" ? nil : name
    }

    private static func strippingSessionFlag(_ tokens: [String]) -> [String] {
        var out: [String] = []
        var skipNext = false
        for token in tokens {
            if skipNext { skipNext = false; continue }
            if token == "--session" { skipNext = true; continue }
            out.append(token)
        }
        return out
    }
}
