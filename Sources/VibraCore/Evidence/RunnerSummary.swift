import Foundation

/// Reads a runner's own summary line from the end of a check's output.
///
/// The two patterns are pinned by a separate oracle in `tools/evidence-oracle`.
/// Change one only together with the other. Failure is checked first, so a
/// tail that carries both reads as failed. No match is undecided, never a pass.
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

    /// true passed, false failed, nil undecided.
    static func verdict(outputTail: String) -> Bool? {
        let tail = String(decoding: Array(outputTail.utf8.suffix(tailBytes)), as: UTF8.self)
        let range = NSRange(tail.startIndex..., in: tail)
        if fail.firstMatch(in: tail, range: range) != nil { return false }
        if pass.firstMatch(in: tail, range: range) != nil { return true }
        return nil
    }
}
