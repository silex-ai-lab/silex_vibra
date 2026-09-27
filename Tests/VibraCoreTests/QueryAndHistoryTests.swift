import Foundation
import Testing
@testable import VibraCore

struct QueryOutputTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func rows(_ data: Data) throws -> (top: [String: Any], sessions: [[String: Any]]) {
        let top = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (top, try #require(top["sessions"] as? [[String: Any]]))
    }

    private var sample: [Session] {
        var priced = Session(
            id: "s1", agent: .claudeCode, cwd: "/Users/demo/alpha", gitBranch: "main",
            model: "claude-sonnet-4-5", state: .awaitingInput,
            startedAt: now.addingTimeInterval(-600), lastActivity: now.addingTimeInterval(-60),
            usage: TokenUsage(input: 1000, output: 100), title: "Title from a message",
            lastEvent: .turnComplete)
        priced.entrypoint = "cli"
        let unpriced = Session(
            id: "s2", agent: .openCode, cwd: "/Users/demo/beta", model: "some-unknown-model",
            state: .working, startedAt: now, lastActivity: now, lastEvent: .producing)
        return [priced, unpriced]
    }

    @Test func schemaIsStableAndCarriesNoTitle() throws {
        let data = try QueryOutput(sessions: sample, settings: .defaults, now: now).json()
        let (top, sessions) = try rows(data)
        #expect(Set(top.keys) == ["generatedAt", "settings", "sessions"])
        let expected: Set<String> = [
            "agent", "id", "project", "cwd", "gitBranch", "state", "needsAttention", "lastEvent",
            "lastActivity", "startedAt", "model", "tokens", "estimatedCostUSD", "unattended",
        ]
        for row in sessions { #expect(Set(row.keys) == expected) }
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("Title from a message"))
        #expect(!text.contains("\"title\""))
        #expect(text.contains("\"lastActivity\" : \"2026-"))
        let settings = try #require(top["settings"] as? [String: Double])
        #expect(settings["stallThresholdSeconds"] == 300)
    }

    @Test func unknownRateIsNullNotZero() throws {
        let (_, sessions) = try rows(try QueryOutput(sessions: sample, settings: .defaults, now: now).json())
        let unpriced = try #require(sessions.first { $0["id"] as? String == "s2" })
        #expect(unpriced["estimatedCostUSD"] is NSNull)
        #expect(unpriced["gitBranch"] is NSNull)
        let priced = try #require(sessions.first { $0["id"] as? String == "s1" })
        #expect((priced["estimatedCostUSD"] as? Double ?? 0) > 0)
    }

    @Test func attentionAndAgentFilters() throws {
        let attention = try rows(try QueryOutput(
            sessions: sample, settings: .defaults, now: now, attentionOnly: true).json()).sessions
        #expect(attention.map { $0["id"] as? String } == ["s1"])
        #expect(attention.allSatisfy { $0["needsAttention"] as? Bool == true })
        let open = try rows(try QueryOutput(
            sessions: sample, settings: .defaults, now: now, agent: .openCode).json()).sessions
        #expect(open.map { $0["id"] as? String } == ["s2"])
    }
}

