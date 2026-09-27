import Foundation

/// Reads the questions you asked, on demand only.
///
/// Modelled on `ReportIngest`: a separate reader over the same files, starting
/// from byte zero, sharing no state with `SessionIngest`, and run only when the
/// History window opens. Nothing it reads is written anywhere.
public actor HistoryIngest {
    private let adapters: [any AgentAdapter]
    private let reader: IncrementalLineReader

    public init(adapters: [any AgentAdapter], reader: IncrementalLineReader = IncrementalLineReader()) {
        self.adapters = adapters
        self.reader = reader
    }

    /// JSONL reader bytes in the last `collect` (a database-only history
    /// reads 0 here, as `ReportIngest` counts it).
    public private(set) var lastBytesRead: Int = 0

    /// Every question in sources that may hold something from the last
    /// `windowDays` local days. This is a read bound, a day wider than the
    /// window; `HistoryIndex.build` applies the window per record.
    public func collect(windowDays: Int, now: Date = Date()) -> [QuestionRecord] {
        lastBytesRead = 0
        let cutoff = now.addingTimeInterval(-Double(HistoryIndex.clampDays(windowDays) + 1) * 86_400)
        var records: [QuestionRecord] = []

        for adapter in adapters {
            guard adapter.isAvailable else { continue }
            records.append(contentsOf: adapter.storedQuestions(since: cutoff))

            // No extractor: this adapter has no history, so none of its files
            // are read at all.
            guard adapter.historyExtractor() != nil else { continue }
            let sources = (try? adapter.sources()) ?? []
            for source in sources where source.modified >= cutoff && source.url.pathExtension == "jsonl" {
                guard var extractor = adapter.historyExtractor() else { break }
                var offset: UInt64 = 0
                while true {
                    guard let batch = try? reader.read(url: source.url, from: offset) else { break }
                    lastBytesRead += batch.bytesRead
                    let advanced = batch.nextOffset > offset
                    offset = batch.nextOffset
                    if batch.lines.isEmpty && !advanced { break }
                    // Drain per batch, as ReportIngest does.
                    autoreleasepool {
                        records.append(contentsOf: extractor.fold(batch.lines))
                    }
                    if !advanced { break }
                }
            }
        }
        return records
    }
}
