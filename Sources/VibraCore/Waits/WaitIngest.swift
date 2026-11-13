import Foundation

/// Reads how long sessions waited on the human, on demand only.
///
/// Modelled on `HistoryIngest`: a separate reader over the same files, from
/// byte zero, one extractor per source, sharing no state with `SessionIngest`.
/// Run only by `--wait-stats`. It keeps nothing.
public actor WaitIngest {
    private let adapters: [any AgentAdapter]
    private let reader: IncrementalLineReader

    public init(adapters: [any AgentAdapter], reader: IncrementalLineReader = IncrementalLineReader()) {
        self.adapters = adapters
        self.reader = reader
    }

    /// JSONL reader bytes in the last `collect`.
    public private(set) var lastBytesRead: Int = 0

    /// One fold per `.jsonl` source modified at or after a day before `lo`. A
    /// file untouched since then cannot hold a wait ending at or after `lo`.
    public func collect(since lo: EpochMs) -> [(agent: AgentKind, fold: WaitFold)] {
        lastBytesRead = 0
        let cutoff = Date(timeIntervalSince1970: Double(lo) / 1000).addingTimeInterval(-86_400)
        var rows: [(agent: AgentKind, fold: WaitFold)] = []

        for adapter in adapters {
            guard adapter.isAvailable, adapter.waitExtractor() != nil else { continue }
            let sources = (try? adapter.sources()) ?? []
            for source in sources where source.modified >= cutoff && source.url.pathExtension == "jsonl" {
                guard var extractor = adapter.waitExtractor() else { break }
                var offset: UInt64 = 0
                while true {
                    guard let batch = try? reader.read(url: source.url, from: offset) else { break }
                    lastBytesRead += batch.bytesRead
                    let advanced = batch.nextOffset > offset
                    offset = batch.nextOffset
                    if batch.lines.isEmpty && !advanced { break }
                    autoreleasepool { extractor.fold(batch.lines) }
                    if !advanced { break }
                }
                rows.append((adapter.kind, extractor.finish()))
            }
        }
        return rows
    }
}
