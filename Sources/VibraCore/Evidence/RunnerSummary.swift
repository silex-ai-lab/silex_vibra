import Foundation

/// Reads a runner's own summary line from the end of a check's output.
///
/// The patterns are pinned by a separate oracle in `tools/evidence-oracle`, and
/// both run the same case file. Change one only together with the other. The
/// last line that matches decides, and on that line failure beats pass. A pass
/// after an earlier failure line is undecided: output can quote a failure (a
/// test named "...failed") or hold two runs, and neither may be called a pass
/// or a failure on that alone.
///
/// A pass names the kind it proves, and a zero count proves nothing: a test run
/// prints "Build complete!" before any test executes, and can run no tests.
enum RunnerSummary {
    static let tailBytes = 6000

    private static let fail = regex(
        #"Test run with \d+ tests?.*failed|with [1-9]\d* issues?|Executed \d+ tests?, with [1-9]\d* failure|\b[1-9]\d* failed\b|\b[1-9]\d* errors?\b|test result: FAILED|^FAIL\b|error: fatal|Tests:\s+[1-9]\d* failed|\*\*\* \[|BUILD FAILED|TEST FAILED|Segmentation fault|signal code \d+|threshold.*not met|does not meet.*threshold|fatal runtime error|process didn't exit successfully|SIGABRT|SIGSEGV|error: test failed"#)
    private static let nothingRan = regex(
        #"No matching test cases|no tests to run|running 0 tests|^Tests:\s+\d+ skipped, \d+ total"#)
    private static let pass: [CheckKind: NSRegularExpression] = [
        .test: regex(
            #"Test run with [1-9]\d* tests?.*passed|Executed [1-9]\d* tests?, with 0 failures|\b[1-9]\d* passed\b|test result: ok\. [1-9]\d* passed|Tests:\s+[1-9]\d* passed|TEST SUCCEEDED"#),
        .build: regex(#"Build complete!|BUILD SUCCEEDED"#),
        .lint: regex(#"All checks passed|Success: no issues"#),
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // A malformed literal is a programmer error that every test exercises.
        try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
    }

    private static func matches(_ pattern: NSRegularExpression?, _ line: String) -> Bool {
        pattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// The run exited cleanly because it selected nothing to do.
    static func ranNothing(outputTail: String) -> Bool {
        let tail = String(decoding: Array(outputTail.utf8.suffix(tailBytes)), as: UTF8.self)
        return matches(nothingRan, tail)
    }

    /// true passed, false failed, nil undecided.
    static func verdict(outputTail: String, kind: CheckKind) -> Bool? {
        let tail = String(decoding: Array(outputTail.utf8.suffix(tailBytes)), as: UTF8.self)
        var endsInPass = false
        for line in tail.split(whereSeparator: \.isNewline).reversed().map(String.init) {
            if matches(fail, line) { return endsInPass ? nil : false }
            if matches(pass[kind], line) { endsInPass = true }
        }
        return endsInPass ? true : nil
    }
}
