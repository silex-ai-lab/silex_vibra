import Foundation
import Testing
@testable import VibraCore

struct EvidenceStatsTests {
    private let t = EvidenceFixtures.base

    private func check(_ s: TimeInterval, _ kind: CheckKind, _ result: CheckResult) -> EvidenceEvent {
        .check(ObservedCheck(at: t.addingTimeInterval(s), kind: kind, result: result))
    }

    @Test func printsExactlyTheFourLineFamiliesSortedAndCountsOnly() {
        let rows: [(agent: AgentKind, fold: EvidenceFold)] = [
            (.codex, EvidenceFold(events: [.codeChange(t), check(5, .test, .failed(.runnerSummary))], sawToolRecords: true)),
            (.claudeCode, EvidenceFold(events: [], sawToolRecords: false)),
            (.claudeCode, EvidenceFold(
                events: [.codeChange(t), .codeChange(t.addingTimeInterval(1)),
                         check(9, .build, .passed(.exitStatus)), check(10, .build, .unknown)],
                sawToolRecords: true)),
            (.claudeCode, EvidenceFold(events: [.codeChange(t)], sawToolRecords: true)),
        ]

        let text = EvidenceStats.format(rows)

        #expect(text == """
        sessions agent=claudeCode n=3
        sessions agent=codex n=1
        case agent=claudeCode case=changedWithoutCheck n=1
        case agent=claudeCode case=checkedAfterLastChange n=1
        case agent=claudeCode case=noToolRecordsRecognized n=1
        case agent=codex case=checkedAfterLastChange n=1
        check agent=claudeCode kind=build result=passed.exitStatus n=1
        check agent=claudeCode kind=build result=unknown n=1
        check agent=codex kind=test result=failed.runnerSummary n=1
        change agent=claudeCode n=3
        change agent=codex n=1

        """)
    }

    @Test func noSessionsPrintsNothing() {
        #expect(EvidenceStats.format([]) == "")
    }
}
