import Testing
@testable import VibraCore

struct RunnerSummaryTests {
    @Test func everyCaseInTheSharedFile() throws {
        let cases = try EvidenceCases.load().summary
        #expect(cases.count > 30)
        for item in cases {
            let kind = try #require(CheckKind(rawValue: item.kind))
            #expect(RunnerSummary.verdict(outputTail: item.tail, kind: kind) == item.verdict, "\(item.tail)")
        }
    }

    @Test func onlyTheTailIsRead() {
        let early = "Test run with 4 tests in 1 suites failed with 1 issue.\n"
        let filler = String(repeating: "x", count: RunnerSummary.tailBytes + 100)
        #expect(RunnerSummary.verdict(outputTail: early + filler, kind: .test) == nil)
        #expect(RunnerSummary.verdict(outputTail: filler + "\nBuild complete!", kind: .build) == true)
    }
}
