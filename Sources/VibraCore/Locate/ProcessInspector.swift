import Foundation

/// Small, read-only queries about live processes.
///
/// Shells out to `ps` and `lsof` rather than using libproc. These run only on
/// an explicit user action — clicking a session row — never on the polling
/// path, so the subprocess cost is irrelevant and the clarity is worth more.
public enum ProcessInspector {

    /// True if a process with this pid currently exists.
    ///
    /// `kill(pid, 0)` tests existence without delivering a signal. EPERM means
    /// the process exists but belongs to someone else, which still counts.
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Controlling terminal of a process, normalized to "ttys001" form.
    /// Nil when the process has no controlling terminal — a GUI helper, say,
    /// which cannot be jumped to.
    public static func tty(of pid: Int32) -> String? {
        guard let out = run("/bin/ps", ["-o", "tty=", "-p", "\(pid)"]) else { return nil }
        let value = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "??", value != "?" else { return nil }
        return normalizeTTY(value)
    }

    /// What is sitting between a session's process and the window server.
    ///
    /// Answers "is this tty really inside a multiplexer?" instead of assuming
    /// it. vibra used to report every failed jump as a multiplexer pane, which
    /// on a plain iTerm2 tab is simply false and sends people looking in the
    /// wrong place.
    public enum TTYOwner: Equatable, Sendable {
        /// A terminal emulator holds it; a failed jump is vibra's problem.
        case emulator(String)
        /// tmux, screen or herdr holds it; its panes are invisible to the emulator.
        case multiplexer(String)
        /// Nothing recognisable in the ancestry.
        case unknown
    }

    /// Walks a process's ancestors and reports the first thing that explains
    /// who owns its terminal.
    ///
    /// Bounded: a corrupt or cyclic parent chain must not spin. Sixteen levels
    /// is far past any real shell nesting.
    public static func ttyOwner(of pid: Int32) -> TTYOwner {
        var current = pid
        for _ in 0..<16 {
            guard let out = run("/bin/ps", ["-o", "ppid=,comm=", "-p", "\(current)"]) else {
                return .unknown
            }
            let parts = out.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let ppid = Int32(parts[0]) else { return .unknown }

            // Match on the executable's basename: `ps -o comm=` prints a full
            // path for a bundled app ("/Applications/iTerm.app/.../iTerm2").
            let name = (String(parts[1]) as NSString).lastPathComponent.lowercased()

            if let mux = ["tmux", "tmux: server", "screen", "herdr"]
                .first(where: { name.contains($0) }) {
                return .multiplexer(mux)
            }
            if name.contains("iterm") { return .emulator("iTerm2") }
            if name.contains("terminal") { return .emulator("Terminal") }
            if name.contains("ghostty") { return .emulator("Ghostty") }
            if name.contains("alacritty") { return .emulator("Alacritty") }
            if name.contains("wezterm") { return .emulator("WezTerm") }
            if name.contains("kitty") { return .emulator("kitty") }

            guard ppid > 1 else { return .unknown }
            current = ppid
        }
        return .unknown
    }

    /// Pid holding `url` open. Used for Codex, which keeps an open lock named
    /// after its session id.
    public static func holderOfOpenFile(_ url: URL) -> Int32? {
        guard let out = run(lsofPath, ["-t", url.path]) else { return nil }
        // lsof -t prints one pid per line; take the first live one.
        for line in out.split(separator: "\n") {
            if let pid = Int32(line.trimmingCharacters(in: .whitespaces)), isAlive(pid) {
                return pid
            }
        }
        return nil
    }

    /// The whole process table, for walking ancestry in one read rather than
    /// one `ps` per level. Empty if `ps` cannot be run.
    public static func processTable() -> [Int32: ProcessEntry] {
        guard let out = run("/bin/ps", ["-axo", "pid=,ppid=,tty=,args="]) else { return [:] }
        return HerdrLocator.parseProcessTable(out)
    }

    /// "/dev/ttys001" and "ttys001" both normalize to "ttys001", so a tty from
    /// `ps` compares equal to one reported by a terminal emulator.
    public static func normalizeTTY(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("/dev/") { value.removeFirst("/dev/".count) }
        return value
    }

    /// lsof ships at /usr/sbin on macOS, but /usr/bin on some systems and in
    /// some Homebrew setups. Resolve rather than hardcode: an absent binary
    /// silently made every Codex session unlocatable.
    private static let lsofPath: String = {
        for candidate in ["/usr/sbin/lsof", "/usr/bin/lsof", "/opt/homebrew/bin/lsof"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return "/usr/sbin/lsof"
    }()

    private static func run(_ path: String, _ args: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