struct HistoryExtractionTests {
    private func claudeLine(
        _ content: Any, type: String = "user", minutesAgo: Double = 5,
        extra: [String: Any] = [:], entrypoint: String = "cli"
    ) -> String {
        var record: [String: Any] = [
            "type": type, "sessionId": "c-1", "cwd": "/Users/demo/alpha", "entrypoint": entrypoint,
            "timestamp": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-minutesAgo * 60)),
            "message": ["role": type, "content": content],
        ]
        record.merge(extra) { $1 }
        return String(decoding: try! JSONSerialization.data(withJSONObject: record), as: UTF8.self)
    }

    /// A record with no `entrypoint` key (as can happen in older formats).
    private func claudeLineWithoutEntrypoint(_ text: String) -> String {
        var record = try! JSONSerialization.jsonObject(with: Data(claudeLine(text).utf8)) as! [String: Any]
        record.removeValue(forKey: "entrypoint")
        return String(decoding: try! JSONSerialization.data(withJSONObject: record), as: UTF8.self)
    }

    private func codexLine(_ type: String, _ payload: [String: Any], minutesAgo: Double = 5) -> String {
        let record: [String: Any] = [
            "type": type, "payload": payload,
            "timestamp": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-minutesAgo * 60)),
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: record), as: UTF8.self)
    }

    private func codexMeta(originator: String) -> String {
        codexLine("session_meta", ["session_id": "x-1", "cwd": "/Users/demo/beta", "originator": originator])
    }

    private func codexUser(_ blocks: [String]) -> String {
        codexLine("response_item", [
            "type": "message", "role": "user",
            "content": blocks.map { ["type": "input_text", "text": $0] },
        ])
    }

    @Test func claudeKeepsTypedPromptsOnly() {
        var extractor = ClaudeHistoryExtractor()
        let out = extractor.fold([
            claudeLine("  plain question  "),
            claudeLine([["type": "text", "text": "block question"]]),
            claudeLine("injected", extra: ["isMeta": true]),
            claudeLine("subagent prompt", extra: ["isSidechain": true]),
            claudeLine([["type": "tool_result", "content": "output"]]),
            claudeLine("<command-name>/model</command-name>\n<command-args></command-args>"),
            claudeLine("<local-command-stdout>ok</local-command-stdout>"),
            claudeLine("<task-notification>\n<task-id>b1</task-id>\n</task-notification>"),
            claudeLine("<bash-input>ls</bash-input>"),
            claudeLine("<bash-stdout>out</bash-stdout><bash-stderr></bash-stderr>"),
            claudeLine("see this: <pasted_content id=\"p1\">pasted text</pasted_content>"),
            claudeLine([["type": "text", "text": "[Request interrupted by user]"]]),
            claudeLine("an answer", type: "assistant"),
        ])
        #expect(out.map(\.text) == ["plain question", "block question", "see this: pasted text"])
        #expect(out.allSatisfy { $0.agent == .claudeCode && $0.sessionID == "c-1" && $0.project == "alpha" })
    }

    @Test func claudeSkipsUnattendedSessions() {
        var sdk = ClaudeHistoryExtractor()
        #expect(sdk.fold([claudeLine("headless", entrypoint: "sdk-cli")]).isEmpty)
        var scheduled = ClaudeHistoryExtractor()
        #expect(scheduled.fold([
            claudeLine("<scheduled-task name=\"hourly\">do it</scheduled-task>"),
            claudeLine("follow-up in the same run"),
        ]).isEmpty)
    }

    @Test func codexKeepsTypedBlocksAndSkipsExec() {
        var tui = CodexHistoryExtractor()
        let out = tui.fold([
            codexMeta(originator: "codex-tui"),
            codexUser(["<environment_context>\n  <cwd>/x</cwd>\n</environment_context>"]),
            codexUser(["fix the bug"]),
            codexUser(["<turn_aborted>\nstopped\n</turn_aborted>"]),
            codexUser(["# AGENTS.md instructions for /x\n\nrules"]),
            codexLine("event_msg", ["type": "user_message", "message": "fix the bug"]),
            codexLine("response_item", ["type": "message", "role": "developer",
                                         "content": [["type": "input_text", "text": "dev"]]]),
        ])
        #expect(out.map(\.text) == ["fix the bug"])
        #expect(out.first?.sessionID == "x-1")
        #expect(out.first?.project == "beta")

        var exec = CodexHistoryExtractor()
        #expect(exec.fold([codexMeta(originator: "codex_exec"), codexUser(["scripted"])]).isEmpty)
    }

    @Test func wrapperDetectionNeedsTheWholeBlock() {
        let tags: Set<String> = ["environment_context"]
        #expect(isInjectedWrapper("<environment_context>x</environment_context>", tags: tags))
        #expect(!isInjectedWrapper("<environment_context>x</environment_context> and my question", tags: tags))
        #expect(!isInjectedWrapper("<div>hello</div>", tags: tags))
    }

    // MARK: - Ingest

    private func tempTree() throws -> URL {
        let dir = testScratchDirectory().appendingPathComponent("history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("claude/p"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("codex/2026"), withIntermediateDirectories: true)
        return dir
    }

    private func write(_ lines: [String], to url: URL) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Session-level facts from the first batch must hold in later batches.
    /// With three lines per read, every question below sits after batch one.
    @Test func unattendedSurvivesBatchBoundaries() async throws {
        let dir = try tempTree()
        defer { try? FileManager.default.removeItem(at: dir) }
        let filler = (0..<4).map { _ in claudeLine("answer", type: "assistant") }
        let scheduledRun = [claudeLine("<scheduled-task name=\"nightly\">go</scheduled-task>")] + filler
            + [claudeLine("late question A"), claudeLine("late question B")]
        let execRun = [codexMeta(originator: "codex_exec")]
            + (0..<4).map { _ in codexLine("event_msg", ["type": "task_started"]) }
            + [codexUser(["late exec prompt"])]
        let claudeFile = dir.appendingPathComponent("claude/p/s.jsonl")
        let codexFile = dir.appendingPathComponent("codex/2026/rollout-test.jsonl")
        try write(scheduledRun, to: claudeFile)
        try write(execRun, to: codexFile)

        let adapters: [any AgentAdapter] = [
            ClaudeCodeAdapter(projectsRoot: dir.appendingPathComponent("claude")),
            CodexAdapter(sessionsRoot: dir.appendingPathComponent("codex")),
        ]
        let small = IncrementalLineReader(maxLinesPerRead: 3)
        #expect(await HistoryIngest(adapters: adapters, reader: small).collect(windowDays: 7).isEmpty)

        // Negative control: the same files without the unattended markers
        // yield the late questions, so the assertion above can fail.
        try write([claudeLine("first")] + filler + [claudeLine("late question A"), claudeLine("late question B")], to: claudeFile)
        try write([codexMeta(originator: "codex-tui")] + Array(execRun.dropFirst()), to: codexFile)
        let texts = Set(await HistoryIngest(adapters: adapters, reader: small).collect(windowDays: 7).map(\.text))
        #expect(texts == ["first", "late question A", "late question B", "late exec prompt"])
    }

    /// `entrypoint` on the first record only: the session is still sdk-cli
    /// for a question after the first batch that carries no entrypoint.
    @Test func sdkEntrypointCarriesAcrossBatches() async throws {
        let dir = try tempTree()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("claude/p/s.jsonl")
        let filler = (0..<4).map { _ in claudeLineWithoutEntrypoint("x").replacingOccurrences(of: "\"type\":\"user\"", with: "\"type\":\"assistant\"") }
        let adapters: [any AgentAdapter] = [ClaudeCodeAdapter(projectsRoot: dir.appendingPathComponent("claude"))]
        let small = IncrementalLineReader(maxLinesPerRead: 3)

        try write([claudeLine("answer", type: "assistant", entrypoint: "sdk-cli")] + filler
                  + [claudeLineWithoutEntrypoint("late headless prompt")], to: file)
        #expect(await HistoryIngest(adapters: adapters, reader: small).collect(windowDays: 7).isEmpty)

        // Negative control: the same file started from the CLI yields it.
        try write([claudeLine("answer", type: "assistant", entrypoint: "cli")] + filler
                  + [claudeLineWithoutEntrypoint("late headless prompt")], to: file)
        let texts = await HistoryIngest(adapters: adapters, reader: small).collect(windowDays: 7).map(\.text)
        #expect(texts == ["late headless prompt"])
    }

    /// A file written today can hold a question from before the window; it
    /// must not show, in the index or in the stats.
    @Test func windowAppliesPerRecord() async throws {
        let dir = try tempTree()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write([
            claudeLine("ten days ago", minutesAgo: 10 * 24 * 60),
            claudeLine("just now", minutesAgo: 1),
        ], to: dir.appendingPathComponent("claude/p/s.jsonl"))
        let ingest = HistoryIngest(adapters: [ClaudeCodeAdapter(projectsRoot: dir.appendingPathComponent("claude"))])
        let records = await ingest.collect(windowDays: 7)
        #expect(records.count == 2)  // read bound is only a bound

        let index = HistoryIndex.build(records, windowDays: 7, now: Date())
        #expect(index.days.flatMap(\.questions).map(\.text) == ["just now"])
        let stats = HistoryStats.format(index, windowDays: 7, bytesRead: 0)
        #expect(stats.contains("1 questions"))
        #expect(!stats.contains("just now"))
    }

    @Test func adapterWithoutHistoryIsNeverRead() async throws {
        struct NoHistory: AgentAdapter {
            let kind: AgentKind = .vsCode
            let file: URL
            var isAvailable: Bool { true }
            func discoverSessions() throws -> [Session] { [] }
            func sources() throws -> [SourceDescriptor] { [SourceDescriptor.describing(file)].compactMap { $0 } }
        }
        let dir = try tempTree()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("claude/p/s.jsonl")
        try write([claudeLine("would be a question")], to: file)
        let ingest = HistoryIngest(adapters: [NoHistory(file: file)])
        #expect(await ingest.collect(windowDays: 7).isEmpty)
        #expect(await ingest.lastBytesRead == 0)
    }
}

