import Foundation
import Testing
@testable import VibraCore

/// Agent transcripts are written by a live process, so vibra reads files that
/// may be empty, half-written, or outright corrupt. None of that may produce a
/// bogus row or a crash.
struct MalformedInputTests {

    private func makeTree(_ files: [String: String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vibra-malformed-\(UUID().uuidString)")
        let proj = root.appendingPathComponent("-fake-proj")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        for (name, body) in files {
            try body.write(to: proj.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func emptyAndCorruptFilesProduceNoSessions() throws {
        let root = try makeTree([
            "empty.jsonl": "",
            "garbage.jsonl": "not json at all\n{\"type\":\n",
            "blanklines.jsonl": "\n\n\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = try ClaudeCodeAdapter(projectsRoot: root).discoverSessions()
        #expect(sessions.isEmpty, "unparseable files must not yield phantom sessions")
    }

    @Test func tornFinalLineIsIgnoredButValidRecordsSurvive() throws {
        // Second line is cut mid-write, exactly as a live appender leaves it.
        let body = """
        {"type":"assistant","sessionId":"torn-1","timestamp":"2026-09-19T10:00:00.000Z","cwd":"/fake/proj","message":{"model":"claude-opus-5","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        {"type":"assistant","sessionId":"torn-1","timestamp":"2026-09-19T10:00
        """
        let root = try makeTree(["torn.jsonl": body])
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = try ClaudeCodeAdapter(projectsRoot: root).discoverSessions()
        #expect(sessions.count == 1)
        let s = try #require(sessions.first)
        #expect(s.usage.input == 1)
        #expect(s.usage.output == 2)
        #expect(s.cwd == "/fake/proj")
        #expect(s.lastEvent == .turnComplete)
    }

    @Test func missingDirectoryIsNotAnError() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/vibra/\(UUID().uuidString)")
        let adapter = ClaudeCodeAdapter(projectsRoot: missing)
        #expect(adapter.discoverSessionsSafely().isEmpty)
    }
}
