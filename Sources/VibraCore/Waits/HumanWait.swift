import Foundation

/// What a session was waiting on the human for.
public enum WaitKind: String, Sendable, CaseIterable {
    /// The agent finished its turn; the wait ends at the human's next prompt or command.
    case turn
    /// The agent asked with `AskUserQuestion`; the wait ends at the answer.
    case question
    /// A tool call the human approved or rejected; the wait ends at the result.
    case approval
}

/// How the human answered a question or approval.
public enum WaitAnswer: String, Sendable, CaseIterable {
    case accept, reject, unknown
}

/// Epoch milliseconds read from a record's timestamp string by `epochMs(fromTimestamp:)`.
public typealias EpochMs = Int64

/// One interval in which a session waited on the human. Times only.
public struct HumanWait: Sendable, Equatable {
    public let kind: WaitKind
    public let start: EpochMs
    public let end: EpochMs
    /// nil for `.turn`; `.unknown` when the result carries no decision.
    public let answer: WaitAnswer?

    public init(kind: WaitKind, start: EpochMs, end: EpochMs, answer: WaitAnswer? = nil) {
        self.kind = kind
        self.start = start
        self.end = end
        self.answer = answer
    }
}

/// One transcript's waits. Never carries text, a path or an id.
public struct WaitFold: Sendable, Equatable {
    /// In the order the closing record appeared in the file.
    public var waits: [HumanWait]
    /// Times of human prompts and human commands.
    public var humanEvents: [EpochMs]
    /// At least one human prompt (not only commands) anywhere in the transcript.
    public var hasHumanPrompt: Bool
    /// Start of a turn wait still open when the transcript ends.
    public var openSince: EpochMs?

    public init(
        waits: [HumanWait] = [], humanEvents: [EpochMs] = [], hasHumanPrompt: Bool = false,
        openSince: EpochMs? = nil
    ) {
        self.waits = waits
        self.humanEvents = humanEvents
        self.hasHumanPrompt = hasHumanPrompt
        self.openSince = openSince
    }
}

/// Folds one transcript, fed every batch of it in order, into its waits.
public protocol WaitExtractor {
    mutating func fold(_ lines: [String])
    func finish() -> WaitFold
}

/// The record time the wait rules use: integer milliseconds taken from the
/// timestamp string itself, so no floating-point `Date` enters the arithmetic
/// and the Python oracle computes the same value. nil for anything that is
/// not `YYYY-MM-DDTHH:MM:SS[.fraction](Z|±HH:MM)` with a valid date and time.
public func epochMs(fromTimestamp string: String) -> EpochMs? {
    let pattern = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})$/
    guard let m = string.wholeMatch(of: pattern),
          let year = Int64(m.1), let month = Int64(m.2), let day = Int64(m.3),
          let hour = Int64(m.4), let minute = Int64(m.5), let second = Int64(m.6),
          (1...12).contains(month), day >= 1, day <= daysInMonth(year: year, month: month),
          hour < 24, minute < 60, second < 60
    else { return nil }

    var offsetSeconds: Int64 = 0
    if m.8 != "Z" {
        let zone = m.8.dropFirst()
        guard let oh = Int64(zone.prefix(2)), let om = Int64(zone.suffix(2)), oh < 24, om < 60 else { return nil }
        offsetSeconds = (oh * 3600 + om * 60) * (m.8.first == "-" ? -1 : 1)
    }

    var fraction: Int64 = 0
    if let digits = m.7 {
        let three = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        fraction = Int64(three) ?? 0
    }

    let seconds = daysFromCivil(year: year, month: month, day: day) * 86_400
        + hour * 3600 + minute * 60 + second - offsetSeconds
    return seconds * 1000 + fraction
}

private func daysInMonth(year: Int64, month: Int64) -> Int64 {
    switch month {
    case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
}

/// Days since 1970-01-01 in the proleptic Gregorian calendar (Hinnant's algorithm).
private func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = (month + 9) % 12
    let doy = (153 * mp + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
}

/// The `--wait-stats` window: the half-open interval `[lo, hi)` in epoch ms.
public struct WaitWindow: Sendable, Equatable {
    public let lo: EpochMs
    public let hi: EpochMs

    public init(lo: EpochMs, hi: EpochMs) {
        self.lo = lo
        self.hi = hi
    }

    public static let defaultDays = 30

    /// `--days N`, or `--from D --to D` as local dates in `timeZone`. Each flag
    /// is passed as present-with-value, present-without-value (`.some(nil)`),
    /// or absent (`nil`). Returns a usage message on any invalid combination.
    public static func parse(
        days: String??, from: String??, to: String??, now: EpochMs, timeZone: TimeZone
    ) -> Result<WaitWindow, WaitWindowError> {
        if days != nil && (from != nil || to != nil) {
            return .failure(.usage("use --days or --from/--to, not both"))
        }
        if from != nil || to != nil {
            guard let fromText = from ?? nil, let toText = to ?? nil else {
                return .failure(.usage("--from and --to go together, each with a date"))
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            guard let first = localMidnight(fromText, calendar: calendar),
                  let last = localMidnight(toText, calendar: calendar),
                  let after = calendar.date(byAdding: .day, value: 1, to: last)
            else { return .failure(.usage("dates must be real YYYY-MM-DD dates")) }
            guard first <= last else { return .failure(.usage("--from must not be after --to")) }
            return .success(WaitWindow(lo: milliseconds(first), hi: milliseconds(after)))
        }
        var n = defaultDays
        if let days {
            guard let text = days, text.wholeMatch(of: /\d+/) != nil, let parsed = Int(text), parsed >= 1 else {
                return .failure(.usage("--days takes a whole number of at least 1"))
            }
            n = parsed
        }
        return .success(WaitWindow(lo: now - Int64(n) * 86_400_000, hi: now + 1))
    }

    private static func localMidnight(_ text: String, calendar: Calendar) -> Date? {
        guard let m = text.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/),
              let year = Int(m.1), let month = Int(m.2), let day = Int(m.3),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return date
    }

    private static func milliseconds(_ date: Date) -> EpochMs {
        EpochMs((date.timeIntervalSince1970 * 1000).rounded())
    }
}

public enum WaitWindowError: Error, Equatable {
    case usage(String)
}
