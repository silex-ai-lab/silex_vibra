import Foundation
import Testing
@testable import VibraCore

/// The D1-D3 rules, pinned by hand arithmetic.
///
/// Every expected value below is written as the plan's formula (rates per
/// million tokens, the documented fixture arithmetic), never read back from
/// the analyzer. The fixtures mirror the committed oracle's self-test cases.
struct PerfAnalyzerTests {
    // MARK: - Fixtures

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

    private var now: Date { date("2026-11-03T21:00:00Z") }
    private var window: ReportWindow { ReportWindow(now: now, days: 7, calendar: calendar) }

    /// Minutes after the fixture's day start, one day before `now`.
    /// Concatenates parts that each type-check alone; one long `+` chain of
    /// mapped ranges exceeds Swift 6.1's type-checking time limit.
    private func joined(_ parts: [UsageSample]...) -> [UsageSample] { parts.flatMap { $0 } }

    /// Whether a dollar figure is present and equals `expected` to 1e-9.
    private func near(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 1e-9
    }

    private func at(_ minutes: Double) -> Date { now.addingTimeInterval(-86_400 + minutes * 60) }

    /// Nine days before `now`: outside the seven-day window.
    private func outside() -> Date { now.addingTimeInterval(-9 * 86_400) }

    private func sample(
        _ model: String = "claude-sonnet-5",
        input: Int = 0,
        output: Int = 0,
        creation: Int = 0,
        read: Int = 0,
        tools: [String] = [],
        at time: Date? = nil,
        project: String? = "proj",
        sidechain: Bool = false
    ) -> UsageSample {
        UsageSample(
            timestamp: time,
            model: model,
            usage: TokenUsage(input: input, output: output, cacheCreation: creation, cacheRead: read),
            toolNames: tools,
            project: project,
            isSidechain: sidechain
        )
    }

    private func source(_ samples: [UsageSample], stem: String = "s", subagent: Bool = false) -> SourceSamples {
        SourceSamples(url: URL(fileURLWithPath: "/tmp/\(stem).jsonl"), isSubagent: subagent, samples: samples)
    }

    private func report(_ sources: [SourceSamples], thresholds: PerfThresholds = .defaults) -> PerfReport {
        PerfAnalyzer.report(claudeSources: sources, window: window, thresholds: thresholds)
    }

    private func name(_ finding: Suggestion.Finding) -> String {
        switch finding {
        case .contextCarry: "contextCarry"
        case .cacheRewrite: "cacheRewrite"
        case .explorationBurst: "explorationBurst"
        }
    }

    private func suggestion(_ r: PerfReport, _ stem: String = "s", _ detector: String) -> Suggestion? {
        r.suggestions.first { $0.sessionID == stem && name($0.finding) == detector }
    }

    private enum WrongFinding: Error { case expected }

    private func cacheRewrite(
        _ r: PerfReport,
        _ stem: String = "s"
    ) throws -> (events: Int, rewrittenTokens: Int, dominantCause: Suggestion.RewriteCause, suggestion: Suggestion) {
        let s = try #require(suggestion(r, stem, "cacheRewrite"))
        guard case let .cacheRewrite(events, tokens, cause) = s.finding else {
            Issue.record("expected a cacheRewrite, got \(s.finding)")
            throw WrongFinding.expected
        }
        return (events, tokens, cause, s)
    }

    private func contextCarry(
        _ r: PerfReport,
        _ stem: String = "s"
    ) throws -> (segments: Int, turnsAboveFloor: Int, peakContext: Int, floorTokens: Int, suggestion: Suggestion) {
        let s = try #require(suggestion(r, stem, "contextCarry"))
        guard case let .contextCarry(segments, above, peak, floor) = s.finding else {
            Issue.record("expected a contextCarry, got \(s.finding)")
            throw WrongFinding.expected
        }
        return (segments, above, peak, floor, s)
    }

    private func explorationBurst(
        _ r: PerfReport,
        _ stem: String = "s"
    ) throws -> (bursts: Int, burstTurns: Int, suggestion: Suggestion) {
        let s = try #require(suggestion(r, stem, "explorationBurst"))
        guard case let .explorationBurst(bursts, turns) = s.finding else {
            Issue.record("expected an explorationBurst, got \(s.finding)")
            throw WrongFinding.expected
        }
        return (bursts, turns, s)
    }

