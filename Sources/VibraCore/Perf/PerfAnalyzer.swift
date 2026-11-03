import Foundation

/// The D1-D3 detectors: a pure function from one report read's final samples to
/// the report's typed suggestions.
///
/// The rules are the plan's, and `tools/perf-oracle/perf_oracle.py` implements
/// them in Python; the code gate compares the two, so a change here must be
/// made there too. The analyzer only sees `UsageSample` values, never message
/// text, tool inputs or tool results.
public struct PerfAnalyzer: Sendable {
    /// A turn explored with Read, Grep and Glob only.
    private static let explore: Set<String> = ["Read", "Grep", "Glob"]
    /// A prompt at least this long that drops below half its size was compacted.
    private static let compactionMinContext = 50_000
    /// The share of the previously-held cache a D2 rewrite must cover.
    private static let d2MissedShare = 0.5

    /// Analyzes every non-subagent Claude Code source in the window.
    ///
    /// `claudeSources` is `ReportInput.sources[.claudeCode]`. Subagent sources
    /// are skipped without being counted: the advice is about the main thread,
    /// while the Usage Report's total still includes their usage.
    public static func report(
        claudeSources: [SourceSamples],
        window: ReportWindow,
        thresholds: PerfThresholds
    ) -> PerfReport {
        var analyzed = 0
        var unpriced = 0
        var skipped = 0
        var suggestions: [Suggestion] = []

        for source in claudeSources {
            if source.isSubagent { continue }
            guard let result = analyze(source: source, window: window, thresholds: thresholds) else {
                skipped += 1
                continue
            }
            analyzed += 1
            if !result.priced { unpriced += 1 }
            suggestions += result.suggestions
        }

        suggestions.sort {
            let left = detectorName($0.finding)
            let right = detectorName($1.finding)
            return left == right ? $0.sessionID < $1.sessionID : left < right
        }
        return PerfReport(
            thresholds: thresholds,
            analyzedSessions: analyzed,
            unpricedSessions: unpriced,
            skippedSmallSessions: skipped,
            suggestions: suggestions
        )
    }

    // MARK: - One session

    private struct SessionResult {
        let priced: Bool
        let suggestions: [Suggestion]
    }

    private struct Rewrite {
        let cause: Suggestion.RewriteCause
        let missed: Int
        let rate: ModelRate?
    }

