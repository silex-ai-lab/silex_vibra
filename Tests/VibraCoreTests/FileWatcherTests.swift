import CoreServices
import Foundation
import Testing
@testable import VibraCore

/// Thread-safe collector for `FileWatcher`'s callbacks, which arrive on the
/// watcher's own queue.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [[URL]] = []

    func add(_ urls: [URL]) {
        lock.lock()
        events.append(urls)
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.count
    }

    var all: [[URL]] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0

    func increment() {
        lock.lock()
        n += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return n
    }
}

/// Polls instead of sleeping for a fixed time, so a slow machine costs seconds
/// of budget rather than a flaky failure.
private func waitForEvents(
    _ log: EventLog,
    moreThan count: Int,
    timeout: TimeInterval = 15
) async -> Int {
    let deadline = Date().addingTimeInterval(timeout)
    while log.count <= count, Date() < deadline {
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return log.count
}

private func waitFor(timeout: TimeInterval = 15, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return condition()
}

/// A real, startable stream that delivers nothing: enough to exercise the arm
/// path after a forced failure without depending on filesystem events.
private func inertStream(for roots: [URL]) -> FSEventStreamRef? {
    var context = FSEventStreamContext(
        version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
    let callback: FSEventStreamCallback = { _, _, _, _, _, _ in }
    return FSEventStreamCreate(
        kCFAllocatorDefault,
        callback,
        &context,
        roots.map(\.path) as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.25,
        FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
    )
}

struct FileWatcherTests {
    private func scratchFile() throws -> URL {
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.jsonl")
    }

    private func scratchDirectory() throws -> URL {
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func append(_ data: Data, to url: URL) throws {
        let existing = (try? Data(contentsOf: url)) ?? Data()
        var combined = existing
        combined.append(data)
        try combined.write(to: url)
    }

    @Test func tornLineIsBufferedUntilCompleted() throws {
        let file = try scratchFile()

        // First write is a torn partial line with no newline. The parser must
        // hold it back, never emit it as a (malformed) record.
        try Data(#"{"type":"assistant""#.utf8).write(to: file)

        var reader = JSONLIncrementalReader()
        #expect(try reader.readRecords(from: file).isEmpty)

        // A later read completes the line. The parser must emit exactly one
        // record, the now-complete JSON object.
        try append(Data(#","value":42}"#.utf8 + [0x0A]), to: file)

        let records = try reader.readRecords(from: file)
        #expect(records.count == 1)
        #expect(String(decoding: records[0], as: UTF8.self) == #"{"type":"assistant","value":42}"#)
    }

    @Test func incrementalReadDoesNotReEmitOldRecords() throws {
        let file = try scratchFile()
        try Data("a\nb\n".utf8).write(to: file)

        var reader = JSONLIncrementalReader()
        #expect(try reader.readRecords(from: file).count == 2)

        // Append one more record: only it should be emitted.
        try append(Data("c\n".utf8), to: file)
        let records = try reader.readRecords(from: file)
        #expect(records.count == 1)
        #expect(String(decoding: records[0], as: UTF8.self) == "c")
    }

    @Test func truncationResetsOffset() throws {
        let file = try scratchFile()
        try Data("line1\nline2\n".utf8).write(to: file)

        var reader = JSONLIncrementalReader()
        #expect(try reader.readRecords(from: file).count == 2)

        // Simulate the file being truncated/rewritten: size goes backwards.
        try Data("fresh\n".utf8).write(to: file)

        let records = try reader.readRecords(from: file)
        #expect(records.count == 1)
        #expect(String(decoding: records[0], as: UTF8.self) == "fresh")
    }

    @Test func pollIgnoresSHMButSeesWAL() throws {
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("state.db")
        try Data("main".utf8).write(to: dbURL)

        let before = try #require(FileWatcher.pollSignature(of: dbURL))
        try Data(count: 32768).write(to: dir.appendingPathComponent("state.db-shm"))
        #expect(FileWatcher.pollSignature(of: dbURL) == before)

        try Data("wal".utf8).write(to: dir.appendingPathComponent("state.db-wal"))
        #expect(FileWatcher.pollSignature(of: dbURL) != before)
    }

    @Test func shmOnlyEventsDoNotFire() {
        final class Box: @unchecked Sendable { var calls: [[URL]] = [] }
        let box = Box()
        let watcher = FileWatcher(watchedDirectories: []) { box.calls.append($0) }

        let shm = URL(fileURLWithPath: "/tmp/x/state.vscdb-shm")
        let wal = URL(fileURLWithPath: "/tmp/x/state.vscdb-wal")
        watcher.handleEvents(paths: [shm], mustRescan: false)
        #expect(box.calls.isEmpty)

        watcher.handleEvents(paths: [shm, wal], mustRescan: false)
        #expect(box.calls == [[wal]])
    }

    @Test func rootCreatedAfterStartIsArmedAndFiresForLaterWrites() async throws {
        let base = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent(".claude/projects")
        let log = EventLog()
        let watcher = FileWatcher(watchedDirectories: [root]) { log.add($0) }
        watcher.start()
        defer { watcher.stop() }

        let initial = await waitForEvents(log, moreThan: 0)
        #expect(initial >= 1, "start must publish the initial rescan")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let armed = await waitForEvents(log, moreThan: initial)
        #expect(armed > initial, "a root created after start must be armed and fire")

        let file = root.appendingPathComponent("session.jsonl")
        try Data("one\n".utf8).write(to: file)
        let firstWrite = await waitForEvents(log, moreThan: armed)
        #expect(firstWrite > armed, "the first write into the newly armed root must fire")

        try append(Data("two\n".utf8), to: file)
        let secondWrite = await waitForEvents(log, moreThan: firstWrite)
        #expect(secondWrite > firstWrite, "a later append must fire")
    }

    @Test func rootVanishAndReappearStillFiresForLaterWrites() async throws {
        let base = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent(".claude/projects")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let log = EventLog()
        let watcher = FileWatcher(watchedDirectories: [root]) { log.add($0) }
        watcher.start()
        defer { watcher.stop() }

        // The initial rescan, then the arm of the root that already exists.
        let armed = await waitForEvents(log, moreThan: 1)
        #expect(armed >= 2, "start must rescan and arm an existing root")

        try FileManager.default.removeItem(at: root)
        let vanished = await waitForEvents(log, moreThan: armed)
        #expect(vanished > armed, "a vanished root must fire")

        // FSEvents keeps reporting for a path that still exists, so the
        // teardown is checked on the armed set rather than on the next event.
        let disarmed = await waitFor { watcher.armedIdentity(of: root.path) == nil }
        #expect(disarmed, "a vanished root must be torn down")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let reappeared = await waitForEvents(log, moreThan: vanished)
        #expect(reappeared > vanished, "a reappearing root must re-arm and fire")

        let newIdentity = try #require(FileWatcher.RootIdentity.describing(root))
        let rearmed = await waitFor { watcher.armedIdentity(of: root.path) == newIdentity }
        #expect(rearmed, "a reappearing root must be armed on its new identity")

        let file = root.appendingPathComponent("session.jsonl")
        try Data("one\n".utf8).write(to: file)
        let write = await waitForEvents(log, moreThan: reappeared)
        #expect(write > reappeared, "a write after the root reappears must fire")
    }

    @Test func rootReplacedBetweenTicksRearmsAndFires() async throws {
        let base = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent(".claude/projects")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let log = EventLog()
        let watcher = FileWatcher(watchedDirectories: [root]) { log.add($0) }
        watcher.start()
        defer { watcher.stop() }
        let armed = await waitForEvents(log, moreThan: 1)
        #expect(armed >= 2)

        let oldIdentity = try #require(watcher.armedIdentity(of: root.path))

        // Same path, new directory: the stream must be re-armed on the new
        // identity even though the path never disappeared between two ticks.
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let newIdentity = try #require(FileWatcher.RootIdentity.describing(root))
        #expect(newIdentity != oldIdentity, "a recreated directory must have a new identity")

        let rearmed = await waitFor(timeout: 15) {
            watcher.armedIdentity(of: root.path) == newIdentity
        }
        #expect(rearmed, "a root replaced between ticks must be re-armed on the new identity")

        let settled = log.count
        let file = root.appendingPathComponent("session.jsonl")
        try Data("one\n".utf8).write(to: file)
        let write = await waitForEvents(log, moreThan: settled)
        #expect(write > settled, "a write into a replaced root must fire")
    }

    @Test func databaseAppearingAndDisappearingFires() throws {
        let base = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let db = base.appendingPathComponent("opencode.db")
        let log = EventLog()
        let watcher = FileWatcher(watchedDirectories: [], pollURLs: [db]) { log.add($0) }

        watcher.pollOnce(db)
        #expect(log.count == 0, "the first poll only seeds")

        try Data("db".utf8).write(to: db)
        watcher.pollOnce(db)
        #expect(log.all == [[db]], "a database appearing must fire")

        watcher.pollOnce(db)
        #expect(log.count == 1, "an unchanged database stays quiet")

        try FileManager.default.removeItem(at: db)
        watcher.pollOnce(db)
        #expect(log.count == 2, "a database disappearing must fire")
    }

    @Test func failedArmRetriesOnALaterTick() async throws {
        let base = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent(".claude/projects")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let log = EventLog()
        let attempts = Counter()
        let watcher = FileWatcher(
            watchedDirectories: [root],
            createStream: { roots in
                attempts.increment()
                return attempts.value == 1 ? nil : inertStream(for: roots)
            }
        ) { log.add($0) }
        watcher.start()
        defer { watcher.stop() }

        let fired = await waitForEvents(log, moreThan: 1)
        #expect(attempts.value >= 2, "a failed arm must be retried on a later tick")
        #expect(fired > 1, "the retry must arm the root and fire")
    }
}
