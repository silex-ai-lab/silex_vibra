import Foundation
import Testing
@testable import VibraCore

/// Drives the vendor importer and the reconcile by exact numbers. Every figure
/// here is derived by hand from the plan's formula table; each formula test
/// also pins the plausible wrong sum.
struct VendorUsageTests {
    // MARK: - Helpers

    private func day(_ iso: String) -> UTCDay { UTCDay(iso: iso)! }
    private func instant(_ iso: String) -> Date { parseISODate(iso)! }
    private func after() -> Date { instant("2025-08-03T00:00:00Z") }

    private func load(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL("Fixtures/\(name)"))
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func anthropicPage() throws -> [String: Any] {
        try object(try load("vendor-usage-anthropic.json"))
    }

    private func firstResult(_ root: [String: Any]) -> [String: Any] {
        let buckets = root["data"] as? [[String: Any]] ?? []
        let results = buckets.first?["results"] as? [[String: Any]] ?? []
        return results.first ?? [:]
    }

    /// A copy of `root` with the first bucket's first result edited.
    private func editingFirstResult(
        _ root: [String: Any], _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        var copy = root
        var buckets = copy["data"] as? [[String: Any]] ?? []
        var results = buckets.first?["results"] as? [[String: Any]] ?? []
        var first = results.first ?? [:]
        body(&first)
        if results.isEmpty { results = [first] } else { results[0] = first }
        buckets[0]["results"] = results
        copy["data"] = buckets
        return try data(copy)
    }

    private func editingFirstBucket(
        _ root: [String: Any], _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        var copy = root
        var buckets = copy["data"] as? [[String: Any]] ?? []
        var first = buckets.first ?? [:]
        body(&first)
        buckets[0] = first
        copy["data"] = buckets
        return try data(copy)
    }

    private func failure(_ data: Data, now: Date) -> VendorImportError? {
        do {
            _ = try VendorUsage.parse(data, now: now)
            return nil
        } catch let error as VendorImportError {
            return error
        } catch {
            return nil
        }
    }

    private func isUnrecognisedShape(_ error: VendorImportError?) -> Bool {
        if case .unrecognisedShape = error { return true }
        return false
    }

    private func file(_ tokens: Int, day iso: String = "2025-08-01", key: String = "key_a") -> VendorUsageFile {
        VendorUsageFile(provider: .anthropic, apiKeyID: key, days: [VendorDay(day: day(iso), tokens: tokens)])
    }

    private func local(_ tokens: Int, day iso: String = "2025-08-01") -> [LocalDay] {
        [LocalDay(day: day(iso), tokens: tokens)]
    }

    // MARK: - Fixtures

    @Test func anthropicFixtureParses() throws {
        let parsed = try VendorUsage.parse(try load("vendor-usage-anthropic.json"), now: after())
        #expect(parsed.provider == .anthropic)
        #expect(parsed.apiKeyID == "apikey_01Rj2N8SVvo6BePZj99NhmiT")
        #expect(parsed.days == [VendorDay(day: day("2025-08-01"), tokens: 2200)])
        #expect(parsed.oldestDay == day("2025-08-01"))
    }

