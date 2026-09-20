import Foundation

/// Cost in US dollars per million tokens, split by the four chargeable classes.
///
/// `cacheCreation` is a cache *write*: you pay to fill the cache (typically
/// 1.25x the input rate). `cacheRead` is a cache *hit* (typically 0.1x the
/// input rate). Keeping them separate matters because a cache-heavy session is
/// dominated by cache reads, not by fresh input.
public struct ModelRate: Codable, Sendable, Equatable {
    public let input: Double
    public let output: Double
    public let cacheCreation: Double
    public let cacheRead: Double

    public init(input: Double, output: Double, cacheCreation: Double, cacheRead: Double) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
    }
}

/// Lookup table of model pricing. An unknown model returns `nil` — we would
/// rather under-report cost than invent a number.
public enum CostTable {
    // Rates last verified: 2026-09-19.
    private static let rates: [String: ModelRate] = [
        "claude-opus-5": ModelRate(input: 15.0, output: 75.0, cacheCreation: 18.75, cacheRead: 1.50),
        "claude-sonnet-5": ModelRate(input: 3.0, output: 15.0, cacheCreation: 3.75, cacheRead: 0.30),
        "claude-haiku-4-5": ModelRate(input: 1.0, output: 5.0, cacheCreation: 1.25, cacheRead: 0.10),
        "gpt-5.6": ModelRate(input: 1.25, output: 10.0, cacheCreation: 1.5625, cacheRead: 0.125),
        "deepseek-chat": ModelRate(input: 0.27, output: 1.10, cacheCreation: 0.3375, cacheRead: 0.027),
        "deepseek-reasoner": ModelRate(input: 0.55, output: 2.19, cacheCreation: 0.6875, cacheRead: 0.055),
    ]

    /// Normalizes a model string as reported by an adapter into a known key.
    /// Returns `nil` for anything unrecognized so the caller never guesses.
    public static func canonicalModel(_ model: String?) -> String? {
        guard let model else { return nil }
        let m = model.lowercased()

        if m.contains("opus") { return "claude-opus-5" }
        if m.contains("sonnet") { return "claude-sonnet-5" }
        if m.contains("haiku") { return "claude-haiku-4-5" }
        if m.contains("gpt-5.6") || m == "codex" { return "gpt-5.6" }
        if m.contains("reasoner") || m == "deepseek-r1" { return "deepseek-reasoner" }
        if m.contains("deepseek-chat") { return "deepseek-chat" }
        return nil
    }

    public static func rate(for model: String?) -> ModelRate? {
        guard let key = canonicalModel(model) else { return nil }
        return rates[key]
    }
}
