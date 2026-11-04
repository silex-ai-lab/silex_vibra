import Foundation

/// The one text renderer of the usage report, shared by the report window and
/// `--report`. Every string the user reads about a perf suggestion is built
/// here; `Suggestion` carries typed evidence only.
///
/// Wording is deliberate. Every dollar figure is an estimate at Vibra's table
/// rates (on a subscription you pay a flat fee), so it is never presented as a
/// bill, a quota or a saving. Unpriced and
/// undated tokens get their own lines rather than vanishing into a total that
/// would then look authoritative and be wrong.
public enum ReportText {
    public static func render(usage: UsageReport, perf: PerfReport, read: ReadStats, seconds: Double) -> String {
        var out = usageSection(usage)
        out += "\nPERFORMANCE — Claude Code sessions\n"
        out += perfSection(perf, days: usage.windowDays)
        out += "\n———\n"
        out += "Estimated API-equivalent value, not a bill. On a\n"
        out += "subscription you pay a flat fee; this is what the same\n"
        out += "usage would cost at published API rates.\n"
        out += "Computed locally. Nothing left this machine.\n"
        out += String(format: "\nRead %.1f MB from %d files in %.1fs.\n",
                      Double(read.bytes) / 1_048_576, read.files, seconds)
        return out
    }

    /// The evidence of one suggestion: project, local date, the finding's
    /// numbers and its figure, or "no published rate" when the session is
    /// unpriced.
    public static func evidenceLine(for suggestion: Suggestion) -> String {
        let project = suggestion.project.isEmpty ? "unknown project" : suggestion.project
        let date = suggestion.startedAt.map(localDate.string(from:)) ?? "unknown date"
        let figure = suggestion.exposureUSD.map { String(format: "about $%.2f", $0) } ?? "(no published rate)"
        switch suggestion.finding {
        case let .contextCarry(_, turnsAboveFloor, _, floorTokens):
            let floor = tokens(floorTokens)
            return "\(project), \(date), \(turnsAboveFloor) turns above \(floor): the context above \(floor) cost \(figure)."
        case let .cacheRewrite(events, _, cause):
            let after = switch cause {
            case .modelSwitch: "after a model switch"
            case .idleOver1h: "after a gap of over an hour"
            case .idleOver5m: "after a gap of over 5 minutes"
            case .other: "with no model switch or long gap"
            }
            return "\(project), \(date): \(count(events, "time")), context already in cache was written again, "
                + "the largest part \(after) (inferred). Write premium \(figure)."
        case let .explorationBurst(bursts, _):
            return "\(project), \(date): \(count(bursts, "search burst")). "
                + "If what they added stayed in context, re-sending it cost \(figure)."
        }
    }

    /// What to do about one suggestion. D2's advice follows its dominant cause.
    static func action(for suggestion: Suggestion) -> String {
        switch suggestion.finding {
        case .contextCarry:
            return "Run /compact inside long tasks and /clear between tasks. "
                + "Split unrelated work into separate sessions."
        case let .cacheRewrite(_, _, cause):
            switch cause {
            case .modelSwitch:
                return "Pick the model before starting. A switch mid-session writes the cache again."
            case .idleOver1h, .idleOver5m:
                return "Before a long break, consider /compact, or /clear if the task is done. "
                    + "After the cache expires, much of the context is written to cache again."
            case .other:
                return "Large parts of an already-cached prompt were written again. "
                    + "Check /context for tools or files that change between turns."
            }
        case .explorationBurst:
            return "@-mention the files you mean, or hand broad searches to a subagent "
                + "so only its conclusion enters this session."
        }
    }

    // MARK: - Perf block

    /// The three detectors in their fixed order. `caseName` is the `Finding`
    /// case name, the tie-break when two lines have equal exposure.
    private enum Detector: CaseIterable {
        case contextCarry, cacheRewrite, explorationBurst

        init(_ finding: Suggestion.Finding) {
            switch finding {
            case .contextCarry: self = .contextCarry
            case .cacheRewrite: self = .cacheRewrite
            case .explorationBurst: self = .explorationBurst
            }
        }

        var caseName: String {
            switch self {
            case .contextCarry: "contextCarry"
            case .cacheRewrite: "cacheRewrite"
            case .explorationBurst: "explorationBurst"
            }
        }
    }

