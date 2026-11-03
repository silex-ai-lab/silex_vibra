import Foundation

/// The window of the usage report and the perf analyzer: which files are
/// read, which local days are in, and the calendar that decides both.
///
/// One value is shared by the ingest, the builder and the analyzer so the
/// three cannot drift a day apart. Days are **local** days: transcript
/// timestamps are UTC, and bucketing by UTC day silently moves an evening
/// session into tomorrow.
public struct ReportWindow: Sendable, Equatable {
    public let days: Int
    public let calendar: Calendar
    /// Files modified earlier than this are not read. A day wider than the
    /// window: a file last written just after midnight still holds records
    /// belonging to the previous day.
    public let fileCutoff: Date
    /// Local start of the oldest day in the window, inclusive.
    public let start: Date
    /// Local start of today.
    public let today: Date
    public let now: Date

    public init(now: Date, days: Int, calendar: Calendar) {
        self.now = now
        self.days = days
        self.calendar = calendar
        self.fileCutoff = now.addingTimeInterval(-Double(days + 1) * 86_400)
        let today = calendar.startOfDay(for: now)
        self.today = today
        self.start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
    }

    public func day(of date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public func contains(_ date: Date) -> Bool {
        (start...today).contains(day(of: date))
    }
}
