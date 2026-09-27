import Foundation
import Testing
@testable import VibraCore

/// `HistoryDetail` — the on-demand tasks/timeline reader for the selected
/// question: slice boundaries, last-`TodoWrite`-wins, both caps, and the
/// "no file, no error" contract.
struct HistoryDetailTests {
    private var base: Date { Date(timeIntervalSince1970: 1_790_000_000) }

    private func tempFile(_ lines: [String]) throws -> URL {
        let dir = testScratchDirectory().appendingPathComponent("detail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("s.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func toolLine(_ name: String, at seconds: Double, input: [String: Any] = [:]) -> String {
        let record: [String: Any] = [
            "type": "assistant", "sessionId": "c-1",
            "timestamp": ISO8601DateFormatter().string(from: base.addingTimeInterval(seconds)),
            "message": ["role": "assistant", "content": [
                ["type": "tool_use", "name": name, "input": input],
            ]],
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: record), as: UTF8.self)
    }

    private func todoLine(_ todos: [[String: Any]], at seconds: Double) -> String {
        toolLine("TodoWrite", at: seconds, input: ["todos": todos])
    }

    private func todo(_ content: String, _ status: String) -> [String: Any] {
        ["content": content, "status": status]
    }

    @Test func extractsOnlyTheRequestedSlice() throws {
        let url = try tempFile([
            todoLine([todo("first", "pending"), todo("second", "completed")], at: 10),
            toolLine("Edit", at: 20),
            toolLine("Bash", at: 100),  // after the slice
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let detail = try #require(HistoryDetail.extract(
            path: url.path, from: base, to: base.addingTimeInterval(30)))
        #expect(detail.tasks == [
            HistoryDetail.Task(text: "first", status: .pending),
            HistoryDetail.Task(text: "second", status: .completed),
        ])
        #expect(detail.timeline.map(\.name) == ["TodoWrite", "Edit"])
        #expect(!detail.tasksTruncated && !detail.timelineTruncated)
        #expect(detail.bytesRead > 0)
    }

    /// The last `TodoWrite` inside the slice is the state under the question;
    /// earlier rewrites are not history.
    @Test func lastTodoWriteWins() throws {
        let url = try tempFile([
            todoLine([todo("old draft", "pending")], at: 10),
            todoLine([todo("real task", "in_progress")], at: 20),
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let detail = try #require(HistoryDetail.extract(
            path: url.path, from: base, to: base.addingTimeInterval(60)))
        #expect(detail.tasks == [HistoryDetail.Task(text: "real task", status: .inProgress)])
    }

    @Test func capsBoundBothSections() throws {
        let lines = (0..<70).map { toolLine("Tool\($0)", at: Double($0)) }
        let bigTodos = (0..<20).map { todo("task \($0)", "pending") }
        let url = try tempFile([todoLine(bigTodos, at: 5)] + lines)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let detail = try #require(HistoryDetail.extract(
            path: url.path, from: base, to: base.addingTimeInterval(1000)))
        #expect(detail.tasks.count == HistoryDetail.maxTasks)
        #expect(detail.tasksTruncated)
        #expect(detail.timeline.count == HistoryDetail.maxEvents)
        #expect(detail.timelineTruncated)
    }

    @Test func emptySliceReadsButExtractsNothing() throws {
        let url = try tempFile([toolLine("Bash", at: 10)])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let detail = try #require(HistoryDetail.extract(
            path: url.path, from: base.addingTimeInterval(1_000), to: nil))
        #expect(detail.tasks.isEmpty)
        #expect(detail.timeline.isEmpty)
        #expect(detail.bytesRead > 0)  // the read happened, here, not at open
    }

    @Test func missingOrNonJsonlPathReturnsNil() {
        #expect(HistoryDetail.extract(path: "/nonexistent/s.jsonl", from: base, to: nil) == nil)
        #expect(HistoryDetail.extract(path: "/tmp/s.txt", from: base, to: nil) == nil)
    }

    @Test func onlyClaudeCodeIsSupported() {
        #expect(HistoryDetail.supports(agent: .claudeCode))
        #expect(!HistoryDetail.supports(agent: .codex))
        #expect(!HistoryDetail.supports(agent: .hermes))
    }
}