    // MARK: - D2: cache rewrites

    @Test func newContentIsNotD2() {
        // One cached turn, then 100k of newly written content, then reads: the
        // old prefix is read back every time, so nothing was rewritten.
        let samples = joined(
            [sample(creation: 10_000, at: at(0)), sample(creation: 100_000, read: 10_000, at: at(1))],
            (2..<10).map { sample(read: 110_000, at: at(Double($0))) }
        )
        let r = report([source(samples)])
        #expect(suggestion(r, "s", "cacheRewrite") == nil)
    }

    @Test func noCacheWritesMeansNoD2() {
        let samples = (0..<10).map { sample(input: 100_000, at: at(Double($0))) }
        let r = report([source(samples)])
        #expect(suggestion(r, "s", "cacheRewrite") == nil)
    }

    @Test func firstCacheFillAfterUncachedTurnsIsNotD2() {
        // The turn before the fill left nothing in cache, so the fill rewrote
        // nothing that had been cached.
        let samples = joined(
            (0..<9).map { sample(input: 100_000, at: at(Double($0))) },
            [sample(creation: 100_000, at: at(9))]
        )
        let r = report([source(samples)])
        #expect(suggestion(r, "s", "cacheRewrite") == nil)
    }

    @Test func expiredCacheAfterThreeHoursIsOneIdleOver1hEvent() throws {
        let samples = joined(
            (0..<5).map { sample(read: 100_000, at: at(Double($0))) },
            [sample(creation: 100_000, at: at(180))],
            (6..<10).map { sample(read: 100_000, at: at(180 + Double($0))) }
        )
        let r = report([source(samples)])
        let d2 = try cacheRewrite(r)
        #expect(d2.events == 1)
        #expect(d2.rewrittenTokens == 100_000)
        #expect(d2.dominantCause == .idleOver1h)
        let expected1: Double = 100_000 * (3.75 - 0.30) / 1_000_000
        #expect(near(d2.suggestion.exposureUSD, expected1))
    }

    @Test func d2InputUsesCacheCreationCap() throws {
        // The previous turn held 200k in cache; the current turn wrote only
        // 100k to cache, so the write premium can cover only those 100k.
        let samples = joined(
            [sample(input: 1, read: 200_000, at: at(0)), sample(input: 1_000, creation: 100_000, at: at(1))],
            (2..<10).map { sample(read: 100_000, at: at(Double($0))) }
        )
        let r = report([source(samples)])
        let d2 = try cacheRewrite(r)
        #expect(d2.events == 1)
        #expect(d2.rewrittenTokens == 100_000)
        #expect(d2.dominantCause == .other)
        let expected2: Double = 100_000 * (3.75 - 0.30) / 1_000_000
        #expect(near(d2.suggestion.exposureUSD, expected2))
    }

    @Test func unpricedD2DominantCauseIsModelSwitch() throws {
        // Two events of 200k each. The session is unpriced, so the cause is
        // ranked by rewritten tokens; the fixed order decides the form of the
        // suggestion, not a dollar figure.
        let samples = joined(
            (0..<4).map { sample(read: 200_000, at: at(Double($0))) },
            [sample("claude-fable-5-1", creation: 200_000, at: at(4)),
             sample("claude-fable-5-1", read: 200_000, at: at(5)),
             sample("claude-opus-5", creation: 200_000, at: at(180))],
            (7..<12).map { sample("claude-opus-5", read: 200_000, at: at(180 + Double($0))) }
        )
        let r = report([source(samples)])
        let d2 = try cacheRewrite(r)
        #expect(d2.events == 2)
        #expect(d2.rewrittenTokens == 400_000)
        #expect(d2.dominantCause == .modelSwitch)
        #expect(d2.suggestion.exposureUSD == nil)
        #expect(d2.suggestion.sessionValueUSD == nil)
        #expect(!d2.suggestion.isLead)
        #expect(r.analyzedSessions == 1)
        #expect(r.unpricedSessions == 1)
    }

