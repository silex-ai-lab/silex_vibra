import Foundation

/// `Vibra --wait-stats`: how long sessions waited on the human, per agent.
///
/// Counts and durations only - never an id, a path, a cwd or text. Eligibility,
/// the half-open window, ordinals, the 2 h cap and the seven output groups are
/// the plan's "Window and arithmetic" and "Output of `Vibra --wait-stats`",
/// byte for byte: the independent Python oracle prints the same text.
public enum WaitStats {
    /// The attention-decay cap: no wait counts longer than two hours.
    fileprivate static let capMs: EpochMs = 7_200_000

    /// Only the two agents with wait extractors print, so no other adapter can
    /// introduce a line.
    private static let agents: [AgentKind] = [.claudeCode, .codex]
    fileprivate static let buckets = ["1", "2-3", "4-7", "8+"]
    private static let groupCount = 7

    public static func format(
        _ rows: [(agent: AgentKind, fold: WaitFold)], window: WaitWindow
    ) -> String {
        var groups = [[String]](repeating: [], count: groupCount)

        for agent in agents {
            var report = AgentReport()
            for row in rows where row.agent == agent {
                report.add(row.fold, window: window)
            }
            guard report.sessions > 0 else { continue }
            report.appendLines(for: agent, into: &groups)
        }

        var out = ""
        for group in groups {
            let lines = group.sorted { key(of: $0).utf8.lexicographicallyPrecedes(key(of: $1).utf8) }
            for line in lines {
                out += line
                out += "\n"
            }
        }
        return out
    }

    /// A line's key: the text before the first ` p25=` or ` n=`, compared
    /// byte-wise within a group.
    private static func key(of line: String) -> String {
        var cut = line.endIndex
        for marker in [" p25=", " n="] {
            if let found = line.range(of: marker), found.lowerBound < cut { cut = found.lowerBound }
        }
        return String(line[..<cut])
    }

    // MARK: - Arithmetic

    /// Type-7 quantiles of `values` in whole `unit`s, floored, as one
    /// `p25=… p50=… p75=…` run. Values are integer ms, so the arithmetic below
    /// is exact: with p = k/4, h = k(n−1)/4, so the quantile is
    /// (4·x[f] + m·(x[f+1] − x[f])) / 4 with f and m the quotient and remainder
    /// of k(n−1) by 4.
    fileprivate static func quantileValues(_ values: [EpochMs], unit: EpochMs) -> String {
        let sorted = values.sorted()
        let p25 = quantile(sorted, quartile: 1, unit: unit)
        let p50 = quantile(sorted, quartile: 2, unit: unit)
        let p75 = quantile(sorted, quartile: 3, unit: unit)
        return "p25=\(p25) p50=\(p50) p75=\(p75)"
    }

    private static func quantile(_ sorted: [EpochMs], quartile k: Int, unit: EpochMs) -> EpochMs {
        let n: Int = sorted.count
        let h: Int = k * (n - 1)
        let f: Int = h / 4
        let m: Int = h % 4
        let delta: EpochMs = f + 1 < n ? sorted[f + 1] - sorted[f] : 0
        let numerator: EpochMs = 4 * sorted[f] + EpochMs(m) * delta
        // Integer division floors here: every term is non-negative.
        return numerator / (4 * unit)
    }

    /// Ordinal of each question and approval wait, by its position in the fold:
    /// numbered from 1 across both kinds over the WHOLE transcript, stably by
    /// (start, end) then file order, so a window does not renumber.
    fileprivate static func ordinals(_ waits: [HumanWait]) -> [Int: Int] {
        let ordered = waits.enumerated()
            .filter { $0.element.kind != .turn }
            .sorted { lhs, rhs in
                if lhs.element.start != rhs.element.start { return lhs.element.start < rhs.element.start }
                if lhs.element.end != rhs.element.end { return lhs.element.end < rhs.element.end }
                return lhs.offset < rhs.offset
            }
        var result: [Int: Int] = [:]
        for (position, item) in ordered.enumerated() { result[item.offset] = position + 1 }
        return result
    }

    fileprivate static func bucket(_ ordinal: Int) -> String {
        switch ordinal {
        case 1: return "1"
        case 2...3: return "2-3"
        case 4...7: return "4-7"
        default: return "8+"
        }
    }

    /// Length of the union of half-open `[start, end)` intervals. Touching and
    /// nested intervals merge; a zero-length interval contributes nothing.
    fileprivate static func unionLength(_ intervals: [(start: EpochMs, end: EpochMs)]) -> EpochMs {
        let ordered = intervals
            .sorted { $0.start < $1.start || ($0.start == $1.start && $0.end < $1.end) }
        var total: EpochMs = 0
        var openStart: EpochMs?
        var openEnd: EpochMs = 0
        for interval in ordered where interval.end > interval.start {
            if openStart != nil, interval.start <= openEnd {
                openEnd = max(openEnd, interval.end)
            } else {
                if let start = openStart { total += openEnd - start }
                openStart = interval.start
                openEnd = interval.end
            }
        }
        if let start = openStart { total += openEnd - start }
        return total
    }
}

