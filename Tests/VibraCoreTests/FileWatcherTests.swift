import Foundation
import Testing
@testable import VibraCore

struct FileWatcherTests {
    private func scratchFile() throws -> URL {
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.jsonl")
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
}