struct HistoryIndexTests {
    private var utcPlus8: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return c
    }

    private func q(_ text: String, _ agent: AgentKind = .claudeCode, at iso: String, cwd: String = "/Users/demo/alpha") -> QuestionRecord {
        QuestionRecord(agent: agent, sessionID: "s", timestamp: ISO8601DateFormatter().date(from: iso)!, cwd: cwd, text: text)
    }

    /// 23:30 UTC is already the next day at UTC+8.
    @Test func bucketsByLocalDayAcrossUTCMidnight() {
        let now = ISO8601DateFormatter().date(from: "2026-09-26T12:00:00Z")!
        let records = [q("late evening UTC", at: "2026-09-25T23:30:00Z"), q("morning UTC", at: "2026-09-25T01:00:00Z")]
        let index = HistoryIndex.build(records, windowDays: 7, now: now, calendar: utcPlus8)
        #expect(index.days.count == 2)
        #expect(index.days.first?.questions.map(\.text) == ["late evening UTC"])
        let df = DateFormatter(); df.timeZone = utcPlus8.timeZone; df.dateFormat = "yyyy-MM-dd"
        #expect(df.string(from: index.days[0].day) == "2026-09-26")
    }

    @Test func windowStartMatchesTheReport() {
        let now = ISO8601DateFormatter().date(from: "2026-09-26T12:00:00Z")!
        let report = ReportBuilder(calendar: utcPlus8).build(samplesByAgent: [:], now: now, windowDays: 7)
        #expect(HistoryIndex.windowStart(windowDays: 7, now: now, calendar: utcPlus8) == report.windowStart)
    }

    @Test func keywordAgentAndProjectFilters() {
        let now = ISO8601DateFormatter().date(from: "2026-09-26T12:00:00Z")!
        let records = [
            q("Fix the Café menu", at: "2026-09-26T10:00:00Z"),
            q("deploy", .codex, at: "2026-09-26T09:00:00Z", cwd: "/Users/demo/beta"),
            q("unrelated", at: "2026-09-26T08:00:00Z"),
        ]
        func texts(_ i: HistoryIndex) -> [String] { i.days.flatMap(\.questions).map(\.text) }
        #expect(texts(HistoryIndex.build(records, windowDays: 1, now: now, calendar: utcPlus8, keyword: "cafe")) == ["Fix the Café menu"])
        #expect(texts(HistoryIndex.build(records, windowDays: 1, now: now, calendar: utcPlus8, agent: .codex)) == ["deploy"])
        #expect(texts(HistoryIndex.build(records, windowDays: 1, now: now, calendar: utcPlus8, project: "beta")) == ["deploy"])
        #expect(HistoryIndex.build(records, windowDays: 1, now: now, calendar: utcPlus8).count == 3)
    }

    @Test func statsNeverPrintQuestionText() {
        let canary = "VIBRA_HISTORY_CANARY_MUST_NOT_LEAK"
        let now = Date()
        let index = HistoryIndex.build([q(canary, at: ISO8601DateFormatter().string(from: now.addingTimeInterval(-60)))],
                                       windowDays: 7, now: now)
        #expect(index.count == 1)
        let stats = HistoryStats.format(index, windowDays: 7, bytesRead: 1234)
        #expect(!stats.contains(canary))
        #expect(!stats.contains("alpha"))
    }

    @Test func textIsTrimmedAndCapped() {
        #expect(QuestionRecord.normalized("  \n ") == nil)
        #expect(QuestionRecord.normalized(String(repeating: "x", count: 5000))?.count == QuestionRecord.maxLength)
        let r = QuestionRecord(agent: .codex, sessionID: "", timestamp: Date(), cwd: "", text: "line one\nline two")
        #expect(r.firstLine() == "line one")
        #expect(r.project == "(no folder)")
    }
}
