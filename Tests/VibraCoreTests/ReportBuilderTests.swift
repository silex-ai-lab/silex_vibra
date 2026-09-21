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
