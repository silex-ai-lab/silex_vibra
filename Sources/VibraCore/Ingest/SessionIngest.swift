import Foundation

/// Owns all mutable ingest state — descriptors, byte offsets, adapter
/// checkpoints, parsed sessions and source health — and performs every disk
/// read.
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
        var agent: AgentKind
    }

    private let adapters: [any AgentAdapter]
    private let reader: IncrementalLineReader
    private var entries: [URL: Entry] = [:]

    /// Adapter -> source -> why its last read failed. Sticky: cleared only by a
    /// successful re-read of that source, or by the source leaving the listing.
    private var problems: [AgentKind: [URL: SourceProblem]] = [:]
    /// An adapter that opted out of incremental ingest has no URL to key a
    /// problem by, so its full-parse failure is recorded per adapter.
    private var fullParseProblems: [AgentKind: SourceProblem] = [:]
    /// Adapters whose `sources()` threw on the most recent pass. Recomputed
    /// every pass, so the next good listing clears it.
    private var listFailed: Set<AgentKind> = []
    /// Last time a source of this adapter was actually re-read successfully.
    private var lastSuccessAt: [AgentKind: Date] = [:]

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
    private var horizon: TimeInterval?

    /// What this ingest knows about each adapter's sources, recomputed on every
    /// refresh. Carries a problem kind and a date, never error text or a path.
    public private(set) var health: [AgentKind: SourceHealth] = [:]

    public init(
        adapters: [any AgentAdapter],
        reader: IncrementalLineReader = IncrementalLineReader(),
        horizon: TimeInterval? = 12 * 3600
    ) {
        self.adapters = adapters
        self.reader = reader
        self.horizon = horizon
    }

    /// Changes the freshness horizon, e.g. when the activity window setting
    /// changes. Checkpoints of sources already read are kept, so this costs no
    /// cold pass; a widened horizon just lets the next refresh consider
    /// sources it used to skip.
    public func setHorizon(_ horizon: TimeInterval?) {
        self.horizon = horizon
    }

    /// Bytes read during the most recent `refresh()`.
    public private(set) var lastRefreshBytesRead: Int = 0

    public func refresh() -> [Session] {
        lastRefreshBytesRead = 0
        let now = Date()
        var sessions: [Session] = []
        var seen: Set<URL> = []
        /// Adapters whose listing succeeded this pass. Only their vanished
        /// sources are pruned; one whose `sources()` threw keeps everything.
        var listedAgents: Set<AgentKind> = []

        for adapter in adapters {
            let kind = adapter.kind
            guard adapter.isAvailable else { continue }

            let sources: [SourceDescriptor]
            do {
                sources = try adapter.sources()
            } catch {
                listFailed.insert(kind)
                sessions.append(contentsOf: retainedSessions(of: kind))
                continue
            }
            listFailed.remove(kind)
            listedAgents.insert(kind)

            if sources.isEmpty {
                // Adapter opted out of incremental ingest, or every source it
                // had is gone. Correct, just not cheap — it full-parses every
                // refresh.
                do {
                    let discovered = try adapter.discoverSessions()
                    sessions.append(contentsOf: discovered)
                    fullParseProblems[kind] = nil
                    // Nothing is listed, so no per-source failure can still be
                    // true of this adapter.
                    problems[kind] = nil
                    // An empty result read nothing. Stamping it would change
                    // the snapshot on every idle pass.
                    if !discovered.isEmpty { lastSuccessAt[kind] = now }
                } catch {
                    fullParseProblems[kind] = Self.problem(for: error)
                    sessions.append(contentsOf: retainedSessions(of: kind))
                }
                continue
            }

            // A source that stopped being listed clears its failure; one that
            // is still listed keeps it until it is read successfully again.
            let listed = Set(sources.map(\.url))
            problems[kind] = problems[kind]?.filter { listed.contains($0.key) }

            for source in sources {
                // Skip stale sources without opening them. Cheap: we already
                // have the mtime from the stat done in sources().
                if let horizon, now.timeIntervalSince(source.modified) > horizon {
                    continue
                }
                seen.insert(source.url)
                let previous = entries[source.url]

                if let previous, source.isUnchanged(from: previous.descriptor) {
                    // Nothing appended: reuse without touching the disk. That
                    // also means no new success time, so an idle pass does not
                    // change the snapshot.
                    sessions.append(contentsOf: previous.state.sessions)
                    continue
                }

                let needsReset = previous.map { source.requiresReset(comparedTo: $0.descriptor) } ?? true
                let startOffset = needsReset ? 0 : (previous?.offset ?? 0)

                var nextOffset = startOffset
                var carried = needsReset ? nil : previous?.state
                var produced: ParsedState?
                var problem: SourceProblem?

                if source.url.pathExtension == "jsonl" {
                    // Fold in bounded batches. A cold pass over a large
                    // transcript would otherwise hold every line of the file
                    // in memory at once; folding is already incremental, so
                    // applying it repeatedly costs nothing extra.
                    var isFirstBatch = true
                    while true {
                        let result: IncrementalLineReader.Result
                        do {
                            result = try reader.read(url: source.url, from: nextOffset)
                        } catch {
                            problem = .readFailed
                            break
                        }
                        bytesRead += result.bytesRead
                        lastRefreshBytesRead += result.bytesRead

                        let advanced = result.nextOffset > nextOffset
                        nextOffset = result.nextOffset

                        if result.lines.isEmpty && !advanced {
                            if isFirstBatch, produced == nil, needsReset {
                                do {
                                    produced = try adapter.update(
                                        source: source,
                                        input: .records([], reset: true),
                                        previous: nil
                                    )
                                } catch {
                                    problem = .readFailed
                                }
                            }
                            break
                        }

                        do {
                            // JSONSerialization hands back autoreleased
                            // objects. Without draining per batch they
                            // accumulate for the whole cold pass - 342 MB of
                            // transcripts turned into ~880 MB resident before
                            // this pool was added.
                            produced = try autoreleasepool {
                                try adapter.update(
                                    source: source,
                                    input: .records(result.lines, reset: needsReset && isFirstBatch),
                                    previous: carried
                                )
                            }
                        } catch {
                            // A failure after a partial fold must not be cached:
                            // the offset is not committed, so the next pass
                            // retries the same bytes.
                            problem = .readFailed
                            break
                        }
                        carried = produced
                        isFirstBatch = false
                        if !advanced { break }
                    }
                } else {
                    do {
                        produced = try adapter.update(
                            source: source,
                            input: .databaseSnapshot(since: horizon.map { now.addingTimeInterval(-$0) }),
                            previous: carried
                        )
                    } catch {
                        problem = Self.problem(for: error)
                    }
                }

                if let problem {
                    record(problem, for: source.url, of: kind)
                    // Stale, not gone: the previous parse still describes the
                    // session, and dropping it would empty the menu on a
                    // transient read error.
                    if let previous {
                        sessions.append(contentsOf: previous.state.sessions)
                    }
                    continue
                }

                guard let state = produced else { continue }
                clearProblem(for: source.url, of: kind)
                lastSuccessAt[kind] = now
                entries[source.url] = Entry(
                    descriptor: source,
                    offset: nextOffset,
                    state: state,
                    agent: kind
                )
                sessions.append(contentsOf: state.sessions)
            }
        }

        // Drop sources that vanished, so a deleted transcript stops being
        // reported and its cached bytes are released.
        for (url, entry) in entries
        where listedAgents.contains(entry.agent) && !seen.contains(url) {
            entries.removeValue(forKey: url)
        }

        health = currentHealth()
        // Session ids come from agents' own files, and two files can claim one
        // id. Everything downstream is keyed by SessionKey, so the newest wins here.
        var claimed: Set<SessionKey> = []
        return sessions
            .sorted { $0.lastActivity > $1.lastActivity }
            .filter { claimed.insert($0.key).inserted }
    }

    /// Discards all cached state. Used when FSEvents reports dropped events
    /// and the safety rescan cannot trust its offsets.
    public func invalidateAll() {
        entries.removeAll()
    }

    public var trackedSourceCount: Int { entries.count }

    // MARK: - Health

    private func record(_ problem: SourceProblem, for url: URL, of kind: AgentKind) {
        problems[kind, default: [:]][url] = problem
    }

    private func clearProblem(for url: URL, of kind: AgentKind) {
        problems[kind]?[url] = nil
    }

    /// The sessions of an adapter's retained sources, used while its listing
    /// or read is failing.
    private func retainedSessions(of kind: AgentKind) -> [Session] {
        entries.values
            .filter { $0.agent == kind }
            .flatMap { $0.state.sessions }
    }

    private func currentHealth() -> [AgentKind: SourceHealth] {
        var result: [AgentKind: SourceHealth] = [:]
        for adapter in adapters {
            let kind = adapter.kind
            guard adapter.isAvailable else {
                result[kind] = .absent
                continue
            }
            if listFailed.contains(kind) {
                result[kind] = .failing(.listFailed, lastSuccess: lastSuccessAt[kind])
                continue
            }
            if let problem = fullParseProblems[kind] {
                result[kind] = .failing(problem, lastSuccess: lastSuccessAt[kind])
                continue
            }
            // Sorted so two failing sources always report the same one.
            if let problem = problems[kind]?
                .sorted(by: { $0.key.path < $1.key.path })
                .first?.value {
                result[kind] = .failing(problem, lastSuccess: lastSuccessAt[kind])
            } else {
                result[kind] = .ready(lastSuccess: lastSuccessAt[kind])
            }
        }
        return result
    }

    private static func problem(for error: any Error) -> SourceProblem {
        error is SourceSchemaError ? .parseFailed : .readFailed
    }
}
