import Foundation
import Testing
@testable import VibraCore

/// An adapter whose availability, listing and sessions a test controls, for the
/// transitions a real agent's files cannot be made to produce on demand.
private final class FakeAdapter: AgentAdapter, @unchecked Sendable {
    let kind: AgentKind
    private let lock = NSLock()
    private var available = false
    private var listThrows = false
    private var source: URL?
    private var sessions: [Session] = []

    init(kind: AgentKind = .hermes) {
        self.kind = kind
    }

    func configure(available: Bool, source: URL? = nil, sessions: [Session] = []) {
        lock.lock()
        self.available = available
        self.source = source
        self.sessions = sessions
        lock.unlock()
    }

    func failListing(_ fail: Bool) {
        lock.lock()
        listThrows = fail
        lock.unlock()
    }

    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return available
    }

    /// Only stats, matching the real adapters' contract.
    func sources() throws -> [SourceDescriptor] {
        lock.lock()
        defer { lock.unlock() }
        if listThrows { throw SourceListError() }
        guard let source, let descriptor = SourceDescriptor.describing(source) else { return [] }
        return [descriptor]
    }

    func discoverSessions() throws -> [Session] {
        lock.lock()
        defer { lock.unlock() }
        return sessions
    }
}

struct IngestHealthTests {
    private func scratchDirectory() throws -> URL {
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A transcript whose last assistant record ends the turn, stamped now so a
    /// session classified from it is inside the activity window.
    private func writeTranscript(
        to url: URL,
        sessionID: String = "health-1",
        stopReason: String = "end_turn"
    ) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date())
        let lines = [
            #"{"type":"user","sessionId":"\#(sessionID)","timestamp":"\#(stamp)","cwd":"/tmp/proj","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"assistant","sessionId":"\#(sessionID)","timestamp":"\#(stamp)","cwd":"/tmp/proj","message":{"model":"m","role":"assistant","stop_reason":"\#(stopReason)","usage":{"input_tokens":10,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func setPermissions(_ mode: Int, on url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    private func openCodeFixture(at db: URL) throws {
        let microseconds = Int(Date().timeIntervalSince1970 * 1000)
        try makeDB(at: db, statements: [
            """
            CREATE TABLE session (id TEXT, directory TEXT, title TEXT, model TEXT,
            tokens_input INT, tokens_output INT, tokens_cache_read INT, tokens_cache_write INT,
            time_created INT, time_updated INT, permission TEXT);
            """,
            """
            INSERT INTO session VALUES ('oc-1','/tmp/oc-proj','title','m',10,5,0,0,\(microseconds),\(microseconds),NULL);
            """,
        ])
    }

    // MARK: - Read failures

    @Test func failedReadStaysFailingUntilASuccessfulReread() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("session.jsonl")
        try writeTranscript(to: file)
        let ingest = SessionIngest(adapters: [ClaudeCodeAdapter(file: file)], horizon: nil)

        let first = await ingest.refresh()
        #expect(first.count == 1)
        guard case .ready(let firstSuccess) = await ingest.health[.claudeCode] else {
            Issue.record("a readable source must be ready")
            return
        }
        #expect(firstSuccess != nil)

        // Append first so the descriptor moves (chmod alone does not), then
        // take the read permission away.
        try append(#"{"type":"user","sessionId":"health-1"}"# + "\n", to: file)
        try setPermissions(0o000, on: file)
        defer { try? setPermissions(0o644, on: file) }

        let failedPass = await ingest.refresh()
        #expect(failedPass.map(\.id) == ["health-1"], "the session must survive the failed read")
        guard case .failing(.readFailed, lastSuccess: let failedSuccess) = await ingest.health[.claudeCode]
        else {
            Issue.record("an unreadable source must report readFailed")
            return
        }
        #expect(failedSuccess == firstSuccess, "the last good read time must survive the failure")

        // Still failing on the next pass: an entry is only written on success,
        // so the stale descriptor keeps the source in the retry path.
        _ = await ingest.refresh()
        guard case .failing(.readFailed, lastSuccess: _) = await ingest.health[.claudeCode] else {
            Issue.record("a failure must stay until the source is read again")
            return
        }

        try setPermissions(0o644, on: file)
        let recovered = await ingest.refresh()
        #expect(recovered.count == 1)
        guard case .ready(let recoveredSuccess) = await ingest.health[.claudeCode] else {
            Issue.record("a successful re-read must clear the failure")
            return
        }
        #expect(recoveredSuccess != nil)
        #expect(recoveredSuccess! > firstSuccess!)
    }

