import Foundation
import Testing
@testable import VibraCore

/// A report that is merely plausible is worse than none: the numbers look
/// authoritative whether or not they are right.
struct ReportBuilderTests {

    /// Fixed timezone so "local day" is deterministic regardless of where the
    /// suite runs.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)!
    }

    private func usage(_ n: Int) -> TokenUsage { TokenUsage(input: n, output: 0) }

    private var now: Date { date("2026-09-20T12:00:00Z") }

    private var window: ReportWindow { ReportWindow(now: now, days: 7, calendar: calendar) }

    // MARK: - The bug this feature exists to avoid

    @Test func multiDayUsageIsSplitAcrossDays() {
        // The real case: one session spanning several days. Attributing its
        // whole total to the last day shows zero for the days work happened.
        let samples = [
            UsageSample(timestamp: date("2026-09-18T10:00:00Z"), model: "claude-opus-5", usage: usage(100)),
            UsageSample(timestamp: date("2026-09-19T10:00:00Z"), model: "claude-opus-5", usage: usage(200)),
            UsageSample(timestamp: date("2026-09-20T10:00:00Z"), model: "claude-opus-5", usage: usage(300)),
        ]
        let r = ReportBuilder().build(samplesByAgent: [.claudeCode: samples], window: window)

        #expect(r.days.count == 3, "three days of work must produce three day lines")
        #expect(r.days.map(\.usage.input) == [100, 200, 300])
        #expect(r.total.input == 600)
    }

    // MARK: - Window

    @Test func windowFiltersPerDayNotPerSession() {
        // A session active today but with usage from three weeks ago must
        // contribute only its in-window days.
        let samples = [
            UsageSample(timestamp: date("2026-08-25T10:00:00Z"), model: "claude-opus-5", usage: usage(999)),
            UsageSample(timestamp: date("2026-09-20T10:00:00Z"), model: "claude-opus-5", usage: usage(5)),
        ]
        let r = ReportBuilder().build(samplesByAgent: [.claudeCode: samples], window: window)

        #expect(r.total.input == 5, "out-of-window days must be dropped, got \(r.total.input)")
        #expect(r.days.count == 1)
    }

    @Test func windowIncludesTodayAndSixPrecedingDays() {
        let inWindow = UsageSample(timestamp: date("2026-09-14T18:00:00Z"), model: "claude-opus-5", usage: usage(7))
        let outOfWindow = UsageSample(timestamp: date("2026-09-13T18:00:00Z"), model: "claude-opus-5", usage: usage(11))
        let r = ReportBuilder().build(samplesByAgent: [.claudeCode: [inWindow, outOfWindow]], window: window)
        #expect(r.total.input == 7)
    }

    // MARK: - Timezone

    @Test func bucketsUseLocalDaysNotUTC() {
        // 2026-09-19T03:00Z is still the evening of Sep 18 in Los Angeles.
        // Bucketing by UTC would move it to the 19th.
        let sample = UsageSample(timestamp: date("2026-09-19T03:00:00Z"), model: "claude-opus-5", usage: usage(42))
        let r = ReportBuilder().build(samplesByAgent: [.claudeCode: [sample]], window: window)

        let day = try! #require(r.days.first?.day)

        // Compare against an exact instant, NOT by reading the date back with
        // a calendar. Reading back through the LA calendar makes a UTC bucket
        // (Sep 19 00:00Z) *look* like Sep 18 17:00 local, so such an assertion
        // passes whether or not the bucketing is correct. Caught by mutation
        // testing: forcing UTC bucketing left the earlier version green.
        let expected = calendar.startOfDay(for: date("2026-09-18T20:00:00Z"))
        #expect(day == expected,
                "03:00Z belongs to the previous local day in LA; got \(day), want \(expected)")
    }

    // MARK: - Pricing honesty

    @Test func unknownModelYieldsUnpricedTokensNotZeroDollars() {
        let sample = UsageSample(timestamp: date("2026-09-20T10:00:00Z"),
                                 model: "some-model-nobody-published-rates-for",
                                 usage: usage(1_000))
        let r = ReportBuilder().build(samplesByAgent: [.claudeCode: [sample]], window: window)

        #expect(r.estimatedValue == 0)
        #expect(r.unpricedTokens == 1_000, "unpriced tokens must be surfaced, not silently free")
        #expect(r.hasUnpriced)
    }

    @Test func multiModelSessionIsPricedPerModel() {
        // Pricing a whole session at whichever model happened to be last is
        // wrong when the models differ in rate by an order of magnitude.
        let day = date("2026-09-20T10:00:00Z")
        let opus = UsageSample(timestamp: day, model: "claude-opus-5", usage: usage(1_000_000))
        let haiku = UsageSample(timestamp: day, model: "claude-haiku-4-5", usage: usage(1_000_000))

        let both = ReportBuilder().build(samplesByAgent: [.claudeCode: [opus, haiku]], window: window)
        let opusOnly = ReportBuilder().build(samplesByAgent: [.claudeCode: [opus, UsageSample(timestamp: day, model: "claude-opus-5", usage: usage(1_000_000))]], window: window)

        #expect(both.estimatedValue < opusOnly.estimatedValue,
                "a cheaper model in the mix must lower the estimate")
        #expect(both.estimatedValue > 0)
    }

    // MARK: - Undated

    @Test func undatedUsageIsReportedSeparatelyNotDroppedOrDatedToToday() {
        let dated = UsageSample(timestamp: date("2026-09-20T10:00:00Z"), model: "claude-opus-5", usage: usage(10))
        let undated = UsageSample(timestamp: nil, model: "deepseek-v4-pro", usage: usage(777))
        let r = ReportBuilder().build(samplesByAgent: [.claudeCode: [dated], .openCode: [undated]], window: window)

        #expect(r.undated.input == 777, "undatable usage must be kept")
        #expect(r.days.count == 1, "undatable usage must not create or join a day")
        #expect(r.days.first?.usage.input == 10, "undated usage must not leak into today")
    }

    @Test func emptyInputProducesEmptyReport() {
        let r = ReportBuilder().build(samplesByAgent: [:], window: window)
        #expect(r.days.isEmpty)
        #expect(r.total.total == 0)
        #expect(r.estimatedValue == 0)
        #expect(!r.hasUnpriced)
    }
}

