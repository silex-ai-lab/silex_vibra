import Foundation
import Testing
@testable import VibraCore

struct CostTableTests {
    @Test func modelsActuallyInUseResolve() {
        let inUse = [
            "gpt-6-astra",
            "gpt-5.6-sol",
            "deepseek-v4-pro",
            "deepseek-reasoner",
            "deepseek-chat",
        ]
        for model in inUse {
            #expect(CostTable.rate(for: model) != nil, "expected a rate for \(model)")
        }
    }

    @Test func unknownModelReturnsNil() {
        #expect(CostTable.rate(for: "gemini-3-flash") == nil)
        #expect(CostTable.rate(for: nil) == nil)
        #expect(CostTable.rate(for: "some-random-model") == nil)
    }

    @Test func gpt56SolAliasesGpt56() {
        #expect(CostTable.canonicalModel("gpt-5.6-sol") == "gpt-5.6")
        #expect(CostTable.rate(for: "gpt-5.6-sol") == CostTable.rate(for: "gpt-5.6"))
    }
}