    private static func analyze(
        source: SourceSamples,
        window: ReportWindow,
        thresholds: PerfThresholds
    ) -> SessionResult? {
        // A turn is a final sample that carries context and is not an inline
        // subagent record. Zero-usage and output-only records are not turns,
        // and a sidechain record belongs to a subagent's context, not this one.
        let turns = source.samples.filter { !$0.isSidechain && context($0) > 0 }
        let inWindow = turns.map { $0.timestamp.map(window.contains) ?? false }
        let inWindowCount = inWindow.filter { $0 }.count
        guard inWindowCount >= thresholds.minTurns else { return nil }

        // All-or-nothing pricing: a partly priced session value would compare a
        // priced exposure with a denominator that is not the whole session.
        var priced = true
        var sessionValue = 0.0
        for index in turns.indices where inWindow[index] {
            guard let rate = CostTable.rate(for: turns[index].model) else {
                priced = false
                break
            }
            sessionValue += UsageAggregator.cost(turns[index].usage, rate: rate)
        }

        // Detection runs over every turn; the window only decides what is
        // counted and priced, so a segment that starts before the window still
        // has its boundary in place.
        var segmentIDs = [Int](repeating: 0, count: turns.count)
        var segment = 0
        for index in turns.indices {
            if index > 0,
               context(turns[index - 1]) >= compactionMinContext,
               Double(context(turns[index])) < 0.5 * Double(context(turns[index - 1])) {
                segment += 1
            }
            segmentIDs[index] = segment
        }

        let project = turns.first { !($0.project ?? "").isEmpty }?.project ?? ""
        let startedAt = turns.indices.first(where: { inWindow[$0] }).flatMap { turns[$0].timestamp }
        let stem = source.url.deletingPathExtension().lastPathComponent
        var suggestions: [Suggestion] = []

        func make(_ finding: Suggestion.Finding, exposure: Double?) -> Suggestion {
            var isLead = false
            if priced, let exposure, sessionValue > 0, exposure > 0,
               exposure >= thresholds.leadMinUSD,
               exposure >= thresholds.leadMinShare * sessionValue {
                isLead = true
            }
            return Suggestion(
                sessionID: stem,
                project: project,
                startedAt: startedAt,
                turns: inWindowCount,
                finding: finding,
                exposureUSD: priced ? exposure : nil,
                sessionValueUSD: priced ? sessionValue : nil,
                isLead: isLead
            )
        }

        // D1: context carried above a floor, priced by the band each above-floor
        // token falls in. The API lays a prompt out as the cached prefix, then
        // the newly written cache, then the uncached input.
        let floor = thresholds.d1CarryFloorTokens
        var qualifyingSegments = 0
        var turnsAboveFloor = 0
        var peakContext = 0
        var carry = 0.0
        for id in Set(segmentIDs).sorted() {
            let indices = turns.indices.filter { segmentIDs[$0] == id && inWindow[$0] }
            let above = indices.filter { context(turns[$0]) > floor }
            guard above.count >= thresholds.d1MinTurnsAboveFloor else { continue }
            qualifyingSegments += 1
            turnsAboveFloor += above.count
            peakContext = max(peakContext, indices.map { context(turns[$0]) }.max() ?? 0)
            if priced {
                carry += above.reduce(0) { $0 + aboveFloorUSD(turns[$1], floor: floor) }
            }
        }
        if qualifyingSegments > 0 {
            suggestions.append(make(
                .contextCarry(
                    segments: qualifyingSegments,
                    turnsAboveFloor: turnsAboveFloor,
                    peakContext: peakContext,
                    floorTokens: floor
                ),
                exposure: priced ? carry : nil
            ))
        }

        // D2: the previous turn left `held` tokens in cache; this turn rewrote
        // part of that prefix instead of reading it back. Capped by the tokens
        // this turn actually wrote to cache — the most it could have paid a
        // write premium on — so newly added content never counts.
        var rewrites: [Rewrite] = []
        if turns.count > 1 {
            for index in 1..<turns.count {
                guard segmentIDs[index] == segmentIDs[index - 1], inWindow[index] else { continue }
                let previous = turns[index - 1]
                let turn = turns[index]
                let held = previous.usage.cacheCreation + previous.usage.cacheRead
                let base = min(held, context(turn))
                let missed = min(turn.usage.cacheCreation, max(0, base - turn.usage.cacheRead))
                guard missed >= thresholds.d2MinRewriteTokens,
                      Double(missed) >= d2MissedShare * Double(base) else { continue }

                let gap: TimeInterval? = {
                    guard let current = turn.timestamp, let prior = previous.timestamp else { return nil }
                    return current.timeIntervalSince(prior)
                }()
                let cause: Suggestion.RewriteCause
                if turn.model != previous.model {
                    cause = .modelSwitch
                } else if let gap, gap > 3_600 {
                    cause = .idleOver1h
                } else if let gap, gap > 300 {
                    cause = .idleOver5m
                } else {
                    cause = .other
                }
                rewrites.append(Rewrite(cause: cause, missed: missed, rate: CostTable.rate(for: turn.model)))
            }
        }
        if !rewrites.isEmpty {
            var byCause: [Suggestion.RewriteCause: Int] = [:]
            for rewrite in rewrites { byCause[rewrite.cause, default: 0] += rewrite.missed }
            // Most rewritten tokens; ties go to the earlier cause in this fixed
            // order, so an unpriced session needs no dollar ranking.
            let order: [Suggestion.RewriteCause] = [.modelSwitch, .idleOver1h, .idleOver5m, .other]
            var dominant = order[0]
            var most = -1
            for cause in order {
                let tokens = byCause[cause] ?? 0
                if tokens > most {
                    most = tokens
                    dominant = cause
                }
            }
            var exposure: Double?
            if priced {
                exposure = rewrites.reduce(0.0) { sum, rewrite in
                    guard let rate = rewrite.rate else { return sum }
                    return sum + Double(rewrite.missed) * (rate.cacheCreation - rate.cacheRead) / 1_000_000
                }
            }
            suggestions.append(make(
                .cacheRewrite(
                    events: rewrites.count,
                    rewrittenTokens: rewrites.reduce(0) { $0 + $1.missed },
                    dominantCause: dominant
                ),
                exposure: exposure
            ))
        }

        // D3: exploration bursts. What a burst added is carried by every later
        // turn until context falls back toward where the burst started; the
        // running minimum drops that carry as soon as it is no longer visible.
        var bursts: [[Int]] = []
        var run: [Int] = []
        for index in turns.indices {
            let qualifies = !turns[index].toolNames.isEmpty
                && Set(turns[index].toolNames).isSubset(of: explore)
            if qualifies, run.isEmpty || segmentIDs[index] == segmentIDs[run.last!] {
                run.append(index)
                continue
            }
            if run.count >= thresholds.d3MinBurstTurns { bursts.append(run) }
            run = qualifies ? [index] : []
        }
        if run.count >= thresholds.d3MinBurstTurns { bursts.append(run) }
        bursts = bursts.filter { burst in burst.contains(where: { inWindow[$0] }) }

        if !bursts.isEmpty {
            var carried: [Int: Int] = [:]
            for burst in bursts {
                guard let first = burst.first, let last = burst.last else { continue }
                // `last + 1` is the first send of the last burst turn's results;
                // it is billed as a cache write, so the carry starts after it.
                let top = last + 1 < turns.count && segmentIDs[last + 1] == segmentIDs[first]
                    ? last + 1
                    : last
                var still = max(0, context(turns[top]) - context(turns[first]))
                var index = top + 1
                while index < turns.count {
                    if segmentIDs[index] != segmentIDs[first] { break }
                    still = max(0, min(still, context(turns[index]) - context(turns[first])))
                    if index >= last + 2, inWindow[index] { carried[index, default: 0] += still }
                    index += 1
                }
            }
            var exposure: Double?
            if priced {
                exposure = carried.reduce(0.0) { sum, entry in
                    guard let rate = CostTable.rate(for: turns[entry.key].model) else { return sum }
                    return sum + Double(entry.value) * rate.cacheRead / 1_000_000
                }
            }
            let burstTurns = bursts.reduce(0) { $0 + $1.filter { inWindow[$0] }.count }
            suggestions.append(make(
                .explorationBurst(bursts: bursts.count, burstTurns: burstTurns),
                exposure: exposure
            ))
        }

        return SessionResult(priced: priced, suggestions: suggestions)
    }

