import Foundation

/// Opaque per-source state an adapter carries between incremental updates.
///
/// The ingest layer stores and returns these without interpreting them: only
/// the adapter knows what it needs to remember to fold new records into a
/// running session summary (accumulated token usage, earliest timestamp, the
/// last event seen).
public protocol AdapterCheckpoint: Sendable {}

/// What the ingest layer hands an adapter for one update.
public enum SourceInput: Sendable {
    /// Newline-complete records appended since the last checkpoint.
    ///
    /// A partial trailing line is never included — a live agent is appending,
    /// and half a JSON object is not a record. `reset` is true when the file
    /// was replaced or truncated, meaning any previous checkpoint is invalid
    /// and these records are the whole file.
    case records([String], reset: Bool)

    /// The adapter should re-run its own query. Used for SQLite-backed
    /// sources, where reading a byte range is meaningless.
    case databaseSnapshot
}

/// Result of an incremental update: what to display, plus what to remember.
public struct ParsedState: Sendable {
    public var sessions: [Session]
    public var checkpoint: (any AdapterCheckpoint)?

    public init(sessions: [Session], checkpoint: (any AdapterCheckpoint)? = nil) {
        self.sessions = sessions
        self.checkpoint = checkpoint
    }

    public static let empty = ParsedState(sessions: [], checkpoint: nil)
}
