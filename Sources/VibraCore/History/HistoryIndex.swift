import Foundation

/// Questions grouped by local day, newest first, with the window and filters
/// applied. Pure: the calendar and `now` are parameters.
public struct HistoryIndex: Sendable {
    public struct Day: Sendable, Equatable {
        public let day: Date
        public let questions: [QuestionRecord]
    }

    public let days: [Day]
    public let windowStart: Date

    public static let allowedDays = [1, 3, 7, 14, 30]

    public static func clampDays(_ days: Int) -> Int {
        min(max(days, 1), 30)
    }

    /// The first local day of a `windowDays` window ending today, computed
    /// exactly as `ReportBuilder` does so the two cannot drift a day apart.
    public static func windowStart(windowDays: Int, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(clampDays(windowDays) - 1), to: today) ?? today
    }

    /// Keeps a question iff its local day is inside the window, then applies
    /// the keyword (case- and diacritic-insensitive substring), agent and
    /// project filters.
    public static func build(
        _ records: [QuestionRecord],
        windowDays: Int,
        now: Date,
        calendar: Calendar = .current,
        keyword: String = "",
        agent: AgentKind? = nil,
        project: String? = nil,
        sessionID: String? = nil
    ) -> HistoryIndex {
        let start = windowStart(windowDays: windowDays, now: now, calendar: calendar)
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = records.filter { record in
            let day = calendar.startOfDay(for: record.timestamp)
            guard day >= start, record.timestamp <= now else { return false }
            if let agent, record.agent != agent { return false }
            if let project, record.project != project { return false }
            if let sessionID, record.sessionID != sessionID { return false }
            if !needle.isEmpty,
               record.text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) == nil,
               record.project.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                return false
            }
            return true
        }
        let grouped = Dictionary(grouping: kept) { calendar.startOfDay(for: $0.timestamp) }
        let days = grouped
            .map { Day(day: $0.key, questions: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.day > $1.day }
        return HistoryIndex(days: days, windowStart: start)
    }

    public var count: Int { days.reduce(0) { $0 + $1.questions.count } }
}

/// `--history-stats`: counts per day and agent, and bytes read. Never text.
public enum HistoryStats {
    public static func format(
        _ index: HistoryIndex,
        windowDays: Int,
        bytesRead: Int,
        calendar: Calendar = .current
    ) -> String {
        let df = DateFormatter()
        df.calendar = calendar
        df.timeZone = calendar.timeZone
        df.dateFormat = "yyyy-MM-dd EEE"
        var out = "History — last \(HistoryIndex.clampDays(windowDays)) days: \(index.count) questions\n"
        if index.days.isEmpty { out += "  (none in this window)\n" }
        for day in index.days {
            let perAgent = Dictionary(grouping: day.questions, by: \.agent)
            let parts = AgentKind.allCases.compactMap { agent in
                perAgent[agent].map { "\(agent.displayName) \($0.count)" }
            }
            out += "  \(df.string(from: day.day))  \(day.questions.count)  (\(parts.joined(separator: ", ")))\n"
        }
        out += String(format: "read %.1f MB of transcripts\n", Double(bytesRead) / 1_048_576)
        return out
    }
}