    @Test func missingTimestampWithMatchingModelsIsOther() throws {
        // The gap to an undated previous turn is unknown; with the same model
        // the cause falls through to `other`.
        let samples = joined(
            [sample(read: 100_000, at: nil), sample(creation: 100_000, at: at(1))],
            (2..<11).map { sample(read: 100_000, at: at(Double($0))) }
        )
        let r = report([source(samples)])
        let d2 = try cacheRewrite(r)
        #expect(d2.events == 1)
        #expect(d2.dominantCause == .other)
        #expect(d2.suggestion.startedAt == at(1))
        #expect(d2.suggestion.turns == 10)
    }

    @Test func compactionIsNotARewrite() throws {
        // 12 turns at 229k, a post-compaction write of 60k with no reads, then
        // turns at 60k. The 60k write clears both D2 bars; only the segment
        // rule keeps it out.
        let samples = joined(
            (0..<12).map { sample(read: 229_000, at: at(Double($0))) },
            [sample(creation: 60_000, at: at(12))],
            (13..<21).map { sample(read: 60_000, at: at(Double($0))) }
        )
        let r = report([source(samples)])
        #expect(suggestion(r, "s", "cacheRewrite") == nil)
        #expect(r.analyzedSessions == 1)
    }

    // MARK: - D3: exploration bursts

    @Test func burstWithNoLaterTurnsHasZeroExposure() throws {
        // A burst that runs to the end of the session carried nothing into a
        // later turn.
        let samples = (0..<10).map {
            sample(read: $0.isMultiple(of: 2) ? 100_000 : 190_000, tools: ["Read"], at: at(Double($0)))
        }
        let r = report([source(samples)])
        let d3 = try explorationBurst(r)
        #expect(d3.bursts == 1)
        #expect(d3.burstTurns == 10)
        #expect(d3.suggestion.exposureUSD == 0)
        #expect(!d3.suggestion.isLead)
    }

    @Test func readBurstCarry() throws {
        // Three Read turns at 100k, then seven turns at 190k: the 90k the burst
        // added is carried by the six turns after `last + 1`.
        let samples = joined(
            (0..<3).map { sample(read: 100_000, tools: ["Read"], at: at(Double($0))) },
            [sample(read: 190_000, tools: ["Bash"], at: at(3))],
            (4..<10).map { sample(read: 190_000, tools: ["Bash"], at: at(Double($0))) }
        )
        let r = report([source(samples)])
        let d3 = try explorationBurst(r)
        #expect(d3.bursts == 1)
        #expect(d3.burstTurns == 3)
        let expected3: Double = 90_000 * 6 * 0.30 / 1_000_000
        #expect(near(d3.suggestion.exposureUSD, expected3))
    }

    @Test func droppedGrowthIsNotRecharged() throws {
        // The first burst's growth falls back to its start before the second
        // burst; only the second burst's 50k carry is charged.
        let samples = joined(
            (0..<2).map { sample(read: 100_000, at: at(Double($0))) },
            (2..<5).map { sample(read: 100_000, tools: ["Read"], at: at(Double($0))) },
            [sample(read: 150_000, at: at(5)), sample(read: 100_000, at: at(6))],
            (7..<10).map { sample(read: 100_000, tools: ["Grep"], at: at(Double($0))) },
            [sample(read: 150_000, at: at(10))],
            (11..<18).map { sample(read: 150_000, at: at(Double($0))) }
        )
        let r = report([source(samples)])
        let d3 = try explorationBurst(r)
        let expected4: Double = 7 * 50_000 * 0.30 / 1_000_000
        #expect(near(d3.suggestion.exposureUSD, expected4))
    }

    @Test func earlierBurstGrowthStillInContext() throws {
        // The first burst keeps 20k of its growth in context, the second adds
        // 70k; both are carried by the later turns.
        let samples = joined(
            (0..<2).map { sample(read: 100_000, at: at(Double($0))) },
            (2..<5).map { sample(read: 100_000, tools: ["Read"], at: at(Double($0))) },
            [sample(read: 150_000, at: at(5)), sample(read: 120_000, at: at(6))],
            (7..<10).map { sample(read: 120_000, tools: ["Grep"], at: at(Double($0))) },
            [sample(read: 170_000, at: at(10))],
            (11..<18).map { sample(read: 170_000, at: at(Double($0))) }
        )
        let r = report([source(samples)])
        let d3 = try explorationBurst(r)
        let expected5: Double = (5 * 20_000 + 7 * 70_000) * 0.30 / 1_000_000
        #expect(near(d3.suggestion.exposureUSD, expected5))
    }