/// The window is shared by the ingest, the builder and the analyzer. Its
/// days are local days, so the 2026-11-01 DST change in Los Angeles is the
/// case that tells a calendar day apart from a 24-hour span.
struct ReportWindowTests {
    private var losAngeles: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// 2026-11-03T21:00Z is 13:00 PST on Nov 3; the window reaches back to
    /// Oct 28, which was still PDT.
    private var window: ReportWindow {
        ReportWindow(now: date("2026-11-03T21:00:00Z"), days: 7, calendar: losAngeles)
    }

    @Test func boundsAreLocalMidnightsAcrossTheDSTChange() {
        #expect(window.today == date("2026-11-03T08:00:00Z"), "Nov 3 starts at 00:00 PST = 08:00Z")
        #expect(window.start == date("2026-10-28T07:00:00Z"), "Oct 28 starts at 00:00 PDT = 07:00Z")
        #expect(window.today.timeIntervalSince(window.start) == 6 * 86_400 + 3_600,
                "six days plus the hour the clocks gave back")
        #expect(window.days == 7)
        #expect(window.now == date("2026-11-03T21:00:00Z"))
    }

    @Test func fileCutoffIsOneDayWiderThanTheWindow() {
        #expect(window.fileCutoff == date("2026-11-03T21:00:00Z").addingTimeInterval(-8 * 86_400))
    }

    @Test func containsIsDecidedByLocalDay() {
        #expect(!window.contains(date("2026-10-28T06:59:59Z")), "still Oct 27 in LA")
        #expect(window.contains(date("2026-10-28T07:00:00Z")), "first second of Oct 28 PDT")
        #expect(window.contains(date("2026-11-04T07:59:59Z")), "still Nov 3 PST")
        #expect(!window.contains(date("2026-11-04T08:00:00Z")), "Nov 4 is after today")
    }

    @Test func dayOfOnTheChangeDayIsThePDTMidnight() {
        // Nov 1 began at 00:00 PDT (07:00Z) and lasted 25 hours.
        #expect(window.day(of: date("2026-11-01T08:30:00Z")) == date("2026-11-01T07:00:00Z"))
        #expect(window.day(of: date("2026-11-02T07:30:00Z")) == date("2026-11-01T07:00:00Z"),
                "07:30Z on Nov 2 is 23:30 PST on Nov 1")
        #expect(window.day(of: date("2026-11-02T08:00:00Z")) == date("2026-11-02T08:00:00Z"))
    }
}

