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

    private func claude(_ batches: [String]...) -> EvidenceFold { fold(ClaudeEvidenceExtractor(), batches: batches) }
    private func codex(_ batches: [String]...) -> EvidenceFold { fold(CodexEvidenceExtractor(), batches: batches) }

    private func check(_ kind: CheckKind, _ result: CheckResult, at seconds: TimeInterval) -> EvidenceEvent {
        .check(ObservedCheck(at: F.at(seconds), kind: kind, result: result))
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

    @Test func claudeChainSuccessProvesThePass() {
        let fold = claude([F.claudeBash("a", "cd x && swift test", at: 1), F.claudeResult("a", text: "", at: 2)])
        #expect(fold.events == [check(.test, .passed(.exitStatus), at: 1)])
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
        #expect(ok.events == [.codeChange(F.at(1))])
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
        #expect(fold.events == [.codeChange(F.at(1))])
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
        #expect(fold.events.contains(.codeChange(F.at(3))))
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
            "type": "CommandExecution", "status": "completed", "command": ["zsh", "-lc", "cd x && swift test"],
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
        #expect(fold.events == [.codeChange(F.at(1)), .codeChange(F.at(2))])
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
}