    @Test func d3ExposureNeverExceedsSessionValue() throws {
        let samples = joined(
            (0..<3).map { sample(read: 100_000, tools: ["Read"], at: at(Double($0))) },
            [sample(read: 190_000, tools: ["Bash"], at: at(3))],
            (4..<10).map { sample(read: 190_000, tools: ["Bash"], at: at(Double($0))) }
        )
        let r = report([source(samples)])
        let d3 = try explorationBurst(r)
        #expect((d3.suggestion.exposureUSD ?? .nan) <= (d3.suggestion.sessionValueUSD ?? .nan))
    }

    @Test func mixedModelD3PricesAtEachTurnsRate() throws {
        // The burst added 90k; turns 4-6 are opus and 7-9 are sonnet, so the
        // carry is priced at each turn's own cache-read rate.
        let samples = joined(
            (0..<3).map { sample(read: 100_000, tools: ["Read"], at: at(Double($0))) },
            (3..<7).map { sample("claude-opus-5", read: 190_000, at: at(Double($0))) },
            (7..<10).map { sample(read: 190_000, at: at(Double($0))) }
        )
        let r = report([source(samples)])
        let d3 = try explorationBurst(r)
        #expect(d3.bursts == 1)
        #expect(d3.burstTurns == 3)
        let expected6: Double = (3 * 90_000 * 1.50 / 1_000_000 + 3 * 90_000 * 0.30 / 1_000_000)
        #expect(near(d3.suggestion.exposureUSD, expected6))
        #expect(d3.suggestion.isLead)
    }

    // MARK: - Turns and segments

    @Test func outputOnlyRecordIsNotATurn() {
        let samples = joined(
            (0..<9).map { sample(read: 100_000, at: at(Double($0))) },
            [sample(output: 500, at: at(9))]
        )
        let r = report([source(samples)])
        #expect(r.analyzedSessions == 0)
        #expect(r.skippedSmallSessions == 1)
        #expect(r.suggestions.isEmpty)
    }

    @Test func inlineSidechainRecordIsNotATurnAndDoesNotSplitSegment() throws {
        // 61 main-thread turns at 250k around one sidechain record at 5k. If
        // the sidechain record were a turn it would be a compaction boundary.
        let samples = joined(
            (0..<60).map { sample(read: 250_000, at: at(Double($0))) },
            [sample(read: 5_000, at: at(60), sidechain: true)],
            [sample(read: 250_000, at: at(61))]
        )
        let r = report([source(samples)])
        let d1 = try contextCarry(r)
        #expect(d1.segments == 1)
        #expect(d1.turnsAboveFloor == 61)
        #expect(d1.suggestion.turns == 61)
    }

    @Test func burstTurnsCountsInWindowTurnsOnly() throws {
        // Two Read/Grep turns before the window, one Glob inside it: the burst
        // has one in-window turn.
        let samples = joined(
            [sample(read: 100_000, tools: ["Read"], at: outside()),
             sample(read: 100_000, tools: ["Grep"], at: outside().addingTimeInterval(60)),
             sample(read: 100_000, tools: ["Glob"], at: at(0))],
            (1..<11).map { sample(read: 100_000, at: at(Double($0))) }
        )
        let r = report([source(samples)])
        let d3 = try explorationBurst(r)
        #expect(d3.bursts == 1)
        #expect(d3.burstTurns == 1)
    }

    @Test func repeatedBashIsNotD3() {
        let samples = (0..<10).map { sample(read: 100_000, tools: ["Bash"], at: at(Double($0))) }
        let r = report([source(samples)])
        #expect(suggestion(r, "s", "explorationBurst") == nil)
    }

    // MARK: - D1: context carry

