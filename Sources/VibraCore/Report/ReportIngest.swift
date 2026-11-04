import Foundation

/// The final samples of one JSONL file.
public struct SourceSamples: Sendable {
    public let url: URL
    public let isSubagent: Bool
    /// Empty when the file holds no usage.
    public let samples: [UsageSample]

    public init(url: URL, isSubagent: Bool, samples: [UsageSample]) {
        self.url = url
        self.isSubagent = isSubagent
        self.samples = samples
    }
}

/// What one report read cost.
public struct ReadStats: Sendable, Equatable, Codable {
    /// Bytes read from disk. A batch that stops at the reader's line cap
    /// re-reads the rest of its chunk next time, so this can exceed the files'
    /// size.
    public let bytes: Int
    /// JSONL files whose read was attempted, counted once each.
    public let files: Int

    public init(bytes: Int, files: Int) {
        self.bytes = bytes
        self.files = files
    }
}

/// Everything one read of the window produced. The report and the perf
/// analyzer are both built from this, so one read serves both.
public struct ReportInput: Sendable {
    /// One entry per JSONL file read, empty or not.
    public let sources: [AgentKind: [SourceSamples]]
    /// OpenCode and Hermes session totals, which carry no timestamp.
    public let undated: [AgentKind: [UsageSample]]
    public let read: ReadStats

    public init(sources: [AgentKind: [SourceSamples]], undated: [AgentKind: [UsageSample]], read: ReadStats) {
        self.sources = sources
        self.undated = undated
        self.read = read
    }

    /// Sources plus undated, for the builder.
    public var samplesByAgent: [AgentKind: [UsageSample]] {
        var result: [AgentKind: [UsageSample]] = [:]
        for (agent, files) in sources {
            let samples = files.flatMap(\.samples)
            if !samples.isEmpty { result[agent, default: []] += samples }
        }
        for (agent, samples) in undated where !samples.isEmpty {
            result[agent, default: []] += samples
        }
        return result
    }
}

/// Reads a wider window than the status path, on demand only.
///
/// Deliberately holds **no state shared with `SessionIngest`**. If the two
/// shared byte offsets or checkpoints, opening the report would consume the
/// live monitor's unread bytes, or the monitor's 12-hour horizon would
/// silently truncate the report. They are separate readers over the same
/// files, and each starts from zero.
///
/// This runs when the user opens the report, never on the polling path. A
/// seven-day window measured ~62 MB across 35 files here — about two seconds,
/// which is fine for an explicit action and would be ruinous every two seconds.
public actor ReportIngest {
    private let adapters: [any AgentAdapter]
    private let reader: IncrementalLineReader

    public init(
        adapters: [any AgentAdapter],
        reader: IncrementalLineReader = IncrementalLineReader()
    ) {
        self.adapters = adapters
        self.reader = reader
    }

    public func collect(window: ReportWindow) -> ReportInput {
        var sources: [AgentKind: [SourceSamples]] = [:]
        var undated: [AgentKind: [UsageSample]] = [:]
        var bytes = 0
        var files = 0

        for adapter in adapters {
            guard adapter.isAvailable else { continue }
            var read: [SourceSamples] = []

            for source in (try? adapter.sources()) ?? [] where source.modified >= window.fileCutoff {
                guard source.url.pathExtension == "jsonl" else { continue }
                var sampler = adapter.makeUsageSampler(for: source.url)
                var samples: [UsageSample] = []
                bytes += foldLineBatches(of: source.url, reader: reader) { lines in
                    samples += sampler.add(lines)
                }
                samples += sampler.finish()
                read.append(SourceSamples(url: source.url, isSubagent: sampler.isSubagent, samples: samples))
            }
            files += read.count
            if !read.isEmpty { sources[adapter.kind] = read }

            // Adapters that cannot attribute usage in time still contribute
            // their totals, reported as undated rather than guessed onto a day.
            if adapter.reportsUndatedTotals, read.allSatisfy(\.samples.isEmpty) {
                let totals = adapter.discoverSessionsSafely()
                    .filter { $0.usage.total > 0 }
                    .map { UsageSample(timestamp: nil, model: $0.model, usage: $0.usage) }
                if !totals.isEmpty { undated[adapter.kind] = totals }
            }
        }
        return ReportInput(sources: sources, undated: undated, read: ReadStats(bytes: bytes, files: files))
    }
}
