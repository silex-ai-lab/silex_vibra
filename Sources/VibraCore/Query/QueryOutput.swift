import Foundation

/// What `Vibra --query` prints: the menu's live sessions as stable JSON, for
/// scripts and agents.
///
/// Never message content, and so **no titles**: OpenCode and Claude UI titles
/// are derived from message text. `project`, `cwd` and `id` identify a
/// session. Keys are sorted and dates are ISO 8601, so the output is stable.
public struct QueryOutput: Encodable, Sendable {
    public struct Settings: Encodable, Sendable, Equatable {
        public let stallThresholdSeconds: Double
        public let attentionDecaySeconds: Double
        public let activityWindowSeconds: Double
    }

    public struct Tokens: Encodable, Sendable, Equatable {
        public let input: Int
        public let output: Int
        public let cacheRead: Int
        public let cacheCreation: Int
    }

    public struct Row: Encodable, Sendable, Equatable {
        public let agent: String
        public let id: String
        public let project: String
        public let cwd: String
        public let gitBranch: String?
        public let state: String
        public let needsAttention: Bool
        public let lastEvent: String
        public let lastActivity: Date
        public let startedAt: Date
        public let model: String?
        public let tokens: Tokens
        /// Nil — encoded as `null`, never 0 — when the model has no published
        /// rate. Free and unknown must not look the same.
        public let estimatedCostUSD: Double?
        public let unattended: Bool

        enum CodingKeys: String, CodingKey {
            case agent, id, project, cwd, gitBranch, state, needsAttention, lastEvent
            case lastActivity, startedAt, model, tokens, estimatedCostUSD, unattended
        }

        // Written by hand so optionals are `null` rather than missing keys:
        // a consumer can rely on every key being present.
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(agent, forKey: .agent)
            try c.encode(id, forKey: .id)
            try c.encode(project, forKey: .project)
            try c.encode(cwd, forKey: .cwd)
            try c.encode(gitBranch, forKey: .gitBranch)
            try c.encode(state, forKey: .state)
            try c.encode(needsAttention, forKey: .needsAttention)
            try c.encode(lastEvent, forKey: .lastEvent)
            try c.encode(lastActivity, forKey: .lastActivity)
            try c.encode(startedAt, forKey: .startedAt)
            try c.encode(model, forKey: .model)
            try c.encode(tokens, forKey: .tokens)
            try c.encode(estimatedCostUSD, forKey: .estimatedCostUSD)
            try c.encode(unattended, forKey: .unattended)
        }
    }

    public let generatedAt: Date
    public let settings: Settings
    public let sessions: [Row]

    public init(
        sessions: [Session],
        settings: VibraSettings,
        now: Date,
        attentionOnly: Bool = false,
        agent: AgentKind? = nil
    ) {
        let aggregator = UsageAggregator()
        self.generatedAt = now
        self.settings = Settings(
            stallThresholdSeconds: settings.stallThresholdSeconds,
            attentionDecaySeconds: settings.attentionDecaySeconds,
            activityWindowSeconds: settings.activityWindowSeconds
        )
        self.sessions = sessions
            .filter { !attentionOnly || $0.state.needsAttention }
            .filter { agent == nil || $0.agent == agent }
            .map { s in
                Row(
                    agent: s.agent.rawValue,
                    id: s.id,
                    project: s.projectName,
                    cwd: s.cwd,
                    gitBranch: s.gitBranch,
                    state: s.state.rawValue,
                    needsAttention: s.state.needsAttention,
                    lastEvent: s.lastEvent.rawValue,
                    lastActivity: s.lastActivity,
                    startedAt: s.startedAt,
                    model: s.model,
                    tokens: Tokens(
                        input: s.usage.input,
                        output: s.usage.output,
                        cacheRead: s.usage.cacheRead,
                        cacheCreation: s.usage.cacheCreation
                    ),
                    estimatedCostUSD: aggregator.cost(for: s),
                    unattended: s.isUnattended
                )
            }
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
