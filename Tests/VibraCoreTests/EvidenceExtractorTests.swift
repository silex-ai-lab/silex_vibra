import Foundation
import Testing
@testable import VibraCore

struct EvidenceExtractorTests {
    typealias F = EvidenceFixtures

    private func fold(_ extractor: some EvidenceExtractor, batches: [[String]]) -> EvidenceFold {
        var extractor = extractor
        for batch in batches { extractor.fold(batch) }
        return extractor.finish()
    }

    private func claude(_ batches: [String]...) -> EvidenceFold { fold(ClaudeEvidenceExtractor(), batches: batches).issueOnly }
    private func codex(_ batches: [String]...) -> EvidenceFold { fold(CodexEvidenceExtractor(), batches: batches).issueOnly }

    private func check(_ kind: CheckKind, _ result: CheckResult, at seconds: TimeInterval) -> EvidenceEvent {
        .check(ObservedCheck(at: F.at(seconds), kind: kind, result: result))
    }

    // MARK: Test-path and count helpers

    private func firstChange(_ fold: EvidenceFold) -> CodeChange? {
        for event in fold.events {
            if case .codeChange(let change) = event { return change }
        }
        return nil
    }

    private func firstTarget(_ fold: EvidenceFold) -> CodeChangeTarget? { firstChange(fold)?.target }

    private func pathKey(_ target: CodeChangeTarget) -> PathKey? {
        guard case .test(path: let key, before: _, after: _) = target else { return nil }
        return key
    }

    private func compared(_ target: CodeChangeTarget) -> (before: PatternCounts, after: PatternCounts)? {
        guard case .test(_, before: let before?, after: let after?) = target else { return nil }
        return (before, after)
    }

    // MARK: Completion times