    @Test func d1CarryAt250kIsALead() throws {
        let samples = (0..<60).map { sample(read: 250_000, at: at(Double($0))) }
        let r = report([source(samples)])
        let d1 = try contextCarry(r)
        #expect(d1.segments == 1)
        #expect(d1.turnsAboveFloor == 60)
        #expect(d1.peakContext == 250_000)
        #expect(d1.floorTokens == 200_000)
        let expected7: Double = 60 * (250_000 - 200_000) * 0.30 / 1_000_000
        #expect(near(d1.suggestion.exposureUSD, expected7))
        let expected8: Double = 60 * 250_000 * 0.30 / 1_000_000
        #expect(near(d1.suggestion.sessionValueUSD, expected8))
        #expect(d1.suggestion.isLead)
    }

    @Test func d1PricesAboveFloorByBand() throws {
        // Positions above the 200k floor are the 40k uncached input (input
        // rate) plus 10k of the 60k cache write (write rate).
        let samples = (0..<60).map {
            sample(input: 40_000, creation: 60_000, read: 150_000, at: at(Double($0)))
        }
        let r = report([source(samples)])
        let d1 = try contextCarry(r)
        #expect(d1.turnsAboveFloor == 60)
        let expected9: Double = 60 * (10_000 * 3.75 + 40_000 * 3.0) / 1_000_000
        #expect(near(d1.suggestion.exposureUSD, expected9))
    }

    @Test func leadNeedsShareOfSessionValue() throws {
        // 0.75 dollars is above leadMinUSD, but only 2.8% of the session's
        // 26.55 dollars, so it is not a lead.
        let samples = joined(
            (0..<400).map { sample(read: 190_000, at: at(Double($0))) },
            (400..<450).map { sample(read: 250_000, at: at(Double($0))) }
        )
        let r = report([source(samples)])
        let d1 = try contextCarry(r)
        let expected10: Double = 50 * (250_000 - 200_000) * 0.30 / 1_000_000
        #expect(near(d1.suggestion.exposureUSD, expected10))
        let expected11: Double = (400 * 190_000 + 50 * 250_000) * 0.30 / 1_000_000
        #expect(near(d1.suggestion.sessionValueUSD, expected11))
        #expect(!d1.suggestion.isLead)
    }

    @Test func zeroExposureIsNeverALead() throws {
        // With both lead floors at zero, a zero exposure is still not a lead.
        let thresholds = PerfThresholds(
            minTurns: 10,
            d1MinTurnsAboveFloor: 50,
            d1CarryFloorTokens: 200_000,
            d2MinRewriteTokens: 30_000,
            d3MinBurstTurns: 3,
            leadMinUSD: 0,
            leadMinShare: 0
        )
        let samples = (0..<10).map {
            sample(read: $0.isMultiple(of: 2) ? 100_000 : 190_000, tools: ["Read"], at: at(Double($0)))
        }
        let r = report([source(samples)], thresholds: thresholds)
        let d3 = try explorationBurst(r)
        #expect(d3.suggestion.exposureUSD == 0)
        #expect(!d3.suggestion.isLead)
    }

    // MARK: - Pricing

    @Test func unpricedInWindowTurnGivesNilFigures() throws {
        let inWindow = joined(
            (0..<59).map { sample(read: 250_000, at: at(Double($0))) },
            [sample("claude-fable-5-1", read: 250_000, at: at(59))]
        )
        let outOfWindow = joined(
            [sample("claude-fable-5-1", read: 250_000, at: outside())],
            (0..<60).map { sample(read: 250_000, at: at(Double($0))) }
        )
        let r = report([source(inWindow, stem: "a"), source(outOfWindow, stem: "b")])
        let a = try contextCarry(r, "a")
        let b = try contextCarry(r, "b")
        #expect(a.suggestion.exposureUSD == nil)
        #expect(a.suggestion.sessionValueUSD == nil)
        #expect(!a.suggestion.isLead)
        #expect(b.suggestion.exposureUSD != nil)
        #expect(b.suggestion.isLead)
        #expect(r.analyzedSessions == 2)
        #expect(r.unpricedSessions == 1)
    }

