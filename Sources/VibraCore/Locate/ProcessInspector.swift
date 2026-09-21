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
