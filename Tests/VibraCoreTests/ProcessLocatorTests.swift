import Foundation
import Testing
@testable import VibraCore

/// Jump-back is only safe if the session→process link is exact. A wrong jump
/// silently moves the user's focus away from what they were doing, which is
/// worse than not jumping at all.
struct ProcessLocatorTests {

    private func makeTree(
        claude: [String: String] = [:],
        codexLocks: [String] = []
    ) throws -> (root: URL, claudeDir: URL, codexDir: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vibra-locate-\(UUID().uuidString)")
        let claudeDir = root.appendingPathComponent("sessions")
        let codexDir = root.appendingPathComponent("locks")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        for (name, body) in claude {
            try body.write(to: claudeDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        for name in codexLocks {
            try "".write(to: codexDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return (root, claudeDir, codexDir)
    }

    // MARK: - Secrets

    /// `~/.claude/sessions` holds `<pid>.<hash>.key` files beside the JSON.
    /// Those are secrets. Same class of hazard as the auth tokens in the
    /// OpenCode database, and held to the same standard.
    @Test func keyFilesAreNeverOpened() throws {
        let canary = "VIBRA_KEY_CANARY_MUST_NOT_LEAK"
        let tree = try makeTree(claude: [
            "4242.json": #"{"pid":4242,"sessionId":"sess-a","cwd":"/tmp"}"#,
            "4242.abcdef.key": canary,
        ])
        defer { try? FileManager.default.removeItem(at: tree.root) }

        let locator = ProcessLocator(claudeSessionsDir: tree.claudeDir, codexLocksDir: tree.codexDir)

        // The enumeration must not even list the key file.
        let listed = locator.claudeSessionFiles().map(\.lastPathComponent)
        #expect(listed == ["4242.json"], "only .json may be enumerated, got \(listed)")

        // And nothing derived from it may carry the canary.
        let found = locator.locate(sessionID: "sess-a", agent: .claudeCode)
        let rendered = "\(String(describing: found))\(listed)"
        #expect(!rendered.contains(canary), "key contents must never reach any output")
    }

    // MARK: - Exactness

    @Test func unknownSessionIsNotLocated() throws {
        let tree = try makeTree(claude: [
            "4242.json": #"{"pid":4242,"sessionId":"sess-a","cwd":"/tmp"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: tree.root) }
        let locator = ProcessLocator(claudeSessionsDir: tree.claudeDir, codexLocksDir: tree.codexDir)
        #expect(locator.locate(sessionID: "sess-does-not-exist", agent: .claudeCode) == nil)
    }

    @Test func deadProcessIsNotOffered() throws {
        // pid 999999 is above the default macOS pid ceiling, so it cannot be
        // alive. A stale session file must not produce a jump target.
        let tree = try makeTree(claude: [
            "999999.json": #"{"pid":999999,"sessionId":"sess-dead","cwd":"/tmp"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: tree.root) }
        let locator = ProcessLocator(claudeSessionsDir: tree.claudeDir, codexLocksDir: tree.codexDir)
        #expect(locator.locate(sessionID: "sess-dead", agent: .claudeCode) == nil)
    }

    @Test func openCodeIsNeverLocated() throws {
        // OpenCode publishes no session→process link. Returning nil is the
        // correct answer; guessing from cwd would be wrong, because two agents
        // routinely share a directory.
        let tree = try makeTree()
        defer { try? FileManager.default.removeItem(at: tree.root) }
        let locator = ProcessLocator(claudeSessionsDir: tree.claudeDir, codexLocksDir: tree.codexDir)
        #expect(locator.locate(sessionID: "anything", agent: .openCode) == nil)
    }

    @Test func codexWithoutALockIsNotLocated() throws {
        let tree = try makeTree(codexLocks: ["other-session.lock"])
        defer { try? FileManager.default.removeItem(at: tree.root) }
        let locator = ProcessLocator(claudeSessionsDir: tree.claudeDir, codexLocksDir: tree.codexDir)
        #expect(locator.locate(sessionID: "sess-x", agent: .codex) == nil)
    }

    @Test func missingDirectoriesAreNotAnError() {
        let locator = ProcessLocator(
            claudeSessionsDir: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"),
            codexLocksDir: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        )
        #expect(locator.locate(sessionID: "x", agent: .claudeCode) == nil)
        #expect(locator.locate(sessionID: "x", agent: .codex) == nil)
    }

    // MARK: - TTY normalization

    @Test func ttyNormalizationMatchesEmulatorForm() {
        // `ps` reports "ttys001"; iTerm and Terminal report "/dev/ttys001".
        // They must compare equal or every jump silently fails.
        #expect(ProcessInspector.normalizeTTY("/dev/ttys001") == "ttys001")
        #expect(ProcessInspector.normalizeTTY("ttys001") == "ttys001")
        #expect(ProcessInspector.normalizeTTY(" /dev/ttys012 \n") == "ttys012")
    }

    @Test func currentProcessIsAliveAndBogusPidIsNot() {
        #expect(ProcessInspector.isAlive(ProcessInfo.processInfo.processIdentifier))
        #expect(!ProcessInspector.isAlive(999_999))
        #expect(!ProcessInspector.isAlive(0))
        #expect(!ProcessInspector.isAlive(-1))
    }

    // MARK: - TTY ownership
    //
    // vibra used to report every failed jump as "probably a multiplexer".
    // On a plain iTerm2 tab that is false, and it sent the user looking for a
    // tmux problem they did not have. These pin the walk itself; which owner a
    // developer's own shell reports is environment-dependent and deliberately
    // not asserted.

    @Test func launchdHasNoTerminalInItsAncestry() {
        // pid 1 is launchd: no shell, no emulator, no multiplexer above it.
        // If the walk ever claims otherwise it is matching on something far too
        // loose.
        #expect(ProcessInspector.ttyOwner(of: 1) == .unknown)
    }

    @Test func aDeadPidYieldsUnknownRatherThanAGuess() {
        // ps prints nothing for a pid that does not exist. The walk must end,
        // not fall through to a default that names a terminal.
        #expect(ProcessInspector.ttyOwner(of: 999_999) == .unknown)
    }

    @Test func ownershipWalkTerminatesOnEveryLivePID() {
        // The bound exists so a cyclic or corrupt parent chain cannot spin.
        // Walking a handful of real processes exercises it against whatever
        // this machine actually has running.
        for pid in [Int32(1), ProcessInfo.processInfo.processIdentifier] {
            let owner = ProcessInspector.ttyOwner(of: pid)
            // Any answer is acceptable; not returning is not.
            #expect(owner == owner)
        }
    }
}