struct PerfThresholdsTests {
    /// The comparator checks these keys and values against the oracle's
    /// `DEFAULTS` exactly, so both are pinned here.
    @Test func encodesTheOraclesSevenBareKeysAndDefaults() throws {
        let data = try JSONEncoder().encode(PerfThresholds.defaults)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == [
            "minTurns", "d1MinTurnsAboveFloor", "d1CarryFloorTokens", "d2MinRewriteTokens",
            "d3MinBurstTurns", "leadMinUSD", "leadMinShare",
        ])
        #expect(object["minTurns"] as? Int == 10)
        #expect(object["d1MinTurnsAboveFloor"] as? Int == 50)
        #expect(object["d1CarryFloorTokens"] as? Int == 200_000)
        #expect(object["d2MinRewriteTokens"] as? Int == 30_000)
        #expect(object["d3MinBurstTurns"] as? Int == 3)
        #expect(object["leadMinUSD"] as? Double == 0.25)
        #expect(object["leadMinShare"] as? Double == 0.10)
    }

    @Test func roundTripsThroughCodable() throws {
        let custom = PerfThresholds(minTurns: 3, d1MinTurnsAboveFloor: 5, d1CarryFloorTokens: 20_000,
                                    d2MinRewriteTokens: 5_000, d3MinBurstTurns: 2, leadMinUSD: 0, leadMinShare: 0)
        let decoded = try JSONDecoder().decode(PerfThresholds.self, from: JSONEncoder().encode(custom))
        #expect(decoded == custom)
    }
}

/// What `--report --json` prints, from a fixture tree through `collect` and
/// `encode`, so the comparator's input is pinned end to end.
struct ReportJSONTests {
    private var losAngeles: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private let main = """
    {"type":"assistant","timestamp":"2026-11-03T10:00:00.000Z","cwd":"/Users/demo/proj","message":{"id":"a","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":100}}}
    {"type":"assistant","timestamp":"2026-11-03T10:00:01.000Z","cwd":"/Users/demo/proj","message":{"id":"a","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":9,"cache_creation_input_tokens":0,"cache_read_input_tokens":100}}}
    {"type":"assistant","timestamp":"2026-11-03T10:00:02.000Z","cwd":"/Users/demo/proj","message":{"model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":100}}}

    """
    private let subagent = """
    {"type":"assistant","timestamp":"2026-11-03T10:00:03.000Z","cwd":"/Users/demo/proj","message":{"id":"b","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":100}}}

    """

    private func encodedFixtureTree() async throws -> (object: [String: Any], bytes: Int) {
        let root = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            (root.appendingPathComponent("proj/s1.jsonl"), Data(main.utf8)),
            (root.appendingPathComponent("proj/s1/subagents/agent-a1.jsonl"), Data(subagent.utf8)),
        ]
        for (url, data) in files {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }

