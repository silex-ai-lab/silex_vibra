import Foundation

/// Watches Claude Code and Codex transcripts for incidents.
///
/// A separate reader with offsets of its own, sharing no state with
/// `SessionIngest`. Offsets are deliberately not persisted: replaying each file
/// from byte 0 at launch rebuilds all detection state, so a denial before a
/// restart still pairs with its retry after one, and stable ids keep the user's
/// answers.
public actor IncidentMonitor {
    public struct PollStats: Sendable, Equatable {
        public let bytesRead: Int
        public let newIncidents: Int
        public let delivered: Int
    }

    private struct Tracked {
        var deviceID: UInt64
        var fileID: UInt64
        var lastSize: Int64
        var lastModified: Date
        var offset: UInt64
        var extractor: any IncidentExtractor
        var ids: Set<IncidentID>
    }

    private struct Found {
        var extracted: ExtractedIncident
        var sources: Set<URL>
    }

    public static let notificationKey = "incident:review"
    private static let scanWindow: TimeInterval = 7 * 86_400

    private let adapters: [any AgentAdapter]
    private let store: IncidentStore
    private let reader: IncrementalLineReader
    private let now: @Sendable () -> Date
    private let deliveryInterval: TimeInterval
    private let deliver: @Sendable (AttentionNotification) -> Void
    private let notifies: Bool

    private var tracked: [URL: Tracked] = [:]
    private var found: [IncidentID: Found] = [:]
    private var vendor: [IncidentID: Incident] = [:]
    private var pending: [IncidentID: Date] = [:]
    private var lastDelivery: Date?
    private var started = false

    public init(
        adapters: [any AgentAdapter],
        store: IncidentStore,
        reader: IncrementalLineReader = IncrementalLineReader(),
        now: @escaping @Sendable () -> Date = { Date() },
        deliveryInterval: TimeInterval = 60,
        notifies: Bool = true,
        deliver: @escaping @Sendable (AttentionNotification) -> Void
    ) {
        self.adapters = adapters
        self.store = store
        self.reader = reader
        self.now = now
        self.deliveryInterval = deliveryInterval
        self.notifies = notifies
        self.deliver = deliver
    }

    @discardableResult
    public func poll() async -> PollStats {
        let date = now()
        if !started {
            started = true
            if notifies { _ = await store.initializeWatermark(date) }
        }
        let watermark = await store.watermark() ?? date
        let cutoff = date.addingTimeInterval(-Self.scanWindow)
        let answers = await store.dispositions()

        var bytes = 0
        var discovered = 0
        var scanned = Set<URL>()
        for adapter in adapters where adapter.isAvailable && adapter.incidentExtractor() != nil {
            for source in (try? adapter.sources()) ?? []
            where source.url.pathExtension == "jsonl" && source.modified >= cutoff {
                scanned.insert(source.url)
                let result = read(source, adapter: adapter)
                bytes += result.bytes
                for item in result.extracted {
                    let isNew = merge(item, from: source.url)
                    if isNew { discovered += 1 }
                    guard notifies, item.incident.kind.rule.severity == .review, item.incident.completedAt > watermark
                    else { continue }
                    if isNew || Self.reopens(item.incident, answer: answers[item.incident.id]) {
                        pending[item.incident.id] = item.incident.completedAt
                    }
                }
            }
        }
        for url in Array(tracked.keys) where !scanned.contains(url) {
            forget(url)
        }
        let delivered = await deliverPending(at: date)
        return PollStats(bytesRead: bytes, newIncidents: discovered, delivered: delivered)
    }

    private func read(_ source: SourceDescriptor, adapter: any AgentAdapter) -> (extracted: [ExtractedIncident], bytes: Int) {
        var state: Tracked
        var changed = false
        if let existing = tracked[source.url], !needsReset(existing, source) {
            state = existing
            changed = source.size != existing.lastSize
        } else {
            if tracked[source.url] != nil { forget(source.url) }
            guard let extractor = adapter.incidentExtractor() else { return ([], 0) }
            state = Tracked(
                deviceID: source.deviceID, fileID: source.fileID, lastSize: source.size,
                lastModified: source.modified, offset: 0, extractor: extractor, ids: [])
            changed = true
        }

        var extracted: [ExtractedIncident] = []
        var bytes = 0
        if changed {
            var reading = true
            while reading {
                // The read belongs inside the pool too: a Task's thread never
                // drains one, so Foundation's buffers would pile up for the
                // whole replay.
                autoreleasepool {
                    guard let batch = try? reader.read(url: source.url, from: state.offset) else {
                        reading = false
                        return
                    }
                    bytes += batch.bytesRead
                    reading = batch.nextOffset > state.offset
                    state.offset = batch.nextOffset
                    extracted += state.extractor.fold(batch.lines)
                }
            }
        }
        state.lastSize = source.size
        state.lastModified = source.modified
        state.ids.formUnion(extracted.map(\.incident.id))
        tracked[source.url] = state
        return (extracted, bytes)
    }

    private func needsReset(_ state: Tracked, _ source: SourceDescriptor) -> Bool {
        source.deviceID != state.deviceID
            || source.fileID != state.fileID
            || source.size < Int64(state.offset)
            || (source.size == state.lastSize && source.modified != state.lastModified)
    }

    /// True the first time this id is seen. The earliest `at` wins when a
    /// session's main and subagent files report the same id.
    private func merge(_ item: ExtractedIncident, from url: URL) -> Bool {
        guard var existing = found[item.incident.id] else {
            found[item.incident.id] = Found(extracted: item, sources: [url])
            return true
        }
        existing.sources.insert(url)
        let current = existing.extracted
        existing.extracted = ExtractedIncident(
            incident: Incident(
                id: current.incident.id,
                kind: current.incident.kind,
                agent: current.incident.agent,
                evidence: current.incident.evidence,
                at: min(current.incident.at, item.incident.at),
                completedAt: max(current.incident.completedAt, item.incident.completedAt),
                posture: current.incident.posture,
                detail: current.incident.detail),
            rawSessionID: current.rawSessionID)
        found[item.incident.id] = existing
        return false
    }

    private func forget(_ url: URL) {
        guard let state = tracked.removeValue(forKey: url) else { return }
        for id in state.ids {
            guard var entry = found[id] else { continue }
            entry.sources.remove(url)
            found[id] = entry.sources.isEmpty ? nil : entry
        }
    }

    /// An answer on a session-wide write finding covers only the writes it saw.
    private static func reopens(_ incident: Incident, answer: Disposition?) -> Bool {
        guard incident.kind == .writeToPathOutsideWorkspace, let date = answer?.date else { return false }
        return incident.completedAt > date
    }

    /// Commit, then deliver. A crash before the commit delivers nothing and
    /// the next replay finds the batch. A crash after it loses one notification
    /// and never duplicates it.
    private func deliverPending(at date: Date) async -> Int {
        guard let newest = pending.values.max() else { return 0 }
        if let lastDelivery, date.timeIntervalSince(lastDelivery) < deliveryInterval { return 0 }
        guard await store.commit(watermark: newest) else { return 0 }
        let count = pending.count
        pending.removeAll()
        lastDelivery = date
        deliver(AttentionNotification(
            key: Self.notificationKey,
            sessionID: "",
            title: "Agent activity to review",
            body: count == 1 ? "1 item to review." : "\(count) items to review."))
        return count
    }

    /// Findings from an imported usage file. They live for the app run, never
    /// notify and never touch the watermark.
    public func addVendorIncidents(_ incidents: [Incident]) {
        for incident in incidents { vendor[incident.id] = incident }
    }

    /// The answers and the watermark are the store's. A diagnostic reader
    /// passes `notifies: false` so it can never silence an alert.
    /// Newest first, with the user's answers.
    public func rows() async -> [IncidentJSON.Row] {
        let answers = await store.dispositions()
        return (found.values.map(\.extracted.incident) + vendor.values)
            .sorted { ($0.completedAt, $0.id.hex) > ($1.completedAt, $1.id.hex) }
            .map { IncidentJSON.Row(incident: $0, disposition: Self.reopens($0, answer: answers[$0.id]) ? .open : answers[$0.id] ?? .open) }
    }

    /// For Jump to session only.
    public func rawSessionID(for id: IncidentID) -> String? {
        found[id]?.extracted.rawSessionID
    }
}
