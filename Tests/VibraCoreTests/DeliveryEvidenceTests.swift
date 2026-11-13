import Foundation
import Testing
@testable import VibraCore

struct DeliveryEvidenceTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func check(_ seconds: TimeInterval, _ kind: CheckKind = .test, _ result: CheckResult = .passed(.exitStatus))
        -> EvidenceEvent {
        .check(ObservedCheck(at: at(seconds), kind: kind, result: result))
    }

    private func build(_ events: [EvidenceEvent], saw: Bool = true) -> DeliveryEvidence {
        DeliveryEvidence.build(events: events, sawToolRecords: saw)
    }

    @Test func noToolRecords() {
        #expect(build([], saw: false) == .noToolRecordsRecognized)
    }

    @Test func noCodeChange() {
        #expect(build([]) == .noCodeChangeSeen)
        #expect(build([check(5)]) == .noCodeChangeSeen)
    }

    @Test func changedWithoutCheck() {
        #expect(build([.codeChange(at: at(10))]) == .changedWithoutCheck(lastChange: at(10)))
    }

    @Test func changedAfterLastCheck() {
        let earlier = ObservedCheck(at: at(5), kind: .test, result: .failed(.exitStatus))
        let events: [EvidenceEvent] = [.codeChange(at: at(1)), .check(earlier), .codeChange(at: at(10))]
        #expect(build(events) == .changedAfterLastCheck(lastChange: at(10), check: earlier))
    }

    @Test func checkedAfterLastChange() {
        let later = ObservedCheck(at: at(20), kind: .test, result: .passed(.runnerSummary))
        #expect(build([.codeChange(at: at(10)), .check(later)]) == .checkedAfterLastChange(later))
    }

    @Test func aChangeAtTheSameInstantAsACheckIsAfterIt() {
        let same = ObservedCheck(at: at(10), kind: .test, result: .passed(.exitStatus))
        #expect(build([.check(same), .codeChange(at: at(10))]) == .changedAfterLastCheck(lastChange: at(10), check: same))
    }

    @Test func eventOrderInTheArrayDoesNotMatter() {
        let later = ObservedCheck(at: at(20), kind: .build, result: .unknown)
        #expect(build([.check(later), .codeChange(at: at(10))]) == .checkedAfterLastChange(later))
    }

    @Test func aFailedBuildBeatsALaterPassedTest() {
        let failedBuild = ObservedCheck(at: at(20), kind: .build, result: .failed(.exitStatus))
        let events: [EvidenceEvent] = [.codeChange(at: at(10)), .check(failedBuild), check(30, .test)]
        #expect(build(events) == .checkedAfterLastChange(failedBuild))
    }

    @Test func aLaterPassReplacesAnEarlierFailOfTheSameKind() {
        let passed = ObservedCheck(at: at(30), kind: .test, result: .passed(.exitStatus))
        let events: [EvidenceEvent] = [
            .codeChange(at: at(10)), check(20, .test, .failed(.exitStatus)), .check(passed),
        ]
        #expect(build(events) == .checkedAfterLastChange(passed))
    }

    @Test func withNoFailureTestThenBuildThenLintIsReported() {
        let test = ObservedCheck(at: at(20), kind: .test, result: .unknown)
        let events: [EvidenceEvent] = [.codeChange(at: at(10)), check(30, .lint), check(25, .build), .check(test)]
        #expect(build(events) == .checkedAfterLastChange(test))
        #expect(build([.codeChange(at: at(10)), check(30, .lint), check(25, .build)])
            == .checkedAfterLastChange(ObservedCheck(at: at(25), kind: .build, result: .passed(.exitStatus))))
    }

    @Test func checksBeforeTheLastChangeAreNotAfterIt() {
        let events: [EvidenceEvent] = [check(5, .build, .failed(.exitStatus)), .codeChange(at: at(10)), check(20, .test)]
        #expect(build(events) == .checkedAfterLastChange(ObservedCheck(at: at(20), kind: .test, result: .passed(.exitStatus))))
    }

    @Test func caseNamesAreStable() {
        #expect(build([], saw: false).caseName == "noToolRecordsRecognized")
        #expect(build([]).caseName == "noCodeChangeSeen")
        #expect(build([.codeChange(at: at(1))]).caseName == "changedWithoutCheck")
        #expect(build([check(1), .codeChange(at: at(2))]).caseName == "changedAfterLastCheck")
        #expect(build([.codeChange(at: at(1)), check(2)]).caseName == "checkedAfterLastChange")
    }

    private let limit = "Edits made through shell commands are not counted."

    @Test func linesStateWhatWasSeen() {
        let now = at(3600)
        let lines = [
            build([], saw: false).line(now: now),
            build([]).line(now: now),
            build([.codeChange(at: at(3600 - 720))]).line(now: now),
            build([check(100), .codeChange(at: at(3600 - 720))]).line(now: now),
            build([.codeChange(at: at(10)), check(20, .test, .failed(.runnerSummary))]).line(now: now),
        ]
        #expect(lines[0] == "Vibra saw no tool activity it can read in this session.")
        #expect(lines[2].hasPrefix("Code changed 12m ago."))
        for line in lines.dropFirst() { #expect(line.hasSuffix(limit)) }
    }

    @Test func linesNeverClaimMoreThanWasSeen() {
        let results: [CheckResult] = [
            .passed(.exitStatus), .passed(.runnerSummary), .failed(.exitStatus), .failed(.runnerSummary), .unknown,
        ]
        for kind in CheckKind.allCases {
            for result in results {
                let events: [EvidenceEvent] = [.codeChange(at: at(1)), check(2, kind, result)]
                let text = build(events).line(now: at(100)).lowercased()
                for word in ["done", "complete", "verified"] { #expect(!text.contains(word)) }
            }
        }
    }

    @Test func unknownResultSaysItWasNotVisible() {
        let text = build([.codeChange(at: at(1)), check(2, .test, .unknown)]).line(now: at(100))
        #expect(text.contains("Result not visible"))
        let pass = build([.codeChange(at: at(1)), check(2, .test, .passed(.runnerSummary))]).line(now: at(100))
        #expect(pass.contains("summary"))
    }
}