    private static func perfSection(_ perf: PerfReport, days: Int) -> String {
        var out = ""
        let leads = perf.suggestions.filter(\.isLead)
        var lines: [(exposure: Double, detector: Detector, evidence: Suggestion, others: Int)] = []
        for detector in Detector.allCases {
            let ofDetector = leads
                .filter { Detector($0.finding) == detector }
                .sorted { ($0.exposureUSD ?? 0, $1.sessionID) > ($1.exposureUSD ?? 0, $0.sessionID) }
            guard let best = ofDetector.first else { continue }
            lines.append((best.exposureUSD ?? 0, detector, best, ofDetector.count - 1))
        }
        lines.sort { ($0.exposure, $1.detector.caseName) > ($1.exposure, $0.detector.caseName) }

        if lines.isEmpty {
            if perf.analyzedSessions == 0 && perf.skippedSmallSessions == 0 {
                out += "No Claude Code sessions in the last \(days) days.\n"
            } else if perf.analyzedSessions == 0 {
                out += "No Claude Code session in the last \(days) days had enough turns to analyze.\n"
            } else {
                out += "No priced pattern above the thresholds in \(count(perf.analyzedSessions, "analyzed session")).\n"
            }
        }
        for (number, line) in lines.enumerated() {
            out += "\(number + 1). \(action(for: line.evidence))\n"
            out += "   \(evidenceLine(for: line.evidence))"
            if line.others > 0 { out += " (also in \(count(line.others, "other session")))" }
            out += "\n"
        }

        let unpriced = perf.suggestions.filter { $0.exposureUSD == nil }
        let matched = Set(unpriced.map(\.sessionID)).count
        if matched > 0 {
            out += "\(count(perf.unpricedSessions, "session")) use\(perf.unpricedSessions == 1 ? "s" : "") a model "
                + "with no published rate. \(matched) of them matched a pattern, shown without a dollar figure.\n"
            for detector in Detector.allCases {
                let ofDetector = unpriced
                    .filter { Detector($0.finding) == detector }
                    .sorted { ($0.turns, $1.sessionID) > ($1.turns, $0.sessionID) }
                guard let pick = ofDetector.first else { continue }
                out += "   \(action(for: pick))\n"
                out += "   \(evidenceLine(for: pick))"
                if ofDetector.count > 1 { out += " (also in \(count(ofDetector.count - 1, "other unpriced session")))" }
                out += "\n"
            }
        }

        out += "Estimated API-equivalent value at Vibra's table rates (last verified 2026-09-19); "
            + "1-hour cache writes use the single write rate. Not a bill.\n"
        return out
    }

    // MARK: - Usage section

    private static func usageSection(_ r: UsageReport) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        // String(format:) ignores width specifiers for %@, so columns are
        // padded by hand. Without this the figures come out ragged and the
        // table is much harder to scan than a table should be.
        func padRight(_ s: String, _ width: Int) -> String {
            s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
        }
        func padLeft(_ s: String, _ width: Int) -> String {
            s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
        }
        func row(_ label: String, _ usage: TokenUsage, _ value: Double, _ unpriced: Int) -> String {
            var line = "  " + padRight(label, 16)
                + padLeft(tok(usage.total), 8) + " tok"
                + padLeft(String(format: "~$%.2f", value), 12)
            if unpriced > 0 { line += "   +\(tok(unpriced)) unpriced" }
            return line + "\n"
        }

        var out = "USAGE — last \(r.windowDays) days (rolling)\n"
        out += "\(df.string(from: r.windowStart)) – \(df.string(from: r.generatedAt))\n\n"

        out += "BY DAY\n"
        if r.days.isEmpty { out += "  (no dated usage in this window)\n" }
        for d in r.days {
            out += row(df.string(from: d.day), d.usage, d.estimatedValue, d.unpricedTokens)
        }

        out += "\nBY AGENT\n"
        for a in r.agents {
            out += row(a.agent.displayName, a.usage, a.estimatedValue, a.unpricedTokens)
        }

        out += "\n" + "  " + padRight("TOTAL", 16)
            + padLeft(tok(r.total.total), 8) + " tok"
            + padLeft(String(format: "~$%.2f", r.estimatedValue), 12) + "\n"

        if r.unpricedTokens > 0 {
            out += "  \(tok(r.unpricedTokens)) tokens have no published rate and\n"
            out += "  are excluded from the estimate above.\n"
        }
        if r.undated.total > 0 {
            out += "  \(tok(r.undated.total)) tokens could not be dated: that source\n"
            out += "  records per-session totals with no timestamps.\n"
        }
        return out
    }

    // MARK: - Formatting

    private static let localDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()

    /// Usage totals, rounded: "1.2M", "62k", "900".
    private static func tok(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6)
                       : (n >= 1_000 ? "\(n / 1_000)k" : "\(n)")
    }

    /// A threshold, exactly: "200k", "1M", or the digits when it is neither.
    private static func tokens(_ n: Int) -> String {
        if n % 1_000_000 == 0 { return "\(n / 1_000_000)M" }
        if n % 1_000 == 0 { return "\(n / 1_000)k" }
        return "\(n)"
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
