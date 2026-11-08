import Foundation

/// Reads a runner's own summary line from the end of a check's output.
///
/// The two patterns are pinned by a separate oracle in `tools/evidence-oracle`.
/// Change one only together with the other. The last line that matches decides,
/// and on that line failure beats pass. A pass after an earlier failure line is
/// undecided: output can quote a failure (a test named "...failed") or hold two
/// runs, and neither may be called a pass or a failure on that alone.
enum RunnerSummary {
    static let tailBytes = 6000

    private static let fail = regex(
        #"Test run with \d+ tests?.*failed|with [1-9]\d* issues?|Executed \d+ tests?, with [1-9]\d* failure|\b[1-9]\d* failed\b|test result: FAILED|^FAIL\b|error: fatal|Tests:\s+[1-9]\d* failed|\*\*\* \[|BUILD FAILED|exit[=: ]+[1-9]"#)
    private static let pass = regex(
        #"Test run with \d+ tests?.*passed|Executed \d+ tests?, with 0 failures|\b\d+ passed\b|test result: ok|^ok\s+\S+|Tests:\s+\d+ passed|Build complete!|BUILD SUCCEEDED|exit[=: ]+0\b|All checks passed|Success: no issues"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // A malformed literal is a programmer error that every test exercises.
        try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
    }

    private static func matches(_ pattern: NSRegularExpression, _ line: String) -> Bool {
        pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// true passed, false failed, nil undecided.
    static func verdict(outputTail: String) -> Bool? {
        let tail = String(decoding: Array(outputTail.utf8.suffix(tailBytes)), as: UTF8.self)
        var endsInPass = false
        for line in tail.split(whereSeparator: \.isNewline).reversed().map(String.init) {
            if matches(fail, line) { return endsInPass ? nil : false }
            if matches(pass, line) { endsInPass = true }
        }
        return endsInPass ? true : nil
    }
}
