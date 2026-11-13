import Foundation

public enum CheckKind: String, Sendable, CaseIterable { case test, build, lint }
public enum CheckProof: Sendable, Equatable { case exitStatus, runnerSummary }
public enum CheckResult: Sendable, Equatable {
    case passed(CheckProof), failed(CheckProof), unknown
}

public struct ObservedCheck: Sendable, Equatable {
    /// When the command was issued.
    public let at: Date
    /// When its result was recorded; nil when the transcript has none.
    public let completedAt: Date?
    public let kind: CheckKind, result: CheckResult

    public init(at: Date, completedAt: Date?, kind: CheckKind, result: CheckResult) {
        self.at = at
        self.completedAt = completedAt
        self.kind = kind
        self.result = result
    }
}

public enum TestEditEffect: String, Sendable, CaseIterable {
    case fewerAssertionMatches, moreSkipMatches, moreFocusMatches, moreExpectedFailureMatches, fewerTestFunctionMatches

    /// Named as pattern matches, never as calls or functions: a string holding
    /// a pattern word matches like code.
    var phrase: String {
        switch self {
        case .fewerAssertionMatches: "fewer assertion matches"
        case .moreSkipMatches: "more skip matches"
        case .moreFocusMatches: "more focus (.only) matches"
        case .moreExpectedFailureMatches: "more expected-failure matches"
        case .fewerTestFunctionMatches: "fewer test-function matches"
        }
    }
}

/// Pattern-match counts in an edit's removed and inserted text. Numbers only.
public struct PatternCounts: Sendable, Equatable {
    public var assertion, skip, focus, expectedFailure, testFunction: Int

    public init(assertion: Int, skip: Int, focus: Int, expectedFailure: Int, testFunction: Int) {
        self.assertion = assertion
        self.skip = skip
        self.focus = focus
        self.expectedFailure = expectedFailure
        self.testFunction = testFunction
    }
}

/// Identifies one file within a session so its edits can be netted. Holds a
/// hash of the path, never the path, and is never printed. `String.hashValue`
/// is seeded per process, so the key is in-memory only and must never be
/// persisted: the same path hashes differently in the next launch.
public struct PathKey: Sendable, Hashable {
    private let hash: Int

    init(path: String) { hash = path.hashValue }
}

public enum CodeChangeTarget: Sendable, Equatable {
    case source
    /// Counts are nil when the edit's text is not available.
    case test(path: PathKey, before: PatternCounts?, after: PatternCounts?)
}

public struct CodeChange: Sendable, Equatable {
    /// When the edit call opened.
    public let at: Date
    /// When its successful result was recorded.
    public let completedAt: Date?
    public let target: CodeChangeTarget

    public init(at: Date, completedAt: Date?, target: CodeChangeTarget) {
        self.at = at
        self.completedAt = completedAt
        self.target = target
    }
}

public enum EvidenceEvent: Sendable, Equatable {
    case codeChange(CodeChange)
    case check(ObservedCheck)
}

/// What a session's transcript shows about checking its own code changes.
/// Derived on demand and never stored.
public enum DeliveryEvidence: Sendable, Equatable {
    case noToolRecordsRecognized
    case noCodeChangeSeen
    case changedWithoutCheck(lastChange: Date)
    case changedAfterLastCheck(lastChange: Date, check: ObservedCheck)
    case checkedAfterLastChange(ObservedCheck, testEdits: TestEdits?)

    /// Present only when the clause shows: `effects` is never empty.
    public struct TestEdits: Sendable, Equatable {
        /// F.completedAt: when the failed run before the reported one finished.
        public let failedRunFinishedAt: Date
        public let effects: Set<TestEditEffect>

