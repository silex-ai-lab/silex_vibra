import Foundation
import Testing
@testable import VibraCore

struct EvidenceStatsTests {
    private let t = EvidenceFixtures.base

    private func check(_ s: TimeInterval, _ kind: CheckKind, _ result: CheckResult) -> EvidenceEvent {
        .check(ObservedCheck(at: t.addingTimeInterval(s), kind: kind, result: result))
    }

    @Test func printsExactlyTheFiveLineFamiliesSortedAndCountsOnly() {
        let rows: [(agent: AgentKind, fold: EvidenceFold)] = [
            (.codex, EvidenceFold(events: [.codeChange(at: t), check(5, .test, .failed(.runnerSummary))], sawToolRecords: true)),
            (.claudeCode, EvidenceFold(events: [], sawToolRecords: false)),
            (.claudeCode, EvidenceFold(
                events: [.codeChange(at: t), .codeChange(at: t.addingTimeInterval(1)),
                         check(9, .build, .passed(.exitStatus)), check(10, .build, .unknown)],
                sawToolRecords: true)),
            (.claudeCode, EvidenceFold(events: [.codeChange(at: t)], sawToolRecords: true)),
        ]

        let text = EvidenceStats.format(rows)

        #expect(text == """
        sessions agent=claudeCode n=3
        sessions agent=codex n=1
        case agent=claudeCode case=changedWithoutCheck n=1
        case agent=claudeCode case=checkedAfterLastChange n=1
        case agent=claudeCode case=noToolRecordsRecognized n=1
        case agent=codex case=checkedAfterLastChange n=1
        reported agent=claudeCode kind=build result=unknown n=1
        reported agent=codex kind=test result=failed.runnerSummary n=1
        check agent=claudeCode kind=build result=passed.exitStatus n=1
        check agent=claudeCode kind=build result=unknown n=1
        check agent=codex kind=test result=failed.runnerSummary n=1
        change agent=claudeCode target=source n=3
        change agent=codex target=source n=1

        """)
    }

    @Test func noSessionsPrintsNothing() {
        #expect(EvidenceStats.format([]) == "")
    }

    @Test func qualifiedLinesNameEachEffectTheClauseCarries() {
        let failure = ObservedCheck(
            at: t.addingTimeInterval(1), completedAt: t.addingTimeInterval(2), kind: .test,
            result: .failed(.exitStatus))
        let pass = ObservedCheck(
            at: t.addingTimeInterval(9), completedAt: t.addingTimeInterval(10), kind: .test,
            result: .passed(.exitStatus))
        let edit = CodeChange(
            at: t.addingTimeInterval(4), completedAt: t.addingTimeInterval(5),
            target: .test(
                path: PathKey(path: "/work/tests/a.swift"),
                before: PatternCounts(assertion: 1, skip: 0, focus: 0, expectedFailure: 0, testFunction: 0),
                after: PatternCounts(assertion: 0, skip: 1, focus: 0, expectedFailure: 0, testFunction: 0)))
        let rows: [(agent: AgentKind, fold: EvidenceFold)] = [
            (.claudeCode, EvidenceFold(events: [.codeChange(edit), .check(failure), .check(pass)], sawToolRecords: true)),
            (.codex, EvidenceFold(events: [.check(failure), .check(pass)], sawToolRecords: true)),
        ]

        let qualified = EvidenceStats.format(rows)
            .split(separator: "\n")
            .filter { $0.hasPrefix("qualified ") }

        #expect(qualified == [
            "qualified agent=claudeCode effect=fewerAssertionMatches n=1",
            "qualified agent=claudeCode effect=moreSkipMatches n=1",
        ])
    }
}