        let window = ReportWindow(now: ISO8601DateFormatter().date(from: "2026-11-03T21:00:00Z")!,
                                  days: 7, calendar: losAngeles)
        let input = await ReportIngest(adapters: [ClaudeCodeAdapter(projectsRoot: root)]).collect(window: window)
        let usage = ReportBuilder().build(samplesByAgent: input.samplesByAgent, window: window)
        let data = try ReportJSON.encode(usage: usage, window: window, read: input.read, perf: nil)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (object, files.map(\.1.count).reduce(0, +))
    }

    @Test func schemaWindowReadAndAgentsFromAFixtureTree() async throws {
        let (object, bytes) = try await encodedFixtureTree()

        #expect(Set(object.keys) == ["schema", "window", "read", "agents", "perf"])
        #expect(object["schema"] as? Int == 1)
        #expect(object["perf"] is NSNull, "Task 1 writes perf as an explicit null")

        let window = try #require(object["window"] as? [String: Any])
        #expect(Set(window.keys) == ["days", "start", "now"])
        #expect(window["days"] as? Int == 7)
        #expect(window["now"] as? String == "2026-11-03T21:00:00Z")
        #expect(window["start"] as? String == "2026-10-28T07:00:00Z", "local midnight PDT, as ISO 8601")

        let read = try #require(object["read"] as? [String: Any])
        #expect(read["bytes"] as? Int == bytes, "every byte of both files, main and subagent")
        #expect(read["files"] as? Int == 2)

        // Main file: "a" folds to its last record (10/9/0/100) plus the
        // no-ID record (10/5/0/100); subagent: one response (10/5/0/100).
        let agents = try #require(object["agents"] as? [[String: Any]])
        #expect(agents.count == 1)
        let claude = try #require(agents.first)
        #expect(claude["agent"] as? String == "claudeCode")
        #expect(claude["usage"] as? [String: Int] == ["input": 30, "output": 19, "cacheCreation": 0, "cacheRead": 300])
        #expect(claude["unpricedTokens"] as? Int == 0)
        // claude-opus-5: $15 input, $75 output, $1.50 cache read, per million.
        let value = (30.0 * 15.0 + 19.0 * 75.0 + 300.0 * 1.50) / 1e6
        #expect(abs((claude["estimatedValue"] as? Double ?? -1) - value) < 1e-12)
    }

    @Test func perfEncodesThresholdsAndFindingsByCaseName() throws {
        let window = ReportWindow(now: ISO8601DateFormatter().date(from: "2026-11-03T21:00:00Z")!,
                                  days: 7, calendar: losAngeles)
        let usage = ReportBuilder().build(samplesByAgent: [:], window: window)
        let perf = PerfReport(
            thresholds: .defaults, analyzedSessions: 1, unpricedSessions: 0, skippedSmallSessions: 2,
            suggestions: [Suggestion(
                sessionID: "s1", project: "proj", startedAt: window.now, turns: 60,
                finding: .contextCarry(segments: 1, turnsAboveFloor: 60, peakContext: 250_000, floorTokens: 200_000),
                exposureUSD: 0.9, sessionValueUSD: 4.5, isLead: true)])
        let data = try ReportJSON.encode(usage: usage, window: window, read: ReadStats(bytes: 0, files: 0), perf: perf)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let encoded = try #require(object["perf"] as? [String: Any])
        let thresholds = try #require(encoded["thresholds"] as? [String: Any])
        #expect(Set(thresholds.keys) == [
            "minTurns", "d1MinTurnsAboveFloor", "d1CarryFloorTokens", "d2MinRewriteTokens",
            "d3MinBurstTurns", "leadMinUSD", "leadMinShare",
        ])
        let suggestion = try #require((encoded["suggestions"] as? [[String: Any]])?.first)
        #expect(suggestion["finding"] as? [String: [String: Int]] ==
                ["contextCarry": ["segments": 1, "turnsAboveFloor": 60, "peakContext": 250_000, "floorTokens": 200_000]])
        #expect(suggestion["startedAt"] as? String == "2026-11-03T21:00:00Z")
        #expect(suggestion["isLead"] as? Bool == true)
    }
}
