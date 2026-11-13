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

    private func check(
        _ seconds: TimeInterval, _ kind: CheckKind, _ result: CheckResult, ends: TimeInterval?
    ) -> EvidenceEvent {
        .check(ObservedCheck(at: at(seconds), completedAt: ends.map { at($0) }, kind: kind, result: result))
    }

    private func counts(
        assertion: Int = 0, skip: Int = 0, focus: Int = 0, expectedFailure: Int = 0, testFunction: Int = 0
    ) -> PatternCounts {
        PatternCounts(
            assertion: assertion, skip: skip, focus: focus, expectedFailure: expectedFailure,
            testFunction: testFunction)
    }

    private func edit(
        _ seconds: TimeInterval, ends: TimeInterval?, file: String = "tests/a.swift",
        before: PatternCounts?, after: PatternCounts?
    ) -> EvidenceEvent {
        .codeChange(CodeChange(
            at: at(seconds), completedAt: ends.map { at($0) },
            target: .test(path: PathKey(path: file), before: before, after: after)))
    }

    private func sourceEdit(_ seconds: TimeInterval, ends: TimeInterval? = nil) -> EvidenceEvent {
        .codeChange(CodeChange(at: at(seconds), completedAt: ends.map { at($0) }, target: .source))
    }

    private func clauses(_ evidence: DeliveryEvidence) -> DeliveryEvidence.TestEdits? {
        guard case .checkedAfterLastChange(_, let testEdits) = evidence else { return nil }
        return testEdits
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

    // MARK: The test-edit clause
    //
    // F fails and finishes at 12, P is issued at 20 unless a test says otherwise.

    @Test func anAssertionRemovedBetweenAFailedRunAndAPassShowsTheClause() throws {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, before: counts(assertion: 1), after: counts()),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        let clause = try #require(clauses(evidence))
        #expect(clause.failedRunFinishedAt == at(12))
        #expect(clause.effects == [.fewerAssertionMatches])
        let expected = "Test command issued 11m ago, after the last code change. It exited with status 0. "
            + "Between a failed test run that finished 12m ago and this run, edits to test files "
            + "changed Vibra's text-pattern counts in the edited text: fewer assertion matches. "
            + "Vibra matches text patterns in the edited text only; it does not parse code or read the whole file. "
            + limit
        #expect(evidence.line(now: at(732)) == expected)
    }

    @Test func noClauseWhenAPassedTestSitsBetweenTheFailureAndThePass() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, before: counts(assertion: 1), after: counts()),
            check(16, .test, .passed(.exitStatus), ends: 17),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func noClauseWhenAnUnknownTestSitsBetweenTheFailureAndThePass() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, before: counts(assertion: 1), after: counts()),
            check(16, .test, .unknown, ends: 17),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func noClauseWhenTheEditStartedWhileTheFailedRunWasStillGoing() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(11, ends: 15, before: counts(assertion: 1), after: counts()),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func noClauseWhenTheFailedRunHasNoFinishTime() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: nil),
            edit(14, ends: 15, before: counts(assertion: 1), after: counts()),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func noClauseWhenTheEditIsStillRunningAsThePassIsIssued() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 21, before: counts(assertion: 1), after: counts()),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func aRestoringEditThatStraddlesThePassDropsTheFile() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, before: counts(assertion: 1), after: counts()),
            edit(16, ends: 21, before: counts(), after: counts(assertion: 1)),
            check(20, .test, .passed(.exitStatus), ends: 22),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func aRestoringEditThatStraddlesTheFailuresFinishDropsTheFile() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(11, ends: 16, before: counts(), after: counts(assertion: 1)),
            edit(14, ends: 15, before: counts(assertion: 1), after: counts()),
            check(20, .test, .passed(.exitStatus), ends: 22),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func anAssertionMovedToAnotherTestFileShowsNoClause() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, file: "tests/a.swift", before: counts(assertion: 1), after: counts()),
            edit(16, ends: 17, file: "tests/b.swift", before: counts(), after: counts(assertion: 1)),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func aSourceOnlyEditShowsNoClause() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            sourceEdit(14, ends: 15),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func aSourceEditPlusATestEditStillShowsTheClause() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            sourceEdit(13, ends: 14),
            edit(14, ends: 15, before: counts(assertion: 1), after: counts()),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence)?.effects == [.fewerAssertionMatches])
    }

    @Test func aStringOnlyChangeStillShowsTheClauseInMatchWording() throws {
        // The text-pattern rule counts a string literal like code, so the
        // sentence must say "matches" and never claim an assertion was removed.
        let before = patternCounts(in: #"let expectation = "assert(x)""#)
        let after = patternCounts(in: #"let expectation = """#)
        #expect(before.assertion == 1)
        #expect(after.assertion == 0)
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, before: before, after: after),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        let text = evidence.line(now: at(732))
        #expect(text.contains("fewer assertion matches"))
        #expect(text.contains("Vibra matches text patterns in the edited text only"))
        #expect(!text.lowercased().contains("removed"))
    }

    @Test func aSkipAddedThenRemovedShowsNoClause() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, before: counts(), after: counts(skip: 1)),
            edit(16, ends: 17, before: counts(skip: 1), after: counts()),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func anAssertionRemovedThenRestoredShowsNoClause() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, before: counts(assertion: 1), after: counts()),
            edit(16, ends: 17, before: counts(), after: counts(assertion: 1)),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func anAssertionMovedWithinOneFileShowsNoClause() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, before: counts(assertion: 1), after: counts(assertion: 1)),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func aReplaceAllEditOnTheOnlyFileShowsNoClause() {
        // A `replace_all` edit changes an unknown number of occurrences, so it
        // reaches this rule as nil counts and its file is dropped.
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, before: nil, after: nil),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func aNilCountEditOnTheOnlyFileShowsNoClause() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, before: nil, after: nil),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence) == nil)
    }

    @Test func aWriteOnAnotherTestFileDoesNotHideTheComparedFile() throws {
        // A whole-file Write carries no counts, so its file is dropped; the
        // clause still names what the file with counts shows.
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, file: "tests/a.swift", before: counts(assertion: 1), after: counts()),
            edit(16, ends: 17, file: "tests/b.swift", before: nil, after: nil),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence)?.effects == [.fewerAssertionMatches])
    }

    @Test func aPassedBuildAsTheReportedCheckShowsNoClause() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, before: counts(assertion: 1), after: counts()),
            check(20, .build, .passed(.exitStatus), ends: 21),
        ])
        #expect(evidence.caseName == "checkedAfterLastChange")
        #expect(clauses(evidence) == nil)
    }

    @Test func twoEffectsAreNamedInAllCasesOrder() throws {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            edit(14, ends: 15, before: counts(assertion: 1), after: counts(skip: 1)),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        let clause = try #require(clauses(evidence))
        #expect(clause.effects == [.fewerAssertionMatches, .moreSkipMatches])
        let expected = "Test command issued 11m ago, after the last code change. It exited with status 0. "
            + "Between a failed test run that finished 12m ago and this run, edits to test files "
            + "changed Vibra's text-pattern counts in the edited text: fewer assertion matches, more skip matches. "
            + "Vibra matches text patterns in the edited text only; it does not parse code or read the whole file. "
            + limit
        #expect(evidence.line(now: at(732)) == expected)
    }

    @Test func aBuildBetweenTheFailureAndThePassKeepsAdjacency() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            check(13, .build, .passed(.exitStatus), ends: 14),
            edit(16, ends: 17, before: counts(assertion: 1), after: counts()),
            check(20, .test, .passed(.exitStatus), ends: 21),
        ])
        #expect(clauses(evidence)?.effects == [.fewerAssertionMatches])
    }

    @Test func aChangeAtExactlyThePassesInstantIsNotClaused() {
        let evidence = build([
            check(10, .test, .failed(.exitStatus), ends: 12),
            check(20, .test, .passed(.exitStatus), ends: 21),
            edit(20, ends: 21, before: counts(assertion: 1), after: counts()),
        ])
        #expect(evidence.caseName == "changedAfterLastCheck")
        #expect(!evidence.line(now: at(732)).contains("Between a failed test run"))
    }
}
