import Foundation

/// Reads one session's change and check evidence, on demand only.
///
/// Modelled on `HistoryIngest`: a separate reader over the same files,
/// starting from byte zero and sharing no state with `SessionIngest`. It runs
/// when the Session Details window asks, never on the poll path, and keeps
/// nothing between calls.
public actor EvidenceIngest {
    private let adapters: [any AgentAdapter]
    private let reader: IncrementalLineReader

    public init(adapters: [any AgentAdapter], reader: IncrementalLineReader = IncrementalLineReader()) {
        self.adapters = adapters
        self.reader = reader
    }

    /// JSONL reader bytes in the last `collect`.
    public private(set) var lastBytesRead: Int = 0

    /// nil when no adapter for the session's agent reads evidence, when its
    /// transcript is gone, or when the caller cancelled.
    public func collect(for session: Session) -> EvidenceFold? {
        lastBytesRead = 0
        guard let adapter = adapters.first(where: { $0.kind == session.agent && $0.isAvailable }),
              adapter.evidenceExtractor() != nil
        else { return nil }

        let sources = adapter.evidenceSources(for: session)
        guard !sources.isEmpty else { return nil }
        var merged = EvidenceFold()
        for url in sources {
            if Task.isCancelled { return nil }
            guard var extractor = adapter.evidenceExtractor() else { break }
            lastBytesRead += foldLineBatches(of: url, reader: reader) { extractor.fold($0) }
            let fold = extractor.finish()
            merged.events += fold.events
            merged.sawToolRecords = merged.sawToolRecords || fold.sawToolRecords
        }
        return merged
    }

    public func evidence(for session: Session) -> DeliveryEvidence? {
        collect(for: session).map {
            DeliveryEvidence.build(events: $0.events, sawToolRecords: $0.sawToolRecords)
        }
    }
}