    @Test func completionTimesComeFromTheResultRecord() {
        let claude = fold(ClaudeEvidenceExtractor(), batches: [[
            F.claudeEdit("e", at: 1), F.claudeResult("e", text: "ok", at: 3),
            F.claudeBash("t", "swift test", at: 4), F.claudeResult("t", text: "ok", at: 9),
            F.claudeBash("u", "swift test", at: 10),
        ]])
        #expect(claude.events == [
            .codeChange(CodeChange(at: F.at(1), completedAt: F.at(3), target: .source)),
            .check(ObservedCheck(at: F.at(4), completedAt: F.at(9), kind: .test, result: .passed(.exitStatus))),
            .check(ObservedCheck(at: F.at(10), completedAt: nil, kind: .test, result: .unknown)),
        ])
        let codex = fold(CodexEvidenceExtractor(), batches: [[
            F.codexChange(["/work/a.swift"], at: 5), F.codexCommand("swift test", exit: 0, durationSeconds: 4, at: 12),
        ]])
        #expect(codex.events == [
            .codeChange(CodeChange(at: F.at(5), completedAt: F.at(5), target: .source)),
            .check(ObservedCheck(at: F.at(8), completedAt: F.at(12), kind: .test, result: .passed(.exitStatus))),
        ])
    }

    // MARK: Claude Code

    @Test func claudeExitVisibleTestUsesIsError() {
        let passed = claude([
            F.claudeBash("a", "swift test", at: 1), F.claudeResult("a", text: "ok", at: 2),
        ])
        #expect(passed.events == [check(.test, .passed(.exitStatus), at: 1)])
        let failed = claude([
            F.claudeBash("a", "swift test", at: 1), F.claudeResult("a", text: "Exit code 1", isError: true, at: 2),
        ])
        #expect(failed.events == [check(.test, .failed(.exitStatus), at: 1)])
    }

    @Test func claudeMaskedCheckIsNeverProvenByExitStatus() {
        let piped = claude([
            F.claudeBash("a", "swift test 2>&1 | tail -5", at: 1),
            F.claudeResult("a", text: "quiet output", at: 2),
        ])
        #expect(piped.events == [check(.test, .unknown, at: 1)])
    }

    @Test func claudeMaskedFailureIsNotAFailureWithoutASummary() {
        let grep = claude([
            F.claudeBash("a", "swift test | grep FAIL", at: 1),
            F.claudeResult("a", text: "", isError: true, at: 2),
        ])
        #expect(grep.events == [check(.test, .unknown, at: 1)])
    }

    @Test func claudeMaskedCheckReadsTheRunnerSummary() {
        let passed = claude([
            F.claudeBash("a", "swift test 2>&1 | tail -5", at: 1),
            F.claudeResult("a", text: "Test run with 4 tests in 1 suite passed after 0.1 seconds.", at: 2),
        ])
        #expect(passed.events == [check(.test, .passed(.runnerSummary), at: 1)])
        let failed = claude([
            F.claudeBash("a", "swift test; echo done", at: 1),
            F.claudeResult("a", text: "Executed 4 tests, with 1 failure\ndone", at: 2),
        ])
        #expect(failed.events == [check(.test, .failed(.runnerSummary), at: 1)])
    }

    @Test func claudeResultContentCanBeAListOfTextBlocks() {
        let fold = claude([
            F.claudeBash("a", "swift test | tail", at: 1),
            F.claudeResult("a", text: "Test run with 2 tests passed", asBlocks: true, at: 2),
        ])
        #expect(fold.events == [check(.test, .passed(.runnerSummary), at: 1)])
    }

    @Test(arguments: [
        "The user doesn't want to proceed with this tool use.",
        "The user doesn't want to take this action right now.",
    ])
    func claudeRejectedCallLeavesNoEvent(text: String) {
        let fold = claude([F.claudeBash("a", "swift test", at: 1), F.claudeResult("a", text: text, isError: true, at: 2)])
        #expect(fold.events.isEmpty)
        #expect(fold.sawToolRecords)
    }

    @Test func claudeBackgroundedCheckIsNeverExitProven() {
        let fold = claude([
            F.claudeUse("a", name: "Bash", input: ["command": "swift test", "run_in_background": true], at: 1),
            F.claudeResult("a", text: "Command running in background with ID: bash_1", at: 2),
        ])
        #expect(fold.events == [check(.test, .unknown, at: 1)])
    }

    @Test func claudeManuallyBackgroundedCheckIsNotAPass() {
        let fold = claude([
            F.claudeBash("a", "swift test", at: 1),
            F.claudeResult("a", text: "Command was manually backgrounded by user", at: 2),
        ])
        #expect(fold.events == [check(.test, .unknown, at: 1)])
    }

    @Test(arguments: ["Permission denied by policy", "Command timed out"])
    func claudeAnErrorWithoutAnExitCodeIsNotAFailure(text: String) {
        let fold = claude([F.claudeBash("a", "swift test", at: 1), F.claudeResult("a", text: text, isError: true, at: 2)])
        #expect(fold.events == [check(.test, .unknown, at: 1)])
    }

    @Test func claudeNoteAfterPartialOutputIsStillNotFinished() {
        let fold = claude([
            F.claudeBash("a", "swift test", at: 1),
            F.claudeResult("a", text: "Building...\n12 passed\nCommand was moved to the background (ID: x)", at: 2),
        ])
        #expect(fold.events == [check(.test, .unknown, at: 1)])
    }

    @Test(arguments: ["Exit code 1\nTests: 5 passed, 5 total", "Command timed out after 2m\n12 passed"])
    func claudeASummaryCannotOverruleACallThatDidNotExitCleanly(text: String) {
        let fold = claude([F.claudeBash("a", "cd x && npx jest", at: 1), F.claudeResult("a", text: text, isError: true, at: 2)])
        #expect(fold.events == [check(.test, .unknown, at: 1)])
    }

    @Test func claudeASummaryCanConfirmAFailureBehindAChain() {
        let fold = claude([
            F.claudeBash("a", "cd x && swift test", at: 1),
            F.claudeResult("a", text: "Exit code 1\nTest run with 3 tests failed", isError: true, at: 2),
        ])
        #expect(fold.events == [check(.test, .failed(.runnerSummary), at: 1)])
    }

    @Test(arguments: ["Permission to use Bash has been denied.", "Not started: same command", "[Tool call did not complete"])
    func claudeACallThatNeverStartedLeavesNoEvent(text: String) {
        let fold = claude([F.claudeBash("a", "swift test", at: 1), F.claudeResult("a", text: text, isError: true, at: 2)])
        #expect(fold.events.isEmpty)
    }

    @Test func claudeChainFailureDoesNotBlameTheCheck() {
        let fold = claude([
            F.claudeBash("a", "cd missing && swift test", at: 1),
            F.claudeResult("a", text: "Exit code 1\nno such directory", isError: true, at: 2),
        ])
        #expect(fold.events == [check(.test, .unknown, at: 1)])
    }

    @Test func claudeChainEndingInGrepIsNotProvenByItsFlag() {
        let fold = claude([F.claudeBash("a", "npm run lint && git diff --exit-code", at: 1), F.claudeResult("a", text: "", at: 2)])
        #expect(fold.events == [check(.lint, .unknown, at: 1)])
    }

    @Test(arguments: ["Exit code 143\nCommand timed out after 2m 0.0s", "Exit code 127\npytest: command not found"])
    func claudeAKilledOrMissingCommandIsNotAFailedCheck(text: String) {
        let fold = claude([F.claudeBash("a", "pytest", at: 1), F.claudeResult("a", text: text, isError: true, at: 2)])
        #expect(fold.events == [check(.test, .unknown, at: 1)])
    }

    @Test func aRunThatSelectedNothingIsNotAPass() {
        let fold = claude([
            F.claudeBash("a", "swift test --filter Nope", at: 1),
            F.claudeResult("a", text: "warning: No matching test cases were run", at: 2),
        ])
        #expect(fold.events == [check(.test, .unknown, at: 1)])
    }

    @Test func aChangedRecordShapeIsNotReadAsACleanSession() {
        let claudeFold = claude([F.claudeUse("a", name: "Edit", input: ["renamed": "/work/a.swift"], at: 1)])
        #expect(claudeFold.sawToolRecords == false)
    }

    @Test func claudeCheckWithoutAResultIsUnknownAtFinish() {
        let fold = claude([F.claudeBash("a", "swift build", at: 1)])
        #expect(fold.events == [check(.build, .unknown, at: 1)])
        #expect(fold.sawToolRecords)
    }

    @Test func claudeEditCountsOnlyWithASuccessfulResult() {
        let ok = claude([F.claudeEdit("e", at: 1), F.claudeResult("e", text: "updated", at: 2)])
        #expect(ok.events == [.codeChange(at: F.at(1))])
        let failed = claude([F.claudeEdit("e", at: 1), F.claudeResult("e", text: "no", isError: true, at: 2)])
        #expect(failed.events.isEmpty)
        let unanswered = claude([F.claudeEdit("e", at: 1)])
        #expect(unanswered.events.isEmpty)
        #expect(unanswered.sawToolRecords)
    }

    @Test(arguments: ["Edit", "Write", "MultiEdit", "NotebookEdit"])
    func claudeEveryEditingToolCounts(name: String) {
        let key = name == "NotebookEdit" ? "notebook_path" : "file_path"
        let fold = claude([
            F.claudeUse("e", name: name, input: [key: "/work/a.ipynb"], at: 1),
            F.claudeResult("e", text: "ok", at: 2),
        ])
        #expect(fold.events == [.codeChange(at: F.at(1))])
    }

    @Test(arguments: [
        "/work/README.md", "/work/notes.TXT", "/work/doc.rst", "/work/logo.png", "/work/a.pdf",
        "/tmp/scratch.swift", "/private/tmp/x/y.py", "/var/folders/ab/c/T/z.js", "/private/var/folders/ab/z.js",
    ])
    func claudeDocumentationAndScratchEditsAreNotCodeChanges(path: String) {
        let fold = claude([F.claudeEdit("e", path: path, at: 1), F.claudeResult("e", text: "ok", at: 2)])
        #expect(fold.events.isEmpty)
        #expect(fold.sawToolRecords)
    }

    @Test func claudePairsAcrossBatches() {
        let fold = claude(
            [F.claudeBash("a", "swift test", at: 1), F.claudeEdit("e", at: 3)],
            [F.claudeResult("a", text: "ok", at: 4)],
            [F.claudeResult("e", text: "ok", at: 5)])
        #expect(fold.events.count == 2)
        #expect(fold.events.contains(check(.test, .passed(.exitStatus), at: 1)))
        #expect(fold.events.contains(.codeChange(at: F.at(3))))
    }

    @Test func claudeReplayedToolUseDoesNotReopenAFinishedCall() {
        let use = F.claudeBash("a", "swift test", at: 1)
        let fold = claude(
            [use, F.claudeResult("a", text: "ok", at: 2)],
            [use])
        #expect(fold.events == [check(.test, .passed(.exitStatus), at: 1)])
    }

    @Test func claudeDuplicateToolUseCountsOnce() {
        let use = F.claudeBash("a", "swift test", at: 1)
        let fold = claude([use, use, F.claudeResult("a", text: "ok", at: 2)])
        #expect(fold.events == [check(.test, .passed(.exitStatus), at: 1)])
    }

    @Test func claudeIgnoresNonChecksButNotesToolRecords() {
        let fold = claude([
            F.claudeBash("a", "git commit -m \"make test\"", at: 1), F.claudeResult("a", text: "ok", at: 2),
        ])
        #expect(fold.events.isEmpty)
        #expect(fold.sawToolRecords)
    }

    @Test func claudeWithoutToolRecords() {
        let fold = claude([#"{"type":"user","message":{"role":"user","content":"hi"}}"#, "not json"])
        #expect(fold == EvidenceFold(events: [], sawToolRecords: false))
    }

    // MARK: Codex

    @Test func codexExitVisibleUsesTheExitCode() {
        let fold = codex([
            F.codexCommand("swift test", exit: 0, at: 10),
            F.codexCommand("swift build", exit: 1, at: 20),
        ])
        #expect(fold.events == [check(.test, .passed(.exitStatus), at: 10), check(.build, .failed(.exitStatus), at: 20)])
    }

    @Test func codexMaskedCheckReadsTheRunnerSummaryNotTheExitCode() {
        let fold = codex([
            F.codexCommand("swift test | grep FAIL", exit: 1, output: "", at: 10),
            F.codexCommand("swift test 2>&1 | tail", exit: 0, output: "Test run with 3 tests passed", at: 20),
        ])
        #expect(fold.events == [check(.test, .unknown, at: 10), check(.test, .passed(.runnerSummary), at: 20)])
    }

    @Test func codexCheckStartsAtCompletionMinusDuration() {
        let fold = codex([F.codexCommand("swift test", exit: 0, durationSeconds: 8, at: 20)])
        #expect(fold.events == [check(.test, .passed(.exitStatus), at: 12)])
    }

    @Test func codexShellWrapperScriptIsTheThirdElement() {
        let line = F.codexItem([
            "type": "CommandExecution", "status": "completed", "command": ["zsh", "-lc", "swift test"],
            "exit_code": 0, "aggregated_output": "", "duration": ["secs": 0, "nanos": 0],
        ], at: 5)
        #expect(codex([line]).events == [check(.test, .passed(.exitStatus), at: 5)])
        let bash = F.codexItem([
            "type": "CommandExecution", "command": ["bash", "-c", "git commit -m 'make test'"],
            "exit_code": 0, "aggregated_output": "", "duration": ["secs": 0, "nanos": 0],
        ], at: 5)
        #expect(codex([bash]).events.isEmpty)
    }

    @Test func codexFileChangeCountsWhenCompletedAndCode() {
        let fold = codex([
            F.codexChange(["/work/a.swift"], at: 1),
            F.codexChange(["/work/README.md", "/work/b.swift"], at: 2),
            F.codexChange(["/work/README.md"], at: 3),
            F.codexChange(["/work/c.swift"], status: "failed", at: 4),
            F.codexChange(["/tmp/d.swift"], at: 5),
        ])
        #expect(fold.events == [.codeChange(at: F.at(1)), .codeChange(at: F.at(2))])
        #expect(fold.sawToolRecords)
    }

    @Test func codexOtherRecordsDoNotSetToolRecords() {
        let message = F.codexItem(["type": "AgentMessage", "content": "x"], at: 1)
        let meta = #"{"type":"session_meta","payload":{"id":"x"}}"#
        #expect(codex([message, meta, "garbage"]) == EvidenceFold(events: [], sawToolRecords: false))
    }

    @Test func codexNonCheckCommandStillSetsToolRecords() {
        let fold = codex([F.codexCommand("ls", exit: 0, at: 1)])
        #expect(fold == EvidenceFold(events: [], sawToolRecords: true))
    }

    // MARK: Pattern counts

    @Test(arguments: [
        "assert x == 1", "XCTAssertEqual(a, b)", "#expect(x)", "#require(y)", "expect(z)",
        "value.should == 1", "t.Error(\"boom\")", "t.Fatalf(\"boom %v\", v)", "require.NoError(t, err)",
    ])
    func assertionFamilyMatches(text: String) {
        #expect(patternCounts(in: text).assertion == 1)
    }

    @Test(arguments: [
        "pytest.mark.skip", "pytest.mark.skipif(cond)", "it.skip(\"x\", f)", "test.skip(\"x\", f)",
        "describe.skip(\"x\", f)", "context.skip(\"x\")", "suite.skip(\"x\")", "pytest.skip(\"x\")",
        "this.skip()", "self.skipTest(\"x\")", "xit(\"x\", f)", "xdescribe(\"x\")", "XCTSkip(\"x\")",
        "@Disabled", ".disabled(\"x\")", "t.SkipNow()", "#[ignore]", "@unittest.skip(\"x\")",
    ])
    func skipFamilyMatches(text: String) {
        #expect(patternCounts(in: text).skip == 1)
    }

    @Test(arguments: [
        "it.only(\"x\", f)", "test.only(\"x\", f)", "describe.only(\"x\")", "context.only(\"x\")",
        "suite.only(\"x\")", "fit(\"x\", f)", "fdescribe(\"x\")",
    ])
    func focusFamilyMatches(text: String) {
        #expect(patternCounts(in: text).focus == 1)
    }

    @Test(arguments: [
        "pytest.mark.xfail", "withKnownIssue(\"x\") { }", "XCTExpectFailure(\"x\")",
        "@unittest.expectedFailure", "it.failing(\"x\", f)", "test.failing(\"x\", f)",
    ])
    func expectedFailureFamilyMatches(text: String) {
        #expect(patternCounts(in: text).expectedFailure == 1)
    }

    @Test(arguments: [
        "def test_foo():", "func testFoo() {", "@Test", "it(\"x\", f)", "test(\"x\", f)",
        "#[test]", "func TestFoo(t *testing.T) {",
    ])
    func testFunctionFamilyMatches(text: String) {
        #expect(patternCounts(in: text).testFunction == 1)
    }

    /// Ordinary code that contains one of the pattern words without being a
    /// test call. Every one of these must count nothing in every family.
    @Test(arguments: [
        "wait(", "exit(", "split(", ".shoulder", "latest(", "asser", "button.disabled",
        "iter().skip(1)", "stream.skip(n)", "re.test(x)", "require.resolve(", "qs.only(\"id\")",
        "model.fit(x)",
    ])
    func ordinaryCodeMatchesNoFamily(text: String) {
        #expect(patternCounts(in: text)
            == PatternCounts(assertion: 0, skip: 0, focus: 0, expectedFailure: 0, testFunction: 0))
    }

    /// The exact strings the plan lists as matches, each in its own family.
    @Test func thePinnedMatchesCount() {
        #expect(patternCounts(in: "require.NoError(").assertion == 1)
        #expect(patternCounts(in: "@Test(.disabled(\"x\"))").skip == 1)
        #expect(patternCounts(in: "@Test(.disabled(\"x\"))").testFunction == 1)
        #expect(patternCounts(in: "XCTExpectFailure(").expectedFailure == 1)
        #expect(patternCounts(in: "it.skip(").skip == 1)
        #expect(patternCounts(in: "self.skipTest(").skip == 1)
        #expect(patternCounts(in: "test.only(").focus == 1)
        #expect(patternCounts(in: "fit(").focus == 1)
        #expect(patternCounts(in: "test.failing(").expectedFailure == 1)
    }

    @Test func commentLinesAreDroppedBeforeCounting() {
        #expect(patternCounts(in: "// assert(x)").assertion == 0)
        #expect(patternCounts(in: "/* assert(x) */").assertion == 0)
        #expect(patternCounts(in: " * assert(x)").assertion == 0)
        #expect(patternCounts(in: "   # assert(x)").assertion == 0)
        #expect(patternCounts(in: "// assert(x)\nassert(y)").assertion == 1)
        #expect(patternCounts(in: "#expect(x)").assertion == 1)
        #expect(patternCounts(in: "#[test]").testFunction == 1)
        #expect(patternCounts(in: "#[ignore]").skip == 1)
        // No space after `#`, so the line is code to this rule: a known miss.
        #expect(patternCounts(in: "#assert(x)").assertion == 1)
        // `\s` in the pattern covers Unicode spaces, not just ASCII ones.
        #expect(patternCounts(in: "\u{00A0}// XCTAssert(x)").assertion == 0)
        // CRLF: lines split on the `\n` scalar, so a leading comment line drops
        // itself and not the assertions below it.
        #expect(patternCounts(in: "    assert a == 1\r\n    assert b == 2").assertion == 2)
        #expect(patternCounts(in: "    # check both\r\n    assert a == 1\r\n    assert b == 2").assertion == 2)
    }

    // MARK: Test paths

    @Test(arguments: [
        ("/Users/test/app/src/main.py", false),
        ("/Users/test/app/tests/test_x.py", true),
        ("/Users/test/app/conftest.py", true),
        ("/Users/test/app/tests/fixtures/a.py", false),
        ("/Users/test/app/test_data/x.py", false),
        ("/Users/test/app/Sources/App.swift", false),
        ("/Users/test/app/Sources/AppTests.swift", true),
        ("/Users/test/app/src/widget.spec.tsx", true),
        ("/Users/test/app/src/handler_test.go", true),
        ("tests/test_x.py", true),
        ("/Users/test/other/tests/main.py", false),
    ])
    func testPathBelowTheRoot(path: String, expected: Bool) {
        #expect(isTestPath(path, root: "/Users/test/app") == expected)
    }

    @Test(arguments: [
        ("/x/tests/main.py", false),
        ("/x/spec/main.js", false),
        ("/x/main_test.py", true),
        ("/x/conftest.py", true),
    ])
    func testPathWithNoRootIsDecidedByFileName(path: String, expected: Bool) {
        #expect(isTestPath(path, root: nil) == expected)
    }

    /// A repo whose own path contains a test word must not turn every file
    /// into a test edit.
    @Test func testPathIgnoresTheRootsOwnComponents() {
        #expect(isTestPath("/Users/jian/code/testing/app/main.py", root: "/Users/jian/code/testing/app") == false)
        #expect(isTestPath("/Users/jian/code/testing/app/tests/main.py", root: "/Users/jian/code/testing/app"))
    }

    // MARK: Claude Code test edits

    @Test func claudeTestEditCarriesCountsAndCompletionTime() throws {
        let fold = self.fold(ClaudeEvidenceExtractor(), batches: [[
            F.claudeEdit(
                "e", path: "tests/a.swift", old: "XCTAssertEqual(a, b)",
                new: "// XCTAssertEqual(a, b)", cwd: "/work/app", at: 1),
            F.claudeResult("e", text: "ok", at: 2),
        ]])
        let change = try #require(firstChange(fold))
        #expect(change.completedAt == F.at(2))
        let counts = try #require(compared(change.target))
        #expect(counts.before.assertion == 1)
        #expect(counts.after == PatternCounts(assertion: 0, skip: 0, focus: 0, expectedFailure: 0, testFunction: 0))
        #expect(change.target.statsName == "test.compared")
    }

    @Test(arguments: ["Write", "NotebookEdit"])
    func aWholeFileEditOnATestPathHasNoCounts(name: String) throws {
        let key = name == "NotebookEdit" ? "notebook_path" : "file_path"
        let fold = claude([
            F.claudeUse("e", name: name, input: [key: "tests/a.swift"], cwd: "/work/app", at: 1),
            F.claudeResult("e", text: "ok", at: 2),
        ])
        let target = try #require(firstTarget(fold))
        #expect(compared(target) == nil)
        #expect(target.statsName == "test.unseen")
    }

    @Test func aReplaceAllEditOnATestPathDropsItsCounts() throws {
        let fold = claude([
            F.claudeEdit(
                "e", path: "tests/a.swift", old: "assert(x)", new: "assert(y)",
                replaceAll: true, cwd: "/work/app", at: 1),
            F.claudeResult("e", text: "ok", at: 2),
        ])
        let target = try #require(firstTarget(fold))
        #expect(compared(target) == nil)
        #expect(target.statsName == "test.unseen")
    }

    @Test func aMultiEditWithAReplaceAllDropsItsCounts() throws {
        let fold = claude([
            F.claudeMultiEdit(
                "e", path: "tests/a.swift", edits: [(old: "assert(x)", new: "assert(y)")],
                replaceAll: true, cwd: "/work/app", at: 1),
            F.claudeResult("e", text: "ok", at: 2),
        ])
        let target = try #require(firstTarget(fold))
        #expect(target.statsName == "test.unseen")
        #expect(compared(target) == nil)
    }

    @Test func multiEditJoinsItsEditsBeforeCounting() throws {
        let fold = claude([
            F.claudeMultiEdit(
                "e", path: "tests/a.swift",
                edits: [(old: "assert(a)", new: "assert(a)\nassert(b)"),
                        (old: "it(\"x\")", new: "it.skip(\"x\")")],
                cwd: "/work/app", at: 1),
            F.claudeResult("e", text: "ok", at: 2),
        ])
        let target = try #require(firstTarget(fold))
        let counts = try #require(compared(target))
        #expect(counts.before == PatternCounts(assertion: 1, skip: 0, focus: 0, expectedFailure: 0, testFunction: 1))
        #expect(counts.after == PatternCounts(assertion: 2, skip: 1, focus: 0, expectedFailure: 0, testFunction: 0))
    }

    @Test func editsToOneFileShareAKeyAndAnotherFileDoesNot() throws {
        let fold = claude([
            F.claudeEdit("a", path: "tests/a.swift", old: "assert(x)", new: "assert(y)", cwd: "/work/app", at: 1),
            F.claudeResult("a", text: "ok", at: 2),
            F.claudeEdit("b", path: "tests/a.swift", old: "assert(y)", new: "assert(z)", cwd: "/work/app", at: 3),
            F.claudeResult("b", text: "ok", at: 4),
            F.claudeEdit("c", path: "tests/b.swift", old: "assert(x)", new: "assert(y)", cwd: "/work/app", at: 5),
            F.claudeResult("c", text: "ok", at: 6),
        ])
        let keys = fold.events.compactMap { event -> PathKey? in
            guard case .codeChange(let change) = event else { return nil }
            return pathKey(change.target)
        }
        try #require(keys.count == 3)
        #expect(keys[0] == keys[1])
        #expect(keys[0] != keys[2])
    }

    @Test func claudeResolvesATestPathAgainstTheRecordsCwd() throws {
        let withRoot = claude([
            F.claudeEdit("e", path: "tests/a.swift", old: "assert(x)", new: "assert(y)", cwd: "/work/app", at: 1),
            F.claudeResult("e", text: "ok", at: 2),
        ])
        let withRootTarget = try #require(firstTarget(withRoot))
        #expect(withRootTarget.statsName == "test.compared")

        let withoutRoot = claude([
            F.claudeEdit("e", path: "tests/a.swift", old: "assert(x)", new: "assert(y)", at: 1),
            F.claudeResult("e", text: "ok", at: 2),
        ])
        let withoutRootTarget = try #require(firstTarget(withoutRoot))
        #expect(withoutRootTarget == .source)
        #expect(withoutRootTarget.statsName == "source")
    }

    @Test func aScratchOrDocumentationPathStaysExcludedEvenIfItLooksLikeATest() {
        let scratch = claude([
            F.claudeEdit("e", path: "/tmp/tests/a.swift", old: "assert(x)", new: "", at: 1),
            F.claudeResult("e", text: "ok", at: 2),
        ])
        #expect(scratch.events.isEmpty)
        let docs = claude([
            F.claudeEdit("e", path: "docs/test_guide.md", old: "assert(x)", new: "", cwd: "/work/app", at: 1),
            F.claudeResult("e", text: "ok", at: 2),
        ])
        #expect(docs.events.isEmpty)
    }

    // MARK: Codex test edits

    @Test func codexTestChangeHasNoCountsButKeepsItsCompletionTime() throws {
        let fold = self.fold(CodexEvidenceExtractor(), batches: [[
            F.codexMeta(cwd: "/work/app", at: 0),
            F.codexChange(["tests/a.swift"], at: 5),
        ]])
        let change = try #require(firstChange(fold))
        #expect(change.completedAt == F.at(5))
        #expect(change.target.statsName == "test.unseen")
        #expect(compared(change.target) == nil)
    }

    @Test func codexTakesTheFirstTestPathInSortedOrder() throws {
        let fold = codex([
            F.codexMeta(cwd: "/work/app", at: 0),
            F.codexChange(["tests/z.swift", "tests/a.swift", "src/main.swift"], at: 1),
        ])
        let target = try #require(firstTarget(fold))
        let key = try #require(pathKey(target))
        #expect(key == PathKey(path: "/work/app/tests/a.swift"))
    }

    @Test func codexResolvesATestPathAgainstTheLatestWorkspaceRoot() throws {
        let fold = codex([
            F.codexMeta(cwd: "/work/app", at: 0),
            F.codexChange(["/work/app/tests/a.swift"], at: 1),
            F.codexTurnContext(cwd: "/work/app/tests", at: 2),
            F.codexChange(["/work/app/tests/b.swift"], at: 3),
            F.codexTurnContext(cwd: "/work/app", at: 4),
            F.codexChange(["/work/app/tests/b.swift"], at: 5),
        ])
        let targets = fold.events.compactMap { event -> CodeChangeTarget? in
            guard case .codeChange(let change) = event else { return nil }
            return change.target
        }
        try #require(targets.count == 3)
        #expect(targets[0].statsName == "test.unseen")
        // cd-ed into tests/: the directory is the root now, so it does not count.
        #expect(targets[1] == .source)
        #expect(targets[2].statsName == "test.unseen")
    }

    /// A file named after a metadata record puts that token in the change's own
    /// JSON. The record's type must decide, or the edit disappears.
    @Test(arguments: ["session_meta", "turn_context"])
    func codexAFileNamedLikeAMetadataRecordIsStillAChange(name: String) throws {
        let named = self.fold(CodexEvidenceExtractor(), batches: [[
            F.codexMeta(cwd: "/work/app", at: 0),
            F.codexChange([name], at: 5),
            F.codexCommand("swift test", exit: 0, at: 9),
        ]])
        #expect(named.events == [
            .codeChange(CodeChange(at: F.at(5), completedAt: F.at(5), target: .source)),
            .check(ObservedCheck(at: F.at(9), completedAt: F.at(9), kind: .test, result: .passed(.exitStatus))),
        ])
        #expect(named.sawToolRecords)

        let ordinary = self.fold(CodexEvidenceExtractor(), batches: [[
            F.codexMeta(cwd: "/work/app", at: 0),
            F.codexChange(["src/a.swift"], at: 5),
            F.codexCommand("swift test", exit: 0, at: 9),
        ]])
        #expect(named.events == ordinary.events)

        let evidence = DeliveryEvidence.build(events: named.events, sawToolRecords: named.sawToolRecords)
        #expect(evidence.caseName == "checkedAfterLastChange")
    }
}
