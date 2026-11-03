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

    // MARK: - The bug this feature exists to avoid

    @Test func multiDayUsageIsSplitAcrossDays() {
        // The real case: one session spanning several days. Attributing its
        // whole total to the last day shows zero for the days work happened.
        let samples = [
            UsageSample(timestamp: date("2026-09-18T10:00:00Z"), model: "claude-opus-5", usage: usage(100)),
            UsageSample(timestamp: date("2026-09-19T10:00:00Z"), model: "claude-opus-5", usage: usage(200)),
            UsageSample(timestamp: date("2026-09-20T10:00:00Z"), model: "claude-opus-5", usage: usage(300)),
        ]
        let r = ReportBuilder(calendar: calendar)
            .build(samplesByAgent: [.claudeCode: samples], now: now)

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
        let r = ReportBuilder(calendar: calendar)
            .build(samplesByAgent: [.claudeCode: samples], now: now, windowDays: 7)

        #expect(r.total.input == 5, "out-of-window days must be dropped, got \(r.total.input)")
        #expect(r.days.count == 1)
    }

    @Test func windowIncludesTodayAndSixPrecedingDays() {
        let inWindow = UsageSample(timestamp: date("2026-09-14T18:00:00Z"), model: "claude-opus-5", usage: usage(7))
        let outOfWindow = UsageSample(timestamp: date("2026-09-13T18:00:00Z"), model: "claude-opus-5", usage: usage(11))
        let r = ReportBuilder(calendar: calendar)
            .build(samplesByAgent: [.claudeCode: [inWindow, outOfWindow]], now: now, windowDays: 7)
        #expect(r.total.input == 7)
    }

    // MARK: - Timezone

    @Test func bucketsUseLocalDaysNotUTC() {
        // 2026-09-19T03:00Z is still the evening of Sep 18 in Los Angeles.
        // Bucketing by UTC would move it to the 19th.
        let sample = UsageSample(timestamp: date("2026-09-19T03:00:00Z"), model: "claude-opus-5", usage: usage(42))
        let r = ReportBuilder(calendar: calendar)
            .build(samplesByAgent: [.claudeCode: [sample]], now: now)

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
        let r = ReportBuilder(calendar: calendar)
            .build(samplesByAgent: [.claudeCode: [sample]], now: now)

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

        let both = ReportBuilder(calendar: calendar)
            .build(samplesByAgent: [.claudeCode: [opus, haiku]], now: now)
        let opusOnly = ReportBuilder(calendar: calendar)
            .build(samplesByAgent: [.claudeCode: [opus, UsageSample(timestamp: day, model: "claude-opus-5", usage: usage(1_000_000))]], now: now)

        #expect(both.estimatedValue < opusOnly.estimatedValue,
                "a cheaper model in the mix must lower the estimate")
        #expect(both.estimatedValue > 0)
    }

    // MARK: - Undated

    @Test func undatedUsageIsReportedSeparatelyNotDroppedOrDatedToToday() {
        let dated = UsageSample(timestamp: date("2026-09-20T10:00:00Z"), model: "claude-opus-5", usage: usage(10))
        let undated = UsageSample(timestamp: nil, model: "deepseek-v4-pro", usage: usage(777))
        let r = ReportBuilder(calendar: calendar)
            .build(samplesByAgent: [.claudeCode: [dated], .openCode: [undated]], now: now)

        #expect(r.undated.input == 777, "undatable usage must be kept")
        #expect(r.days.count == 1, "undatable usage must not create or join a day")
        #expect(r.days.first?.usage.input == 10, "undated usage must not leak into today")
    }

    @Test func emptyInputProducesEmptyReport() {
        let r = ReportBuilder(calendar: calendar).build(samplesByAgent: [:], now: now)
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
