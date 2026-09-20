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

    /// Sources untouched for longer than this are never opened.
    ///
    /// This is the difference between parsing 342 MB to display four sessions
    /// and parsing almost nothing. A transcript not written to in this long
    /// cannot contain activity inside the display window, so reading it is
    /// pure waste. Set nil to read everything (used by full-parse tests).
    private let horizon: TimeInterval?

    public init(
        adapters: [any AgentAdapter],
        reader: IncrementalLineReader = IncrementalLineReader(),
        horizon: TimeInterval? = 12 * 3600
    ) {
        self.adapters = adapters
        self.reader = reader
        self.horizon = horizon
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

            let now = Date()
            for source in sources {
                // Skip stale sources without opening them. Cheap: we already
                // have the mtime from the stat done in sources().
                if let horizon, now.timeIntervalSince(source.modified) > horizon {
                    continue
                }
                seen.insert(source.url)
                let previous = entries[source.url]

                if let previous, source.isUnchanged(from: previous.descriptor) {
                    // Nothing appended: reuse without touching the disk.
                    sessions.append(contentsOf: previous.state.sessions)
                    continue
                }

                let needsReset = previous.map { source.requiresReset(comparedTo: $0.descriptor) } ?? true
                let startOffset = needsReset ? 0 : (previous?.offset ?? 0)

                var nextOffset = startOffset
                var carried = needsReset ? nil : previous?.state
                var produced: ParsedState?

                if source.url.pathExtension == "jsonl" {
                    // Fold in bounded batches. A cold pass over a large
                    // transcript would otherwise hold every line of the file
                    // in memory at once; folding is already incremental, so
                    // applying it repeatedly costs nothing extra.
                    var isFirstBatch = true
                    while true {
                        guard let result = try? reader.read(url: source.url, from: nextOffset) else { break }
                        bytesRead += result.bytesRead
                        lastRefreshBytesRead += result.bytesRead

                        let advanced = result.nextOffset > nextOffset
                        nextOffset = result.nextOffset

                        if result.lines.isEmpty && !advanced {
                            if isFirstBatch, produced == nil, needsReset {
                                produced = try? adapter.update(
                                    source: source,
                                    input: .records([], reset: true),
                                    previous: nil
                                )
                            }
                            break
                        }

                        // JSONSerialization hands back autoreleased objects.
                        // Without draining per batch they accumulate for the
                        // whole cold pass - 342 MB of transcripts turned into
                        // ~880 MB resident before this pool was added.
                        produced = autoreleasepool {
                            try? adapter.update(
                                source: source,
                                input: .records(result.lines, reset: needsReset && isFirstBatch),
                                previous: carried
                            )
                        }
                        carried = produced
                        isFirstBatch = false
                        if !advanced { break }
                    }
                } else {
                    produced = try? adapter.update(
                        source: source,
                        input: .databaseSnapshot,
                        previous: carried
                    )
                }

                guard let state = produced else { continue }
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
