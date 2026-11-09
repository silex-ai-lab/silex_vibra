import Foundation

public enum CheckKind: String, Sendable, CaseIterable { case test, build, lint }
public enum CheckProof: Sendable, Equatable { case exitStatus, runnerSummary }
public enum CheckResult: Sendable, Equatable {
    case passed(CheckProof), failed(CheckProof), unknown
}

public struct ObservedCheck: Sendable, Equatable {
    public let at: Date, kind: CheckKind, result: CheckResult

    public init(at: Date, kind: CheckKind, result: CheckResult) {
        self.at = at
        self.kind = kind
        self.result = result
    }
}

public enum EvidenceEvent: Sendable, Equatable {
    case codeChange(Date)
    case check(ObservedCheck)
}

/// What a session's transcript shows about checking its own code changes.
/// Derived on demand and never stored.
public enum DeliveryEvidence: Sendable, Equatable {
    case noToolRecordsRecognized
    case noCodeChangeSeen
    case changedWithoutCheck(lastChange: Date)
    case changedAfterLastCheck(lastChange: Date, check: ObservedCheck)
    case checkedAfterLastChange(ObservedCheck)

    public var caseName: String {
        switch self {
        case .noToolRecordsRecognized: "noToolRecordsRecognized"
        case .noCodeChangeSeen: "noCodeChangeSeen"
        case .changedWithoutCheck: "changedWithoutCheck"
        case .changedAfterLastCheck: "changedAfterLastCheck"
        case .checkedAfterLastChange: "checkedAfterLastChange"
        }
    }

    /// A check at the same instant as a change counts as before it, so a
    /// change is never reported as checked by a run that started with it.
    public static func build(events: [EvidenceEvent], sawToolRecords: Bool) -> DeliveryEvidence {
        guard sawToolRecords else { return .noToolRecordsRecognized }
        var lastChange: Date?
        var checks: [ObservedCheck] = []
        for event in events {
            switch event {
            case .codeChange(let date): lastChange = max(lastChange ?? date, date)
            case .check(let check): checks.append(check)
            }
        }
        guard let lastChange else { return .noCodeChangeSeen }

        let after = checks.filter { $0.at > lastChange }
        if !after.isEmpty {
            // Latest of each kind, then a failure wins, then test, build, lint.
            let latest = CheckKind.allCases.compactMap { kind in
                after.filter { $0.kind == kind }.reduce(nil as ObservedCheck?) { best, next in
                    best.map { $0.at > next.at ? $0 : next } ?? next
                }
            }
            let isFailure = { (check: ObservedCheck) in
                if case .failed = check.result { return true }
                return false
            }
            if let pick = latest.first(where: isFailure) ?? latest.first { return .checkedAfterLastChange(pick) }
        }
        guard let previous = checks.reduce(nil as ObservedCheck?, { best, next in
            best.map { $0.at > next.at ? $0 : next } ?? next
        }) else { return .changedWithoutCheck(lastChange: lastChange) }
        return .changedAfterLastCheck(lastChange: lastChange, check: previous)
    }

    private static let limit = "Edits made through shell commands are not counted."

    /// States what was seen, never that work is finished or proven.
    public func line(now: Date) -> String {
        func ago(_ date: Date) -> String { "\(formatDuration(now.timeIntervalSince(date))) ago" }
        switch self {
        case .noToolRecordsRecognized:
            return "Vibra saw no tool activity it can read in this session."
        case .noCodeChangeSeen:
            return "No code change seen in this session. \(Self.limit)"
        case .changedWithoutCheck(let change):
            return "Code changed \(ago(change)). No test, build or lint command seen in this session. \(Self.limit)"
        case .changedAfterLastCheck(let change, let check):
            return "Code changed \(ago(change)), after the last \(check.kind.rawValue) command was issued \(ago(check.at)). "
                + "No check seen since. \(Self.limit)"
        case .checkedAfterLastChange(let check):
            return "\(check.kind.rawValue.capitalized) command issued \(ago(check.at)), after the last code change. "
                + "\(check.result.sentence) \(Self.limit)"
        }
    }
}

extension CheckResult {
    fileprivate var sentence: String {
        switch self {
        case .passed(.exitStatus): "It exited with status 0."
        case .passed(.runnerSummary): "Its own summary reported a pass."
        case .failed(.exitStatus): "It exited with a non-zero status."
        case .failed(.runnerSummary): "Its own summary reported a failure."
        case .unknown: "Result not visible."
        }
    }

    /// Stable names for the content-free diagnostic.
    public var statsName: String {
        switch self {
        case .passed(.exitStatus): "passed.exitStatus"
        case .passed(.runnerSummary): "passed.runnerSummary"
        case .failed(.exitStatus): "failed.exitStatus"
        case .failed(.runnerSummary): "failed.runnerSummary"
        case .unknown: "unknown"
        }
    }
}
