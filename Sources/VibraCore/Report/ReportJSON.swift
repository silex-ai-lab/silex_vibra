import Foundation

/// The `--report --json` object. Built here so tests encode exactly what the
/// CLI prints; `main.swift` only writes the bytes out. Dates are ISO 8601.
/// Nothing in it is message text.
public enum ReportJSON {
    public static func encode(usage: UsageReport, window: ReportWindow, read: ReadStats, perf: PerfReport?) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(usage: usage, window: window, read: read, perf: perf))
    }

    private struct Document: Encodable {
        let usage: UsageReport
        let window: ReportWindow
        let read: ReadStats
        let perf: PerfReport?

        enum CodingKeys: String, CodingKey { case schema, window, read, agents, perf }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .schema)
            try container.encode(Window(days: window.days, start: window.start, now: window.now), forKey: .window)
            try container.encode(read, forKey: .read)
            try container.encode(usage.agents.map(Agent.init), forKey: .agents)
            // Explicit, so the key is present as `null` rather than absent.
            try container.encode(perf, forKey: .perf)
        }
    }

    private struct Window: Encodable {
        let days: Int
        let start: Date
        let now: Date
    }

    private struct Agent: Encodable {
        let agent: AgentKind
        let usage: TokenUsage
        let estimatedValue: Double
        let unpricedTokens: Int

        init(_ line: UsageReport.AgentLine) {
            agent = line.agent
            usage = line.usage
            estimatedValue = line.estimatedValue
            unpricedTokens = line.unpricedTokens
        }
    }
}
