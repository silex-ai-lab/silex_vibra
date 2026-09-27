import Foundation

/// Tasks and timeline for the one selected question, read on demand from its
/// transcript. Never stored: built for the current selection, replaced by the
/// next, released when the window closes. Caps bound it no matter what the
/// file holds — this is the bounded-memory answer to `the reference dashboard`'s
/// question → tasks → timeline structure.
public struct HistoryDetail: Sendable, Equatable {
    /// One todo item, as the last `TodoWrite` inside the slice saw it.
    public struct Task: Sendable, Equatable {
        public enum Status: String, Sendable {
            case pending, inProgress = "in_progress", completed, unknown = "unknown"
        }
        public let text: String
        public let status: Status
    }

    /// One tool call: when, and what it was called — never its arguments,
    /// which can carry secrets, never its result.
    public struct Event: Sendable, Equatable {
        public let at: Date
        public let name: String
    }

    public let tasks: [Task]
    public let timeline: [Event]
    public let tasksTruncated: Bool
    public let timelineTruncated: Bool
    /// Bytes the extraction read, so tests can assert the read happened here
    /// and only on selection — the contract `HistoryIngest.lastBytesRead`
    /// already sets.
    public let bytesRead: Int

    public static let maxTasks = 12
    public static let maxEvents = 60

    /// Claude Code only for now: its transcripts carry `TodoWrite` in a shape
    /// worth reading. Other agents' sections stay hidden until their formats
    /// are proven on real data — this plan does not guess.
    public static func supports(agent: AgentKind) -> Bool { agent == .claudeCode }

    /// Extracts the slice `[from, to)` of one transcript. `to == nil` means
    /// to the end of the file. Returns nil when there is no file to read —
    /// callers hide their sections, never show an error for a vanished path.
    public static func extract(path: String, from: Date, to: Date?) -> HistoryDetail? {
        guard path.hasSuffix(".jsonl"), FileManager.default.fileExists(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        let reader = IncrementalLineReader()
        var bytes = 0
        var tasks: [Task] = []
        var timeline: [Event] = []
        var tasksTruncated = false
        var timelineTruncated = false
        var offset: UInt64 = 0

        while true {
            guard let batch = try? reader.read(url: url, from: offset) else { break }
            bytes += batch.bytesRead
            let advanced = batch.nextOffset > offset
            offset = batch.nextOffset
            if batch.lines.isEmpty && !advanced { break }
            autoreleasepool {
                for line in batch.lines {
                    guard let record = jsonObject(line),
                          let stamp = (record["timestamp"] as? String).flatMap(parseISODate),
                          stamp >= from, !(to.map { stamp >= $0 } ?? false),
                          let message = record["message"] as? [String: Any],
                          let blocks = message["content"] as? [[String: Any]]
                    else { continue }
                    for block in blocks {
                        guard block["type"] as? String == "tool_use",
                              let name = block["name"] as? String, !name.isEmpty else { continue }
                        if name == "TodoWrite",
                           let input = block["input"] as? [String: Any],
                           let todos = input["todos"] as? [[String: Any]] {
                            // The last list inside the slice wins: it is the
                            // state under this question, not a history of
                            // rewrites.
                            var parsed: [Task] = []
                            for todo in todos {
                                guard let text = todo["content"] as? String,
                                      !text.trimmingCharacters(in: .whitespaces).isEmpty
                                else { continue }
                                let raw = todo["status"] as? String ?? ""
                                parsed.append(Task(text: text, status: Task.Status(rawValue: raw) ?? .unknown))
                            }
                            if parsed.count > Self.maxTasks {
                                tasks = Array(parsed.prefix(Self.maxTasks))
                                tasksTruncated = true
                            } else {
                                tasks = parsed
                            }
                        }
                        if timeline.count < Self.maxEvents {
                            timeline.append(Event(at: stamp, name: name))
                        } else {
                            timelineTruncated = true
                        }
                    }
                }
            }
            if !advanced { break }
        }
        return HistoryDetail(
            tasks: tasks, timeline: timeline,
            tasksTruncated: tasksTruncated, timelineTruncated: timelineTruncated,
            bytesRead: bytes)
    }
}
