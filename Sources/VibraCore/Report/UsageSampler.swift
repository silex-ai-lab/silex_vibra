import Foundation

/// How an adapter turns one source's records into additive usage samples.
///
/// One sampler per file. It may hold state between `add` calls, because the
/// reader hands over a file in bounded batches and a source's records are not
/// independent: Claude Code writes one API response as several records, and a
/// Codex rollout names its model once at the top. Only samples that are final
/// come back from `add`; `finish` releases whatever is still pending at the
/// end of the file.
public protocol UsageSampler: Sendable {
    /// The source is a subagent transcript.
    var isSubagent: Bool { get }
    mutating func add(_ lines: [String]) -> [UsageSample]
    mutating func finish() -> [UsageSample]
}

/// The default sampler: the adapter cannot attribute usage in time, so its
/// totals are reported as undated rather than guessed onto a day.
public struct EmptyUsageSampler: UsageSampler {
    public let isSubagent = false

    public init() {}

    public mutating func add(_ lines: [String]) -> [UsageSample] { [] }
    public mutating func finish() -> [UsageSample] { [] }
}