    @Test func deletedFailingSourceReturnsTheAdapterToReady() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // The projects root has to outlive the transcript, or the adapter
        // itself goes absent and the per-source failure is moot.
        let root = dir.appendingPathComponent("projects")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("proj"), withIntermediateDirectories: true)
        let file = root.appendingPathComponent("proj/session.jsonl")
        try writeTranscript(to: file)
        let ingest = SessionIngest(adapters: [ClaudeCodeAdapter(projectsRoot: root)], horizon: nil)

        _ = await ingest.refresh()
        try append(#"{"type":"user","sessionId":"health-1"}"# + "\n", to: file)
        try setPermissions(0o000, on: file)
        _ = await ingest.refresh()
        let beforeDelete = await ingest.health[.claudeCode]
        guard case .failing = beforeDelete else {
            Issue.record("setup: the source must be failing before it is deleted, got \(String(describing: beforeDelete))")
            return
        }

        try FileManager.default.removeItem(at: file)
        let after = await ingest.refresh()
        #expect(after.isEmpty)
        guard case .ready = await ingest.health[.claudeCode] else {
            Issue.record("a deleted source must stop failing, not pin the adapter")
            return
        }
    }

    @Test func databaseFailingAfterASuccessfulReadKeepsItsLastSuccess() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("opencode.db")
        try openCodeFixture(at: db)
        let ingest = SessionIngest(adapters: [OpenCodeAdapter(dbURL: db)], horizon: nil)

        let first = await ingest.refresh()
        #expect(first.map(\.id) == ["oc-1"])
        guard case .ready(let firstSuccess) = await ingest.health[.openCode] else {
            Issue.record("a readable database must be ready")
            return
        }
        let success = try #require(firstSuccess)

        // Moving the file forces a read, and the bytes are no longer a database.
        try Data("not a database".utf8).write(to: db)

        let after = await ingest.refresh()
        #expect(after.map(\.id) == ["oc-1"], "the previous parse is stale, not gone")
        guard case .failing(.readFailed, lastSuccess: let failedSuccess) = await ingest.health[.openCode]
        else {
            Issue.record("an unreadable database must report readFailed")
            return
        }
        #expect(failedSuccess == success, "the database's last good read must not be nil")
    }

    @Test func parseFailureIsReportedSeparatelyFromAReadFailure() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("opencode.db")
        // A readable database with a schema this build does not understand.
        try makeDB(at: db, statements: [
            "CREATE TABLE session (id TEXT, directory TEXT, renamed_model TEXT);",
        ])
        let ingest = SessionIngest(adapters: [OpenCodeAdapter(dbURL: db)], horizon: nil)

        _ = await ingest.refresh()
        guard case .failing(.parseFailed, lastSuccess: let success) = await ingest.health[.openCode]
        else {
            Issue.record("a schema mismatch must report parseFailed")
            return
        }
        #expect(success == nil, "nothing was ever read successfully")
    }

    // MARK: - Listing failures

    @Test func listingFailureIsRecordedAndClearedByTheNextGoodListing() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("session.jsonl")
        try Data("x\n".utf8).write(to: file)
        let at = Date()
        let session = Session(
            id: "fake-1", agent: .hermes, cwd: "/tmp/fake",
            state: .awaitingInput, startedAt: at, lastActivity: at, lastEvent: .turnComplete)
        let adapter = FakeAdapter()
        adapter.configure(available: true, source: file, sessions: [session])
        let ingest = SessionIngest(adapters: [adapter], horizon: nil)

        let good = await ingest.refresh()
        #expect(good.map(\.id) == ["fake-1"])
        guard case .ready(let success) = await ingest.health[.hermes] else {
            Issue.record("a good listing must be ready")
            return
        }

        adapter.failListing(true)
        let failed = await ingest.refresh()
        #expect(failed.map(\.id) == ["fake-1"], "a listing failure keeps the entries it has")
        guard case .failing(.listFailed, lastSuccess: let failedSuccess) = await ingest.health[.hermes]
        else {
            Issue.record("a throwing sources() must report listFailed")
            return
        }
        #expect(failedSuccess == success)

        adapter.failListing(false)
        _ = await ingest.refresh()
        guard case .ready = await ingest.health[.hermes] else {
            Issue.record("the next good listing must clear listFailed")
            return
        }
    }

    @Test func anAdapterBecomingAvailableBetweenRefreshesIsPickedUp() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("session.jsonl")
        try Data("x\n".utf8).write(to: file)
        let at = Date()
        let session = Session(
            id: "late-1", agent: .hermes, cwd: "/tmp/late",
            state: .working, startedAt: at, lastActivity: at, lastEvent: .producing)
        let adapter = FakeAdapter()
        adapter.configure(available: false)
        let ingest = SessionIngest(adapters: [adapter], horizon: nil)

        _ = await ingest.refresh()
        #expect(await ingest.health[.hermes] == .absent)

        adapter.configure(available: true, source: file, sessions: [session])
        let after = await ingest.refresh()
        #expect(after.map(\.id) == ["late-1"])
        guard case .ready = await ingest.health[.hermes] else {
            Issue.record("an adapter that appears must be read on the next refresh")
            return
        }
    }

    // MARK: - Cost and retained output

    @Test func anEmptyListingDoesNotStampSuccessOnEveryPass() async {
        let adapter = FakeAdapter()
        adapter.configure(available: true)
        let ingest = SessionIngest(adapters: [adapter])
        _ = await ingest.refresh()
        let first = await ingest.health
        _ = await ingest.refresh()
        #expect(first[.hermes] == .ready(lastSuccess: nil))
        #expect(await ingest.health == first, "an idle pass must not change health")
    }

    @Test func aFailingSourceStaysFailingPastTheHorizon() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("aged.jsonl")
        try writeTranscript(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

        let adapter = FakeAdapter()
        adapter.configure(available: true, source: file)
        let ingest = SessionIngest(adapters: [adapter], horizon: 3600)
        _ = await ingest.refresh()
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: file.path)
        _ = await ingest.refresh()
        guard case .failing(.readFailed, _)? = await ingest.health[.hermes] else {
            Issue.record("a source past the horizon is still listed and was never re-read")
            return
        }
    }

    @Test func aWarmRefreshReadsZeroBytesAndLeavesHealthAlone() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("session.jsonl")
        try writeTranscript(to: file)
        let db = dir.appendingPathComponent("opencode.db")
        try openCodeFixture(at: db)
        let ingest = SessionIngest(
            adapters: [ClaudeCodeAdapter(file: file), OpenCodeAdapter(dbURL: db)], horizon: nil)

        let first = await ingest.refresh()
        let firstHealth = await ingest.health
        #expect(first.count == 2)

        let second = await ingest.refresh()
        #expect(second == first, "an unchanged refresh must return the same sessions")
        #expect(await ingest.lastRefreshBytesRead == 0, "an unchanged refresh must not read a byte")
        #expect(await ingest.health == firstHealth, "an idle pass must not change health")
    }

    @Test func retainedOutputIsIdenticalAcrossFailingPassesAndNotifiesNothing() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("session.jsonl")
        try writeTranscript(to: file)
        let ingest = SessionIngest(adapters: [ClaudeCodeAdapter(file: file)], horizon: nil)

        _ = await ingest.refresh()
        try append(#"{"type":"user","sessionId":"health-1"}"# + "\n", to: file)
        try setPermissions(0o000, on: file)
        defer { try? setPermissions(0o644, on: file) }

        let first = await ingest.refresh()
        let second = await ingest.refresh()
        #expect(first == second, "a retained source must produce the same sessions every pass")

        // Classify the way the app does, so the retained session really is in
        // an attention state: otherwise the notifier assertions are vacuous.
        let classified = LivePipeline.recent(first, settings: .defaults, now: Date())
        #expect(!classified.isEmpty)
        #expect(classified.allSatisfy { $0.wantsNotification })

        let sink = RecordingNotificationSink()
        AttentionNotifier(sink: sink).notifyIfNeeded(previous: classified, current: classified)
        #expect(sink.delivered.isEmpty, "identical inputs must not re-alert")
        #expect(sink.withdrawn.isEmpty, "identical inputs must not withdraw")
    }
}