    // MARK: - Helpers

    /// The prompt size this turn sent: cached prefix, new cache writes and
    /// uncached input. Output tokens never enter it.
    private static func context(_ sample: UsageSample) -> Int {
        sample.usage.input + sample.usage.cacheCreation + sample.usage.cacheRead
    }

    /// The price of the prompt tokens at positions `floor...context`, where the
    /// prompt is laid out as the cached prefix, the new cache writes, then the
    /// uncached input. Each band is priced at its own rate.
    private static func aboveFloorUSD(_ sample: UsageSample, floor: Int) -> Double {
        guard let rate = CostTable.rate(for: sample.model) else { return 0 }
        let read = sample.usage.cacheRead
        let write = sample.usage.cacheCreation
        let total = context(sample)
        func overlap(_ low: Int, _ high: Int) -> Int {
            max(0, min(high, total) - max(low, floor))
        }
        let dollars = Double(overlap(0, read)) * rate.cacheRead
            + Double(overlap(read, read + write)) * rate.cacheCreation
            + Double(overlap(read + write, total)) * rate.input
        return dollars / 1_000_000
    }

    /// The `Finding` case name, which is also the oracle's detector name.
    private static func detectorName(_ finding: Suggestion.Finding) -> String {
        switch finding {
        case .contextCarry: "contextCarry"
        case .cacheRewrite: "cacheRewrite"
        case .explorationBurst: "explorationBurst"
        }
    }
}