    @Test func zeroUsageSyntheticIsNeitherBoundaryNorModelSwitch() throws {
        // The <synthetic> record carries no context, so it is not a turn; the
        // following 3-hour gap makes the rewrite `idleOver1h`, not a model
        // switch, and does not start a new segment.
        let samples = joined(
            (0..<5).map { sample(read: 200_000, at: at(Double($0))) },
            [sample("<synthetic>", at: at(5))],
            [sample(creation: 200_000, at: at(180))],
            (7..<12).map { sample(read: 200_000, at: at(180 + Double($0))) }
        )
        let r = report([source(samples)])
        let d2 = try cacheRewrite(r)
        #expect(d2.events == 1)
        #expect(d2.rewrittenTokens == 200_000)
        #expect(d2.dominantCause == .idleOver1h)
        let expected12: Double = 200_000 * (3.75 - 0.30) / 1_000_000
        #expect(near(d2.suggestion.exposureUSD, expected12))
    }

    @Test func projectComesFromTurns() throws {
        // The zero-usage record's project must not win: only turns count.
        let samples = joined(
            [sample("<synthetic>", at: at(0), project: "zero-usage-project")],
            (1..<61).map { sample(read: 250_000, at: at(Double($0)), project: "proj") }
        )
        let r = report([source(samples)])
        let d1 = try contextCarry(r)
        #expect(d1.suggestion.project == "proj")
    }

    @Test func startedAtIsFirstInWindowTurn() throws {
        let samples = joined(
            [sample(read: 250_000, at: outside())],
            (0..<60).map { sample(read: 250_000, at: at(Double($0))) }
        )
        let r = report([source(samples)])
        let d1 = try contextCarry(r)
        #expect(d1.suggestion.startedAt == at(0))
    }

    // MARK: - Session counting

    @Test func smallSessionCountsAsSkipped() {
        let samples = (0..<4).map { sample(read: 100_000, at: at(Double($0))) }
        let r = report([source(samples)])
        #expect(r.analyzedSessions == 0)
        #expect(r.skippedSmallSessions == 1)
        #expect(r.suggestions.isEmpty)
    }

    @Test func subagentSourceIsNeitherAnalyzedNorSkipped() {
        let samples = (0..<60).map { sample(read: 250_000, at: at(Double($0))) }
        let r = report([source(samples, stem: "sub", subagent: true)])
        #expect(r.analyzedSessions == 0)
        #expect(r.skippedSmallSessions == 0)
        #expect(r.suggestions.isEmpty)
    }

    @Test func allSidechainSourceHasNoTurnsAndIsCountedAsSkipped() {
        let samples = (0..<60).map { sample(read: 250_000, at: at(Double($0)), sidechain: true) }
        let r = report([source(samples, stem: "side")])
        #expect(r.analyzedSessions == 0)
        #expect(r.skippedSmallSessions == 1)
        #expect(r.suggestions.isEmpty)
    }

    // MARK: - Thresholds

    @Test func thresholdsLoadClampsRoundsAndFallsBack() {
        let store = DictionarySettingsStore([
            "perf.minTurns": 10.4,                 // rounds to 10
            "perf.d1MinTurnsAboveFloor": 2,        // clamps to 5
            "perf.d1CarryFloorTokens": "200000",   // a numeric string
            "perf.d2MinRewriteTokens": "abc",      // non-numeric: default 30_000
            "perf.d3MinBurstTurns": 51,            // clamps to 50
            "perf.leadMinUSD": -5,                 // clamps to 0
            "perf.leadMinShare": 1.5,              // clamps to 1
        ])
        let t = PerfThresholds.load(from: store)
        #expect(t.minTurns == 10)
        #expect(t.d1MinTurnsAboveFloor == 5)
        #expect(t.d1CarryFloorTokens == 200_000)
        #expect(t.d2MinRewriteTokens == 30_000)
        #expect(t.d3MinBurstTurns == 50)
        #expect(t.leadMinUSD == 0)
        #expect(t.leadMinShare == 1)

        // A fractional integer rounds to the nearest integer.
        let up = PerfThresholds.load(from: DictionarySettingsStore(["perf.minTurns": 10.6]))
        #expect(up.minTurns == 11)

        // Nothing stored is the shipped default.
        #expect(PerfThresholds.load(from: DictionarySettingsStore()) == .defaults)
    }
}