    @Test func openAIFixtureParses() throws {
        let parsed = try VendorUsage.parse(try load("vendor-usage-openai.json"), now: after())
        #expect(parsed.provider == .openai)
        #expect(parsed.apiKeyID == "apikey_openai_demo_0001")
        #expect(parsed.days == [
            VendorDay(day: day("2025-08-01"), tokens: 1100),
            VendorDay(day: day("2025-08-02"), tokens: 2200),
        ])
    }

    // MARK: - The four formulas

    @Test func anthropicFileSumsBothCacheCreationFields() throws {
        let page: [String: Any] = [
            "data": [[
                "starting_at": "2025-08-01T00:00:00Z",
                "results": [[
                    "api_key_id": "k",
                    "uncached_input_tokens": 1000,
                    "cache_read_input_tokens": 200,
                    "cache_creation": [
                        "ephemeral_1h_input_tokens": 300,
                        "ephemeral_5m_input_tokens": 400,
                    ],
                    "output_tokens": 100,
                ]],
            ]],
            "has_more": false,
        ]
        let parsed = try VendorUsage.parse(try data(page), now: after())
        #expect(parsed.days.map(\.tokens) == [2000])  // 1000 + 200 + 300 + 400 + 100
        #expect(parsed.days.map(\.tokens) != [1700])  // the sum without the 1h tier
    }

    @Test func openAIFileExcludesCachedInput() throws {
        let page: [String: Any] = [
            "object": "page",
            "data": [[
                "start_time": 1_754_006_400,
                "results": [[
                    "api_key_id": "k",
                    "input_tokens": 1000,
                    "output_tokens": 100,
                    "input_cached_tokens": 400,
                ]],
            ]],
            "has_more": false,
        ]
        let parsed = try VendorUsage.parse(try data(page), now: after())
        #expect(parsed.days.map(\.tokens) == [1100])  // 1000 + 100, cached is a subset
        #expect(parsed.days.map(\.tokens) != [1500])  // the sum that double-counts cache
    }

    @Test func anthropicLocalSumsEverythingBilled() {
        let usage = TokenUsage(input: 1000, output: 100, cacheCreation: 300, cacheRead: 200)
        let sample = UsageSample(timestamp: instant("2025-08-01T12:00:00Z"), model: "m", usage: usage)
        let days = VendorUsage.localDays(from: [sample], provider: .anthropic)
        #expect(days.map(\.tokens) == [1600])
        #expect(days.map(\.tokens) != [1100])  // input + output alone
    }

    @Test func openAIFileWithoutTheOptionalCachedFieldParses() throws {
        let page: [String: Any] = [
            "object": "page", "has_more": false, "next_page": NSNull(),
            "data": [[
                "object": "bucket", "start_time": 1_754_006_400, "end_time": 1_754_092_800,
                "results": [["input_tokens": 1000, "output_tokens": 100, "api_key_id": "key_1"]],
            ]],
        ]
        let file = try VendorUsage.parse(
            JSONSerialization.data(withJSONObject: page), now: Date(timeIntervalSince1970: 1_754_179_200))
        #expect(file.days.map(\.tokens) == [1100])
    }

    @Test func openAILocalNeverUsesTotal() {
        let usage = TokenUsage(input: 1000, output: 100, cacheCreation: 300, cacheRead: 200)
        let sample = UsageSample(timestamp: instant("2025-08-01T12:00:00Z"), model: "m", usage: usage)
        let days = VendorUsage.localDays(from: [sample], provider: .openai)
        #expect(days.map(\.tokens) == [1100])  // input + output; cached is inside input
        #expect(days.map(\.tokens) != [1600])  // TokenUsage.total
    }

    // MARK: - Local days

    @Test func undatedSamplesAreSkipped() {
        let samples = [
            UsageSample(timestamp: nil, model: nil, usage: TokenUsage(input: 999)),
            UsageSample(timestamp: instant("2025-08-01T00:00:00Z"), model: nil, usage: TokenUsage(input: 10)),
        ]
        #expect(VendorUsage.localDays(from: samples, provider: .openai).map(\.tokens) == [10])
    }

    @Test func samplesBucketByTheirOwnUTCDay() {
        let samples = [
            UsageSample(timestamp: instant("2025-08-01T23:59:59Z"), model: nil, usage: TokenUsage(input: 100)),
            UsageSample(timestamp: instant("2025-08-02T00:00:00Z"), model: nil, usage: TokenUsage(input: 200)),
        ]
        let days = VendorUsage.localDays(from: samples, provider: .openai)
        #expect(days == [
            LocalDay(day: day("2025-08-01"), tokens: 100),
            LocalDay(day: day("2025-08-02"), tokens: 200),
        ])
    }

    @Test func localDaysDoNotDependOnSampleOrder() {
        let first = UsageSample(timestamp: instant("2025-08-01T01:00:00Z"), model: nil, usage: TokenUsage(input: 100))
        let second = UsageSample(timestamp: instant("2025-08-02T01:00:00Z"), model: nil, usage: TokenUsage(input: 200))
        let third = UsageSample(timestamp: instant("2025-08-01T02:00:00Z"), model: nil, usage: TokenUsage(input: 50))
        let inOrder = VendorUsage.localDays(from: [first, third, second], provider: .openai)
        let shuffled = VendorUsage.localDays(from: [second, first, third], provider: .openai)
        #expect(inOrder == shuffled)
        #expect(inOrder.map(\.tokens) == [150, 200])
    }

    @Test func windowDaysReachesBackToTheOldestDay() throws {
        let parsed = try VendorUsage.parse(try load("vendor-usage-openai.json"), now: after())
        let oldest = try #require(parsed.oldestDay)
        #expect(VendorUsage.windowDays(oldest: oldest, now: after()) == 4)
        // The file's newest day is 2025-08-02; weeks later only the oldest
        // day still sets the cutoff, so the read reaches it.
        #expect(VendorUsage.windowDays(oldest: oldest, now: instant("2025-09-01T00:00:00Z")) == 33)
    }

    // MARK: - Refusals

    @Test func aFileThatIsNotJSONIsRefused() {
        #expect(failure(Data("not json".utf8), now: after()) == .notJSON)
    }

    @Test func wrongShapesAreRefusedAndNameTheExpectedKeys() throws {
        let page = try anthropicPage()
        // A top-level array, a page without `data`, a bucket without a start,
        // a result without a token field, and a non-page object.
        #expect(isUnrecognisedShape(failure(Data("[1, 2]".utf8), now: after())))
        #expect(isUnrecognisedShape(failure(try data(["foo": 1]), now: after())))
        #expect(isUnrecognisedShape(failure(try editingFirstBucket(page) { $0.removeValue(forKey: "starting_at") }, now: after())))
        #expect(isUnrecognisedShape(failure(try editingFirstResult(page) { $0.removeValue(forKey: "output_tokens") }, now: after())))
        #expect(isUnrecognisedShape(failure(
            try editingFirstResult(page) { $0["cache_creation"] = ["ephemeral_5m_input_tokens": 0] }, now: after())))
        // The text names keys, never a value from the file.
        if case .unrecognisedShape(let expected) = failure(try data(["foo": 1]), now: after()) {
            #expect(expected.contains("api_key_id"))
            #expect(!expected.contains("2025-08-01"))
        } else {
            Issue.record("expected an unrecognised shape")
        }
    }

    @Test func aPageWithoutHasMoreIsRefused() throws {
        let page = try anthropicPage()
        var without = page
        without.removeValue(forKey: "has_more")
        #expect(failure(try data(without), now: after()) == .partialPage)
    }

    @Test func aPartialPageIsRefused() throws {
        var page = try anthropicPage()
        page["has_more"] = true
        #expect(failure(try data(page), now: after()) == .partialPage)
    }

    @Test func aNullKeyOnAResultWithUsageIsRefused() throws {
        let page = try anthropicPage()
        let nulled = try editingFirstResult(page) { $0["api_key_id"] = NSNull() }
        #expect(failure(nulled, now: after()) == .noSingleKey)
    }

    @Test func twoKeysInOnePageAreRefused() throws {
        let page = try anthropicPage()
        let second = try editingFirstResult(page) { $0["api_key_id"] = "apikey_other" }
        // Append the second result to the same bucket.
        var copy = try object(second)
        var buckets = copy["data"] as? [[String: Any]] ?? []
        var results = buckets[0]["results"] as? [[String: Any]] ?? []
        results.append(firstResult(page))
        buckets[0]["results"] = results
        copy["data"] = buckets
        #expect(failure(try data(copy), now: after()) == .noSingleKey)
    }

    @Test func aPageWithNoUsageIsValidAndHasNoKey() throws {
        // The same page with the key removed and every token count zero.
        let page = try anthropicPage()
        let empty = try editingFirstResult(page) { result in
            result["api_key_id"] = NSNull()
            result["uncached_input_tokens"] = 0
            result["cache_read_input_tokens"] = 0
            result["output_tokens"] = 0
            result["cache_creation"] = [
                "ephemeral_1h_input_tokens": 0,
                "ephemeral_5m_input_tokens": 0,
            ]
        }
        let parsed = try VendorUsage.parse(empty, now: after())
        #expect(parsed.apiKeyID == "")
        #expect(parsed.days == [VendorDay(day: day("2025-08-01"), tokens: 0)])
        #expect(parsed.provider == .anthropic)
    }

    @Test func twoResultsWithOneKeyAreSummed() throws {
        let page = try anthropicPage()
        var copy = page
        var buckets = copy["data"] as? [[String: Any]] ?? []
        var results = buckets[0]["results"] as? [[String: Any]] ?? []
        results.append(firstResult(page))
        buckets[0]["results"] = results
        copy["data"] = buckets
        let parsed = try VendorUsage.parse(try data(copy), now: after())
        #expect(parsed.days.map(\.tokens) == [4400])
    }

    @Test func aFileOlderThanTheLimitIsRefused() throws {
        // 2025-06-01 with now 2025-08-03 is 63 days: one past the limit.
        let tooOld = try editingFirstBucket(try anthropicPage()) { $0["starting_at"] = "2025-06-01T00:00:00Z" }
        #expect(failure(tooOld, now: after()) == .tooOld)
        let atTheLimit = try editingFirstBucket(try anthropicPage()) { $0["starting_at"] = "2025-06-02T00:00:00Z" }
        #expect(failure(atTheLimit, now: after()) == nil)
    }

    // MARK: - Reconcile

    @Test func theFixedFloorFiresOnlyAboveIt() {
        // 10 percent of 1,000,000 is 100,000, so the fixed floor is the arm.
        let above = VendorUsage.reconcile(file(1_000_000), local: local(899_999), now: after())
        #expect(above.incidents.count == 1)
        let at = VendorUsage.reconcile(file(1_000_000), local: local(900_000), now: after())
        #expect(at.incidents.isEmpty)
    }

    @Test func tenPercentFiresOnlyAboveIt() {
        // 10 percent of 2,000,000 is 200,000, above the floor.
        let above = VendorUsage.reconcile(file(2_000_000), local: local(1_799_999), now: after())
        #expect(above.incidents.count == 1)
        let at = VendorUsage.reconcile(file(2_000_000), local: local(1_800_000), now: after())
        #expect(at.incidents.isEmpty)
    }

    @Test func localAboveVendorIsNeverAFinding() {
        let result = VendorUsage.reconcile(file(100_000), local: local(200_000), now: after())
        #expect(result.incidents.isEmpty)
        #expect(result.unreconciled.isEmpty)
    }

    @Test func daysBeforeLocalCoverageAndTodayAreUnreconciled() {
        let f = VendorUsageFile(provider: .anthropic, apiKeyID: "key_a", days: [
            VendorDay(day: day("2025-08-01"), tokens: 10),
            VendorDay(day: day("2025-08-06"), tokens: 0),
            VendorDay(day: day("2025-08-07"), tokens: 10),
        ])
        let result = VendorUsage.reconcile(f, local: local(0, day: "2025-08-05"), now: instant("2025-08-07T00:00:00Z"))
        #expect(result.unreconciled == [day("2025-08-01"), day("2025-08-07")])
        #expect(result.incidents.isEmpty)
    }

    @Test func noLocalSamplesMeansEveryDayIsUnreconciled() {
        let f = VendorUsageFile(provider: .anthropic, apiKeyID: "key_a", days: [
            VendorDay(day: day("2025-08-01"), tokens: 500_000),
            VendorDay(day: day("2025-08-02"), tokens: 500_000),
        ])
        let result = VendorUsage.reconcile(f, local: [], now: after())
        #expect(result.incidents.isEmpty)
        #expect(result.unreconciled == [day("2025-08-01"), day("2025-08-02")])
    }

    @Test func aLaterDayWithNoLocalUsageStillFires() {
        let f = VendorUsageFile(provider: .anthropic, apiKeyID: "key_a", days: [
            VendorDay(day: day("2025-08-01"), tokens: 100),
            VendorDay(day: day("2025-08-02"), tokens: 500_000),
        ])
        let result = VendorUsage.reconcile(f, local: local(100, day: "2025-08-01"), now: after())
        #expect(result.incidents.count == 1)
        #expect(result.incidents.first?.detail == .vendorExcess(VendorExcess(
            provider: .anthropic, day: day("2025-08-02"), vendorTokens: 500_000, localTokens: 0)))
    }

    @Test func anIncidentCarriesOnlyTheProviderDayAndCounts() throws {
        let result = VendorUsage.reconcile(file(500_000, key: "key_a"), local: local(0), now: after())
        let incident = try #require(result.incidents.first)
        #expect(incident.kind == .unexplainedVendorUsage)
        #expect(incident.agent == nil)
        #expect(incident.evidence == .vendorFile)
        #expect(incident.posture == .unknown)
        #expect(incident.at == day("2025-08-01").start)
        #expect(incident.completedAt == day("2025-08-01").start)
        #expect(incident.detail == .vendorExcess(VendorExcess(
            provider: .anthropic, day: day("2025-08-01"), vendorTokens: 500_000, localTokens: 0)))
        #expect(incident.id == IncidentID(
            agent: nil, session: nil, kind: .unexplainedVendorUsage,
            anchor: "anthropic|2025-08-01|key_a"))
    }

    @Test func identitySurvivesAReimportWithChangedAmounts() throws {
        let first = VendorUsage.reconcile(file(500_000), local: local(0), now: after())
        let again = VendorUsage.reconcile(file(900_000), local: local(0), now: after())
        let firstID = try #require(first.incidents.first?.id)
        let againID = try #require(again.incidents.first?.id)
        #expect(firstID == againID)
    }

    @Test func twoKeysOnTheSameDayGetDifferentIdentities() throws {
        let one = VendorUsage.reconcile(file(500_000, key: "key_a"), local: local(0), now: after())
        let two = VendorUsage.reconcile(file(500_000, key: "key_b"), local: local(0), now: after())
        let firstID = try #require(one.incidents.first?.id)
        let secondID = try #require(two.incidents.first?.id)
        #expect(firstID != secondID)
    }

    // MARK: - Error text

    @Test func errorTextNeverEchoesAKeyOrAValue() throws {
        let key = "apikey_01Rj2N8SVvo6BePZj99NhmiT"
        let page = try anthropicPage()
        var partial = page
        partial["has_more"] = true
        var twoKeys = page
        twoKeys["data"] = [[
            "starting_at": "2025-08-01T00:00:00Z",
            "results": [
                firstResult(page),
                ["api_key_id": "apikey_other", "uncached_input_tokens": 1, "cache_read_input_tokens": 0,
                 "cache_creation": ["ephemeral_1h_input_tokens": 0, "ephemeral_5m_input_tokens": 0],
                 "output_tokens": 0],
            ],
        ]]
        let samples = [
            failure(Data("nope".utf8), now: after()),
            failure(try data(["foo": 1]), now: after()),
            failure(try data(partial), now: after()),
            failure(try editingFirstResult(page) { $0["api_key_id"] = NSNull() }, now: after()),
            failure(try data(twoKeys), now: after()),
            failure(try editingFirstBucket(page) { $0["starting_at"] = "2025-06-01T00:00:00Z" }, now: after()),
        ]
        for error in samples {
            let text = try #require(error).description
            #expect(!text.contains(key))
            #expect(!text.contains("apikey_other"))
            #expect(!text.contains("2025-08-01"))
            #expect(!text.contains("1500"))
        }
    }
}
