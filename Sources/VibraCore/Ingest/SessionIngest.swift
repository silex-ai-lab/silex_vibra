import Foundation

/// Owns all mutable ingest state — descriptors, byte offsets, adapter
/// checkpoints and parsed sessions — and performs every disk read.
///
/// An actor, and deliberately not `@MainActor`: the previous design ran a full
/// re-parse of 339 MB on the main actor every 2 seconds. Since one pass took
/// ~13.4s and the timer fired every 2s, refreshes queued faster than they
/// drained, which is what pinned a core. Here the work is serialized off the
/// main thread and `SessionStore` awaits a plain `[Session]` snapshot.
public actor SessionIngest {
    private struct Entry {
        var descriptor: SourceDescriptor
        var offset: UInt64
        var state: ParsedState
    }

    private let adapters: [any AgentAdapter]
    private let reader: IncrementalLineReader
    private var entries: [URL: Entry] = [:]

    /// Cumulative bytes read from disk. The regression test asserts this does
    /// not move across a refresh where nothing changed — a count of parse
    /// calls alone would miss a wasted read that parsed nothing.
    public private(set) var bytesRead: Int = 0

    public init(
        adapters: [any AgentAdapter],
        reader: IncrementalLineReader = IncrementalLineReader()
    ) {
        self.adapters = adapters
        self.reader = reader
    }

    /// Bytes read during the most recent `refresh()`.
    public private(set) var lastRefreshBytesRead: Int = 0

    public func refresh() -> [Session] {
        lastRefreshBytesRead = 0
        var sessions: [Session] = []
        var seen: Set<URL> = []

        for adapter in adapters {
            guard adapter.isAvailable else { continue }

            let sources = (try? adapter.sources()) ?? []
            guard !sources.isEmpty else {
                // Adapter opted out of incremental ingest. Correct, just not
                // cheap — it full-parses every refresh.
                sessions.append(contentsOf: adapter.discoverSessionsSafely())
                continue
            }

            for source in sources {
                seen.insert(source.url)
                let previous = entries[source.url]

                if let previous, source.isUnchanged(from: previous.descriptor) {
                    // Nothing appended: reuse without touching the disk.
                    sessions.append(contentsOf: previous.state.sessions)
                    continue
                }

                let needsReset = previous.map { source.requiresReset(comparedTo: $0.descriptor) } ?? true
                let startOffset = needsReset ? 0 : (previous?.offset ?? 0)

                let input: SourceInput
                var nextOffset = startOffset
                if source.url.pathExtension == "jsonl" {
                    guard let result = try? reader.read(url: source.url, from: startOffset) else {
                        continue
                    }
                    bytesRead += result.bytesRead
                    lastRefreshBytesRead += result.bytesRead
                    nextOffset = result.nextOffset
                    input = .records(result.lines, reset: needsReset)
                } else {
                    input = .databaseSnapshot
                }

                let carried = needsReset ? nil : previous?.state
                guard let state = try? adapter.update(
                    source: source,
                    input: input,
                    previous: carried
                ) else { continue }

                entries[source.url] = Entry(
                    descriptor: source,
                    offset: nextOffset,
                    state: state
                )
                sessions.append(contentsOf: state.sessions)
            }
        }

        // Drop sources that vanished, so a deleted transcript stops being
        // reported and its cached bytes are released.
        for url in entries.keys where !seen.contains(url) {
            entries.removeValue(forKey: url)
        }

        return sessions.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Discards all cached state. Used when FSEvents reports dropped events
    /// and the safety rescan cannot trust its offsets.
    public func invalidateAll() {
        entries.removeAll()
    }

    public var trackedSourceCount: Int { entries.count }
}
