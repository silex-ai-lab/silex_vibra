import Testing
@testable import VibraCore

struct RunnerSummaryTests {
    @Test(arguments: [
        "Test run with 12 tests in 3 suites failed after 0.4 seconds with 2 issues.",
        "Test Suite 'All tests' failed at 2026-11-08.\n\t Executed 12 tests, with 2 failures (0 unexpected) in 0.1 seconds",
        "===== 3 failed, 10 passed in 1.20s =====",
        "test result: FAILED. 4 passed; 1 failed; 0 ignored",
        "FAIL\tgithub.com/x/y\t0.3s",
        "error: fatal error in swift-build",
        "Tests:       2 failed, 8 passed, 10 total",
        "make: *** [test] Error 2",
        "** BUILD FAILED **",
        "process exit=2",
    ])
    func failures(tail: String) {
        #expect(RunnerSummary.verdict(outputTail: tail) == false)
    }

    @Test(arguments: [
        "Test run with 12 tests in 3 suites passed after 0.4 seconds.",
        "Executed 12 tests, with 0 failures (0 unexpected) in 0.1 seconds",
        "===== 10 passed in 1.20s =====",
        "test result: ok. 4 passed; 0 failed; 0 ignored",
        "ok  \tgithub.com/x/y\t0.3s",
        "Tests:       8 passed, 8 total",
        "Build complete! (2.1s)",
        "** BUILD SUCCEEDED **",
        "All checks passed!",
        "Success: no issues found in 3 source files",
    ])
    func passes(tail: String) {
        #expect(RunnerSummary.verdict(outputTail: tail) == true)
    }

    @Test(arguments: ["", "compiling...", "grep: nothing", "3 files changed"])
    func undecided(tail: String) {
        #expect(RunnerSummary.verdict(outputTail: tail) == nil)
    }

    @Test func failureBeatsPass() {
        let tail = "Build complete! (2.1s)\nTest run with 4 tests passed\n1 failed"
        #expect(RunnerSummary.verdict(outputTail: tail) == false)
    }

    @Test func onlyTheTailIsRead() {
        let early = "Test run with 4 tests in 1 suites failed with 1 issue.\n"
        let filler = String(repeating: "x", count: RunnerSummary.tailBytes + 100)
        #expect(RunnerSummary.verdict(outputTail: early + filler) == nil)
        #expect(RunnerSummary.verdict(outputTail: filler + "\nBuild complete!") == true)
    }
}