        public init(failedRunFinishedAt: Date, effects: Set<TestEditEffect>) {
            self.failedRunFinishedAt = failedRunFinishedAt
            self.effects = effects
        }
    }

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
            case .codeChange(let change): lastChange = max(lastChange ?? change.at, change.at)
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
            if let pick = latest.first(where: isFailure) ?? latest.first {
                return .checkedAfterLastChange(
                    pick, testEdits: Self.testEdits(events: events, checks: checks, reported: pick))
            }
        }
        guard let previous = checks.reduce(nil as ObservedCheck?, { best, next in
            best.map { $0.at > next.at ? $0 : next } ?? next
        }) else { return .changedWithoutCheck(lastChange: lastChange) }
        return .changedAfterLastCheck(lastChange: lastChange, check: previous)
    }

    // MARK: - The test-edit clause

    /// Rules 1-5: only a passed test run whose immediately preceding test check
    /// failed can carry the clause, and then only for files whose edits all
    /// started after that failure finished and ended before the pass was issued.
    /// A file with any other window-touching edit is dropped, never counted in
    /// part: an edit still running when the pass starts may undo an earlier one.
    private static func testEdits(
        events: [EvidenceEvent], checks: [ObservedCheck], reported: ObservedCheck
    ) -> TestEdits? {
        guard reported.kind == .test, case .passed = reported.result else { return nil }

        var failure: ObservedCheck?
        for check in checks where check.kind == .test && check.at < reported.at {
            if let current = failure, check.at < current.at { continue }
            failure = check
        }
        guard let failure, case .failed = failure.result, let finished = failure.completedAt else { return nil }

        // A nil completion time means "never finished", so it always touches the
        // window and then drops its file below.
        var windows: [PathKey: [CodeChange]] = [:]
        for event in events {
            guard case .codeChange(let change) = event,
                  case .test(path: let key, before: _, after: _) = change.target,
                  change.at < reported.at,
                  change.completedAt.map({ $0 > finished }) ?? true
            else { continue }
            windows[key, default: []].append(change)
        }

        var totals: [PatternCounts] = []
        for changes in windows.values {
            var net = zeroCounts
            var dropped = false
            for change in changes {
                guard case .test(_, before: let before?, after: let after?) = change.target,
                      let ended = change.completedAt, finished < change.at, ended < reported.at
                else {
                    dropped = true
                    break
                }
                net = adding(net, subtracting(after, before))
            }
            if !dropped { totals.append(net) }
        }

        let sum = totals.reduce(zeroCounts, adding)
        let effects = Set(TestEditEffect.allCases.filter { effect in
            switch effect {
            case .fewerAssertionMatches: totals.contains { $0.assertion < 0 } && sum.assertion < 0
            case .moreSkipMatches: totals.contains { $0.skip > 0 } && sum.skip > 0
            case .moreFocusMatches: totals.contains { $0.focus > 0 } && sum.focus > 0
            case .moreExpectedFailureMatches: totals.contains { $0.expectedFailure > 0 } && sum.expectedFailure > 0
            case .fewerTestFunctionMatches: totals.contains { $0.testFunction < 0 } && sum.testFunction < 0
            }
        })
        guard !effects.isEmpty else { return nil }
        return TestEdits(failedRunFinishedAt: finished, effects: effects)
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
        case .checkedAfterLastChange(let check, let testEdits):
            let head = "\(check.kind.rawValue.capitalized) command issued \(ago(check.at)), after the last code change. "
                + check.result.sentence
            guard let testEdits else { return "\(head) \(Self.limit)" }
            return "\(head) \(Self.clause(testEdits, now: now)) \(Self.limit)"
        }
    }

    /// Two sentences: what the counts changed, then the reach of the claim. The
    /// age is the failed run's finish, in the same phrasing as every other age.
    private static func clause(_ testEdits: TestEdits, now: Date) -> String {
        let phrases = TestEditEffect.allCases
            .filter(testEdits.effects.contains)
            .map(\.phrase)
            .joined(separator: ", ")
        let age = formatDuration(now.timeIntervalSince(testEdits.failedRunFinishedAt))
        return "Between a failed test run that finished \(age) ago and this run, edits to test files "
            + "changed Vibra's text-pattern counts in the edited text: \(phrases). "
            + "Vibra matches text patterns in the edited text only; it does not parse code or read the whole file."
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

private let zeroCounts = PatternCounts(assertion: 0, skip: 0, focus: 0, expectedFailure: 0, testFunction: 0)

private func adding(_ lhs: PatternCounts, _ rhs: PatternCounts) -> PatternCounts {
    PatternCounts(
        assertion: lhs.assertion + rhs.assertion,
        skip: lhs.skip + rhs.skip,
        focus: lhs.focus + rhs.focus,
        expectedFailure: lhs.expectedFailure + rhs.expectedFailure,
        testFunction: lhs.testFunction + rhs.testFunction)
}

private func subtracting(_ lhs: PatternCounts, _ rhs: PatternCounts) -> PatternCounts {
    PatternCounts(
        assertion: lhs.assertion - rhs.assertion,
        skip: lhs.skip - rhs.skip,
        focus: lhs.focus - rhs.focus,
        expectedFailure: lhs.expectedFailure - rhs.expectedFailure,
        testFunction: lhs.testFunction - rhs.testFunction)
}
