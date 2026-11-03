import Foundation
import Testing
@testable import VibraCore

/// The perf canary: raw Claude Code transcripts carry one sentinel in each
/// place the report must never read, the analyzer fires every detector on
/// them, and no sentinel reaches a sample, the JSON, the text or an evidence
/// line. The Makefile checks this test by its exact name.
struct PerfPrivacyTests {
    private let sentinels = [
        "text": "SENTINEL_TEXT_7d1",
        "thinking": "SENTINEL_THINKING_9f2",
        "toolInput": "SENTINEL_TOOL_INPUT_3a4",
        "toolResult": "SENTINEL_TOOL_RESULT_5b6",
        "wireToolInputs": "SENTINEL_WIRE_1c8",
        "cwdParent": "SENTINEL_CWD_2e9",
    ]

    private var losAngeles: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    /// In range of every `defaults write` key, and small enough that a few
    /// turns fire each detector.
    private let thresholds = PerfThresholds(
        minTurns: 3,
        d1MinTurnsAboveFloor: 5,
        d1CarryFloorTokens: 20_000,
        d2MinRewriteTokens: 30_000,
        d3MinBurstTurns: 2,
        leadMinUSD: 0.25,
        leadMinShare: 0.10
    )

    private func stamp(_ minutes: Int) -> String {
        let base = ISO8601DateFormatter().date(from: "2026-11-02T10:00:00Z")!
        return ISO8601DateFormatter().string(from: base.addingTimeInterval(Double(minutes) * 60))
    }

    private func assistant(
        _ id: String,
        minutes: Int,
        model: String = "claude-opus-5",
        creation: Int = 0,
        read: Int = 0,
        content: [[String: Any]] = [],
        extra: [String: Any] = [:]
    ) -> String {
        var record: [String: Any] = [
            "type": "assistant",
            "timestamp": stamp(minutes),
            "cwd": "/Users/\(sentinels["cwdParent"]!)/proj",
            "message": [
                "id": id,
                "role": "assistant",
                "model": model,
                "content": content,
                "usage": [
                    "input_tokens": 0, "output_tokens": 20,
                    "cache_creation_input_tokens": creation, "cache_read_input_tokens": read,
                ],
            ] as [String: Any],
        ]
        for (key, value) in extra { record[key] = value }
        return line(record)
    }

    private func line(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private struct Fixture {
        let root: URL
        let files: [String: Data]
    }

    private func writeFixture() throws -> Fixture {
        let s = sentinels
        let carry = (0..<6).map { i in
            assistant("c\(i)", minutes: i, read: 100_000,
                      content: i == 0 ? [["type": "text", "text": "plan: \(s["text"]!)"]]
                             : i == 1 ? [["type": "thinking", "thinking": "hmm \(s["thinking"]!)"]]
                             : [],
                      extra: i == 2 ? ["wireToolInputs": [["path": s["wireToolInputs"]!]]] : [:])
        }
        let rewrite = [
            assistant("r0", minutes: 0, creation: 100_000),
            line([
                "type": "user", "timestamp": stamp(1), "cwd": "/Users/\(s["cwdParent"]!)/proj",
                "message": ["role": "user", "content": [
                    ["type": "tool_result", "tool_use_id": "t1", "content": "output \(s["toolResult"]!)"],
                ]] as [String: Any],
            ]),
            assistant("r1", minutes: 130, creation: 100_000),
            assistant("r2", minutes: 131, read: 100_000),
        ]
        let burst = [
            assistant("b0", minutes: 0, read: 50_000,
                      content: [["type": "tool_use", "id": "t1", "name": "Read",
                                 "input": ["file_path": "/tmp/\(s["toolInput"]!)"]]]),
            assistant("b1", minutes: 1, read: 50_000,
                      content: [["type": "tool_use", "id": "t2", "name": "Grep", "input": ["pattern": "x"]]]),
        ] + (2..<8).map { assistant("b\($0)", minutes: $0, read: 150_000) }

        let root = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        let files = [
            "carry.jsonl": Data((carry.map { $0 + "\n" }.joined()).utf8),
            "rewrite.jsonl": Data((rewrite.map { $0 + "\n" }.joined()).utf8),
            "burst.jsonl": Data((burst.map { $0 + "\n" }.joined()).utf8),
        ]
        for (name, data) in files {
            let url = root.appendingPathComponent("proj/\(name)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return Fixture(root: root, files: files)
    }

    private func detector(_ finding: Suggestion.Finding) -> String {
        switch finding {
        case .contextCarry: "contextCarry"
        case .cacheRewrite: "cacheRewrite"
        case .explorationBurst: "explorationBurst"
        }
    }

    private func leaks(in text: String) -> [String] {
        sentinels.filter { text.contains($0.value) }.map(\.key).sorted()
    }

    @Test func perfPrivacySentinelsNeverLeak() async throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        // Every sentinel is in the raw bytes, so the absence checks below mean something.
        let raw = fixture.files.values.map { String(decoding: $0, as: UTF8.self) }.joined()
        for (place, sentinel) in sentinels {
            #expect(raw.contains(sentinel), "fixture must hold the \(place) sentinel")
        }

        let window = ReportWindow(now: ISO8601DateFormatter().date(from: "2026-11-03T21:00:00Z")!,
                                  days: 7, calendar: losAngeles)
        let input = await ReportIngest(adapters: [ClaudeCodeAdapter(projectsRoot: fixture.root)]).collect(window: window)
        let sources = try #require(input.sources[.claudeCode])
        #expect(sources.count == 3)
        let perf = PerfAnalyzer.report(claudeSources: sources, window: window, thresholds: thresholds)

        // The detectors must fire first, or the checks below pass vacuously.
        for name in ["contextCarry", "cacheRewrite", "explorationBurst"] {
            #expect(perf.suggestions.contains { $0.isLead && detector($0.finding) == name },
                    "\(name) must produce a lead")
        }

        for source in sources {
            for sample in source.samples {
                #expect(leaks(in: String(describing: sample)).isEmpty,
                        "sample of \(source.url.lastPathComponent) leaks \(leaks(in: String(describing: sample)))")
                #expect(sample.project == "proj")
            }
        }
        let burst = try #require(sources.first { $0.url.lastPathComponent == "burst.jsonl" })
        #expect(burst.samples.map(\.toolNames) == [["Read"], ["Grep"], [], [], [], [], [], []],
                "toolNames are exactly the tool_use names, nothing from input")

        let usage = ReportBuilder().build(samplesByAgent: input.samplesByAgent, window: window)
        let json = String(decoding: try ReportJSON.encode(usage: usage, window: window, read: input.read, perf: perf),
                          as: UTF8.self)
        #expect(leaks(in: json).isEmpty, "JSON leaks \(leaks(in: json))")
        #expect(json.contains("\"perf\" : {"), "the JSON carries the perf report")

        let text = ReportText.render(usage: usage, perf: perf, read: input.read, seconds: 0.1)
        #expect(leaks(in: text).isEmpty, "text leaks \(leaks(in: text))")
        #expect(text.contains("1. "), "the text shows at least one lead")

        for suggestion in perf.suggestions {
            let evidence = ReportText.evidenceLine(for: suggestion)
            #expect(leaks(in: evidence).isEmpty, "evidence line leaks \(leaks(in: evidence))")
        }
    }
}
