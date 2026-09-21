import Foundation

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
    private let windowDays: Int

    public init(
        adapters: [any AgentAdapter],
        reader: IncrementalLineReader = IncrementalLineReader(),
        windowDays: Int = 7
    ) {
        self.adapters = adapters
        self.reader = reader
        self.windowDays = windowDays
    }

    public private(set) var lastBytesRead: Int = 0

    public func collectSamples(now: Date = Date()) -> [AgentKind: [UsageSample]] {
        lastBytesRead = 0
        // Read a day wider than the report window: a file last written just
        // after midnight still contains records belonging to the previous day.
        let cutoff = now.addingTimeInterval(-Double(windowDays + 1) * 86_400)
        var result: [AgentKind: [UsageSample]] = [:]

        for adapter in adapters {
            guard adapter.isAvailable else { continue }
            var samples: [UsageSample] = []

            let sources = (try? adapter.sources()) ?? []
            for source in sources where source.modified >= cutoff {
                guard source.url.pathExtension == "jsonl" else { continue }
                var offset: UInt64 = 0
                while true {
                    guard let batch = try? reader.read(url: source.url, from: offset) else { break }
                    lastBytesRead += batch.bytesRead
                    let advanced = batch.nextOffset > offset
                    offset = batch.nextOffset
                    if batch.lines.isEmpty && !advanced { break }
                    // Drain per batch: JSONSerialization autoreleases, and a
                    // multi-hundred-megabyte pass without this was worth
                    // hundreds of megabytes of resident memory.
                    autoreleasepool {
                        samples.append(contentsOf: adapter.usageSamples(from: batch.lines))
                    }
                    if !advanced { break }
                }
            }

            // Adapters that cannot attribute usage in time still contribute
            // their totals, reported as undated rather than guessed onto a day.
            if samples.isEmpty, adapter.kind == .openCode {
                for session in adapter.discoverSessionsSafely() where session.usage.total > 0 {
                    samples.append(
                        UsageSample(timestamp: nil, model: session.model, usage: session.usage)
                    )
                }
            }

            if !samples.isEmpty { result[adapter.kind] = samples }
        }
        return result
    }
}
