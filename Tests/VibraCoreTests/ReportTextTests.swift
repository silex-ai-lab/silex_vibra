import Foundation
import Testing
@testable import VibraCore

/// What the report window and `--report` print. Expected strings are the
/// plan's templates, not the renderer's output.
struct ReportTextTests {
    // MARK: - Fixtures

    private var now: Date { ISO8601DateFormatter().date(from: "2026-11-03T21:00:00Z")! }

    private func usage(days: Int = 7) -> UsageReport {
        let window = ReportWindow(now: now, days: days, calendar: .current)
        return ReportBuilder().build(samplesByAgent: [:], window: window)
    }

    /// Noon, local time, on 2026-10-30: the same local date in every zone the
    /// suite can run in.
    private var oct30: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))!
    }

    private func perf(
        _ suggestions: [Suggestion],
        analyzed: Int = 5,
        unpriced: Int = 0,
        skipped: Int = 0
    ) -> PerfReport {
        PerfReport(thresholds: .defaults, analyzedSessions: analyzed, unpricedSessions: unpriced,
                   skippedSmallSessions: skipped, suggestions: suggestions)
    }

    private func suggestion(
        _ finding: Suggestion.Finding,
        session: String = "s",
        project: String = "proj",
        turns: Int = 20,
        exposure: Double? = 1.0,
        lead: Bool = true
    ) -> Suggestion {
        Suggestion(sessionID: session, project: project, startedAt: oct30, turns: turns, finding: finding,
                   exposureUSD: exposure, sessionValueUSD: exposure.map { $0 * 4 }, isLead: lead)
    }

    private func d1(session: String = "s", project: String = "proj", turns: Int = 20,
                    exposure: Double? = 1.0, lead: Bool = true, floor: Int = 200_000) -> Suggestion {
        suggestion(.contextCarry(segments: 1, turnsAboveFloor: 60, peakContext: 250_000, floorTokens: floor),
                   session: session, project: project, turns: turns, exposure: exposure, lead: lead)
    }

    private func d2(session: String = "s", project: String = "proj", turns: Int = 20,
                    exposure: Double? = 1.0, lead: Bool = true,
                    cause: Suggestion.RewriteCause = .idleOver1h) -> Suggestion {
        suggestion(.cacheRewrite(events: 3, rewrittenTokens: 300_000, dominantCause: cause),
                   session: session, project: project, turns: turns, exposure: exposure, lead: lead)
    }

    private func d3(session: String = "s", project: String = "proj", turns: Int = 20,
                    exposure: Double? = 1.0, lead: Bool = true) -> Suggestion {
        suggestion(.explorationBurst(bursts: 2, burstTurns: 7),
                   session: session, project: project, turns: turns, exposure: exposure, lead: lead)
    }

    private func render(_ perf: PerfReport, usage: UsageReport? = nil,
                        read: ReadStats = ReadStats(bytes: 0, files: 0), seconds: Double = 0) -> String {
        ReportText.render(usage: usage ?? self.usage(), perf: perf, read: read, seconds: seconds)
    }

    /// Where `needle` first appears, so line order can be asserted.
    private func position(of needle: String, in text: String) throws -> Int {
        let range = try #require(text.range(of: needle), "missing: \(needle)")
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    private let d1Action = "Run /compact inside long tasks and /clear between tasks. Split unrelated work into separate sessions."
    private let d2IdleAction = "Before a long break, consider /compact, or /clear if the task is done. After the cache expires, much of the context is written to cache again."
    private let d3Action = "@-mention the files you mean, or hand broad searches to a subagent so only its conclusion enters this session."
    private let footer = "Estimated API-equivalent value at Vibra's table rates (last verified 2026-09-19); 1-hour cache writes use the single write rate. Not a bill."

    // MARK: - Read line and usage section

    @Test func readLineFromReadStats() {
        let text = render(perf([]), read: ReadStats(bytes: 3 * 1_048_576, files: 12), seconds: 1.26)
        #expect(text.hasSuffix("Read 3.0 MB from 12 files in 1.3s.\n"))
    }

    @Test func usageSectionKeepsItsHeadingsAndWording() {
        let text = render(perf([]))
        for needle in ["USAGE — last 7 days (rolling)", "BY DAY", "BY AGENT", "TOTAL",
                       "Estimated API-equivalent value, not a bill.", "Computed locally. Nothing left this machine."] {
            #expect(text.contains(needle), "missing: \(needle)")
        }
    }

    // MARK: - Empty states

    @Test func noAnalyzedSessionNamesTheWindowDays() {
        let text = render(perf([], analyzed: 0, skipped: 4), usage: usage(days: 3))
        #expect(text.contains("No Claude Code session in the last 3 days had enough turns to analyze."))
        #expect(!text.contains("No priced pattern"))
        #expect(text.contains(footer))
    }

    @Test func noLeadAmongAnalyzedSessions() {
        let text = render(perf([d1(exposure: 0.05, lead: false)], analyzed: 4))
        #expect(text.contains("No priced pattern above the thresholds in 4 analyzed sessions."))
        #expect(!text.contains("1. "))
        #expect(!text.contains("no published rate"))
    }

    // MARK: - Leads

    @Test func oneLinePerDetectorOrderedByExposureWithCaseNameTieBreak() throws {
        let text = render(perf([
            d1(session: "s1", project: "one", exposure: 1.0),
            d1(session: "s2", project: "two", exposure: 2.0),
            d1(session: "s3", project: "three", exposure: 0.5),
            d2(session: "s4", project: "four", exposure: 2.0),
            d3(session: "s5", project: "five", exposure: 3.0),
        ]))
        let burst = try position(of: "1. \(d3Action)", in: text)
        let rewrite = try position(of: "2. \(d2IdleAction)", in: text)
        let carry = try position(of: "3. \(d1Action)", in: text)
        #expect(burst < rewrite && rewrite < carry, "largest exposure first; cacheRewrite before contextCarry at 2.0")
        #expect(!text.contains("4. "))
        #expect(text.contains("two, Oct 30, 60 turns above 200k: the context above 200k cost about $2.00. (also in 2 other sessions)"))
        #expect(!text.contains("one, Oct 30") && !text.contains("three, Oct 30"), "the other D1 leads are counted, not shown")
        #expect(text.contains("four, Oct 30: 3 times, context already in cache was written again, the largest part after a gap of over an hour (inferred). Write premium about $2.00.\n"))
        #expect(text.contains("five, Oct 30: 2 search bursts. If what they added stayed in context, re-sending it cost about $3.00.\n"))
    }

    @Test func alsoInOneOtherSession() {
        let text = render(perf([d2(session: "a", exposure: 0.4), d2(session: "b", exposure: 0.9)]))
        #expect(text.contains("Write premium about $0.90. (also in 1 other session)"))
        #expect(!text.contains("$0.40"))
    }

    @Test func nonLeadSuggestionsNeverMakeALine() {
        let text = render(perf([d1(exposure: 1.0), d3(session: "t", exposure: 0.1, lead: false)]))
        #expect(text.contains("1. \(d1Action)"))
        #expect(!text.contains(d3Action))
    }

    // MARK: - Evidence lines

    @Test func d1LineWithANonDefaultFloor() {
        let s = suggestion(.contextCarry(segments: 2, turnsAboveFloor: 7, peakContext: 300_000, floorTokens: 250_000),
                           exposure: 1.234)
        #expect(ReportText.evidenceLine(for: s)
                == "proj, Oct 30, 7 turns above 250k: the context above 250k cost about $1.23.")
    }

    @Test func d1LineWithTheDefaultFloor() {
        #expect(ReportText.evidenceLine(for: d1(exposure: 0.9))
                == "proj, Oct 30, 60 turns above 200k: the context above 200k cost about $0.90.")
    }

    @Test func unknownProjectAndLocalDate() {
        let s = d3(project: "", exposure: 0.75)
        #expect(ReportText.evidenceLine(for: s)
                == "unknown project, Oct 30: 2 search bursts. If what they added stayed in context, re-sending it cost about $0.75.")
    }

    @Test func singleEventsAndBurstsAreSingular() {
        let rewrite = suggestion(.cacheRewrite(events: 1, rewrittenTokens: 100_000, dominantCause: .idleOver1h), exposure: 0.5)
        #expect(ReportText.evidenceLine(for: rewrite)
                == "proj, Oct 30: 1 time, context already in cache was written again, the largest part after a gap of over an hour (inferred). Write premium about $0.50.")
        let burst = suggestion(.explorationBurst(bursts: 1, burstTurns: 4), exposure: 0.75)
        #expect(ReportText.evidenceLine(for: burst)
                == "proj, Oct 30: 1 search burst. If what they added stayed in context, re-sending it cost about $0.75.")
    }

    @Test func d2LinesFollowTheDominantCause() {
        let lines = [
            Suggestion.RewriteCause.modelSwitch: "after a model switch",
            .idleOver1h: "after a gap of over an hour",
            .idleOver5m: "after a gap of over 5 minutes",
            .other: "with no model switch or long gap",
        ]
        for (cause, phrase) in lines {
            #expect(ReportText.evidenceLine(for: d2(exposure: 0.5, cause: cause))
                    == "proj, Oct 30: 3 times, context already in cache was written again, the largest part \(phrase) (inferred). Write premium about $0.50.")
        }
    }

    @Test func actionsFollowTheDetectorAndTheD2Cause() {
        #expect(ReportText.action(for: d1()) == d1Action)
        #expect(ReportText.action(for: d2(cause: .modelSwitch))
                == "Pick the model before starting. A switch mid-session writes the cache again.")
        #expect(ReportText.action(for: d2(cause: .idleOver1h)) == d2IdleAction)
        #expect(ReportText.action(for: d2(cause: .idleOver5m)) == d2IdleAction)
        #expect(ReportText.action(for: d2(cause: .other))
                == "Large parts of an already-cached prompt were written again. Check /context for tools or files that change between turns.")
        #expect(ReportText.action(for: d3()) == d3Action)
    }

    // MARK: - Unpriced block

    @Test func unpricedBlockAlone() throws {
        let text = render(perf([
            d1(session: "a", project: "alpha", turns: 12, exposure: nil, lead: false),
            d1(session: "b", project: "beta", turns: 30, exposure: nil, lead: false),
            d2(session: "a", project: "alpha", turns: 12, exposure: nil, lead: false),
        ], analyzed: 3, unpriced: 2))
        let empty = try position(of: "No priced pattern above the thresholds in 3 analyzed sessions.", in: text)
        let header = try position(
            of: "2 sessions use a model with no published rate. 2 of them matched a pattern, shown without a dollar figure.",
            in: text)
        let carry = try position(
            of: "beta, Oct 30, 60 turns above 200k: the context above 200k cost (no published rate). (also in 1 other unpriced session)",
            in: text)
        let rewrite = try position(
            of: "alpha, Oct 30: 3 times, context already in cache was written again, the largest part after a gap of over an hour (inferred). Write premium (no published rate).\n",
            in: text)
        #expect(empty < header && header < carry && carry < rewrite, "D1 before D2, after the empty state")
        let perfBlock = text[text.index(text.startIndex, offsetBy: empty)...]
        #expect(!perfBlock.contains("$"), "an unpriced block carries no dollar figure")
        #expect(text.contains(d1Action) && text.contains(d2IdleAction))
    }

    @Test func unpricedBlockAlongsideLeads() throws {
        let text = render(perf([
            d1(session: "p", project: "priced", exposure: 2.0),
            d3(session: "u", project: "unpriced", turns: 15, exposure: nil, lead: false),
        ], analyzed: 2, unpriced: 1))
        let lead = try position(of: "1. \(d1Action)", in: text)
        let header = try position(
            of: "1 session uses a model with no published rate. 1 of them matched a pattern, shown without a dollar figure.",
            in: text)
        let burst = try position(
            of: "unpriced, Oct 30: 2 search bursts. If what they added stayed in context, re-sending it cost (no published rate).\n",
            in: text)
        #expect(lead < header && header < burst)
        #expect(!text.contains("No priced pattern"))
        #expect(!text.contains("also in"))
    }

    @Test func unpricedLineComesFromTheSessionWithMostTurnsThenSessionID() {
        let text = render(perf([
            d1(session: "zeta", project: "z", turns: 40, exposure: nil, lead: false),
            d1(session: "alpha", project: "a", turns: 40, exposure: nil, lead: false),
            d1(session: "mid", project: "m", turns: 10, exposure: nil, lead: false),
        ], analyzed: 3, unpriced: 3))
        #expect(text.contains("a, Oct 30, 60 turns above 200k: the context above 200k cost (no published rate). (also in 2 other unpriced sessions)"))
        #expect(!text.contains("z, Oct 30") && !text.contains("m, Oct 30"))
    }

    @Test func unpricedD2ActionFollowsThatSessionsCause() {
        let text = render(perf([
            d2(session: "u", turns: 15, exposure: nil, lead: false, cause: .modelSwitch),
        ], analyzed: 1, unpriced: 1))
        #expect(text.contains("Pick the model before starting. A switch mid-session writes the cache again."))
        #expect(text.contains("the largest part after a model switch (inferred). Write premium (no published rate)."))
    }

    @Test func unpricedSessionsWithoutAMatchGetNoBlock() {
        let text = render(perf([d1(exposure: 1.0)], analyzed: 3, unpriced: 2))
        #expect(!text.contains("no published rate"))
    }

    @Test func perfBlockEndsWithTheRateFooter() throws {
        let text = render(perf([d1(exposure: 1.0)]))
        let line = try position(of: "1. ", in: text)
        let foot = try position(of: footer, in: text)
        let read = try position(of: "Read 0.0 MB from 0 files", in: text)
        #expect(line < foot && foot < read)
    }
}