// MARK: - One agent's totals

/// Everything the seven groups print for one agent. Filled one eligible source
/// at a time, then rendered in a fixed group order.
private struct AgentReport {
    var sessions = 0
    var openSessions = 0
    var turnWaits = 0
    /// Question and approval waits by kind and answer, in the window.
    var answers: [WaitKind: [WaitAnswer: Int]] = [:]
    var overCap: [WaitKind: Int] = [:]
    /// Capped durations, by kind, in the window.
    var seconds: [WaitKind: [EpochMs]] = [:]
    /// Capped durations of question and approval waits, by kind and ordinal
    /// bucket, in the window.
    var ordinalSeconds: [WaitKind: [String: [EpochMs]]] = [:]
    /// Per-session blocked ms, over the sessions in the window.
    var blocked: [EpochMs] = []
    var blockedWithinCap: [EpochMs] = []

    /// An ineligible source contributes nothing; an eligible one is a session
    /// in the window when it has a human event or a wait there. Its in-window
    /// waits all count, whatever their kind.
    mutating func add(_ fold: WaitFold, window: WaitWindow) {
        guard fold.hasHumanPrompt else { return }
        let inWindow = fold.waits.filter { $0.end >= window.lo && $0.end < window.hi }
        let eventInWindow = fold.humanEvents.contains { $0 >= window.lo && $0 < window.hi }
        guard eventInWindow || !inWindow.isEmpty else { return }

        sessions += 1
        if fold.openSince != nil { openSessions += 1 }

        let ordinals = WaitStats.ordinals(fold.waits)
        var all: [(start: EpochMs, end: EpochMs)] = []
        var withinCap: [(start: EpochMs, end: EpochMs)] = []

        for (index, wait) in fold.waits.enumerated() {
            guard wait.end >= window.lo, wait.end < window.hi else { continue }
            let duration = wait.end - wait.start
            let capped = min(max(duration, 0), WaitStats.capMs)
            if duration > WaitStats.capMs { overCap[wait.kind, default: 0] += 1 }
            seconds[wait.kind, default: []].append(capped)
            if wait.kind == .turn {
                turnWaits += 1
            } else {
                answers[wait.kind, default: [:]][wait.answer ?? .unknown, default: 0] += 1
                if let ordinal = ordinals[index] {
                    ordinalSeconds[wait.kind, default: [:]][WaitStats.bucket(ordinal), default: []]
                        .append(capped)
                }
            }
            all.append((wait.start, wait.start + capped))
            if duration <= WaitStats.capMs { withinCap.append((wait.start, wait.start + capped)) }
        }

        blocked.append(WaitStats.unionLength(all))
        blockedWithinCap.append(WaitStats.unionLength(withinCap))
    }

    func appendLines(for agent: AgentKind, into groups: inout [[String]]) {
        let a = agent.rawValue

        groups[0].append("sessions agent=\(a) n=\(sessions)")
        if openSessions > 0 { groups[1].append("open agent=\(a) n=\(openSessions)") }

        if turnWaits > 0 { groups[2].append("waits agent=\(a) kind=turn n=\(turnWaits)") }
        for kind in [WaitKind.question, .approval] {
            for answer in WaitAnswer.allCases {
                guard let count = answers[kind]?[answer], count > 0 else { continue }
                groups[2].append(
                    "waits agent=\(a) kind=\(kind.rawValue) answer=\(answer.rawValue) n=\(count)")
            }
        }

        for kind in WaitKind.allCases {
            guard let count = overCap[kind], count > 0 else { continue }
            groups[3].append("over_cap agent=\(a) kind=\(kind.rawValue) n=\(count)")
        }

        for kind in WaitKind.allCases {
            guard let values = seconds[kind], !values.isEmpty else { continue }
            groups[4].append(
                "seconds agent=\(a) kind=\(kind.rawValue) "
                    + "\(WaitStats.quantileValues(values, unit: 1000)) n=\(values.count)")
        }

        for kind in [WaitKind.question, .approval] {
            guard let byBucket = ordinalSeconds[kind] else { continue }
            for bucket in WaitStats.buckets {
                guard let values = byBucket[bucket], !values.isEmpty else { continue }
                groups[5].append(
                    "seconds agent=\(a) kind=\(kind.rawValue) ordinal=\(bucket) "
                        + "\(WaitStats.quantileValues(values, unit: 1000)) n=\(values.count)")
            }
        }

        for (scope, values) in [("all", blocked), ("within_cap", blockedWithinCap)] {
            let total = values.reduce(0, +) / 60_000
            groups[6].append(
                "blocked agent=\(a) scope=\(scope) unit=min "
                    + "\(WaitStats.quantileValues(values, unit: 60_000)) "
                    + "total=\(total) n=\(sessions)")
        }
    }
}
