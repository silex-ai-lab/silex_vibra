import Foundation
import CoreServices

/// Incrementally reads a JSONL file that a live agent is appending to.
///
/// Maintains a per-file byte offset so a coalesced change event never re-emits
/// records it already parsed, buffers a torn trailing line until a later read
/// completes it, and resets the offset when the file is truncated or replaced.
public struct JSONLIncrementalReader {
    public private(set) var offset: UInt64 = 0
    private var pending = Data()
    private var lastInode: UInt64?

    public init() {}

    /// Drops the byte offset and any buffered partial line. Used when the
    /// watched file is truncated or replaced, or when FSEvents reports that it
    /// dropped events and a full rescan is required.
    public mutating func reset() {
        offset = 0
        pending.removeAll(keepingCapacity: true)
        lastInode = nil
    }

    /// Reads any bytes appended since the last call and returns every complete
    /// newline-terminated record. A torn trailing line is held back until a
    /// later call completes it; it is never parsed as a malformed record.
    public mutating func readRecords(from url: URL) throws -> [Data] {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? UInt64) ?? 0
        let inode = (attrs[.systemNumber] as? UInt64) ?? 0

        // Replacement (new inode) or truncation (size went backwards) both
        // invalidate the offset: start over from byte zero.
        if let lastInode, lastInode != inode {
            reset()
        } else if size < offset {
            reset()
        }
        lastInode = inode

        guard size > offset else { return [] }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let bytes = handle.readDataToEndOfFile()
        offset += UInt64(bytes.count)

        return appendBytes(bytes)
    }

    /// Feeds raw bytes through the line buffer, returning every complete
    /// record. Empty lines are skipped; a trailing partial record is retained.
    public mutating func appendBytes(_ data: Data) -> [Data] {
        var buffer = pending
        buffer.append(data)

        var records: [Data] = []
        var start = buffer.startIndex
        while start < buffer.endIndex, let newline = buffer[start...].firstIndex(of: 0x0A) {
            let line = buffer[start..<newline]
            start = buffer.index(after: newline)
            if !line.isEmpty { records.append(Data(line)) }
        }
        pending = Data(buffer[start...])
        return records
    }
}

/// Watches the JSONL trees with FSEvents and polls SQLite databases with a
/// timer, invoking `onChange` whenever something changes.
///
/// `@unchecked Sendable` because all mutable state is confined to the private
/// serial `queue`; the only value that crosses threads is the `@Sendable`
/// `onChange` handler.
public final class FileWatcher: @unchecked Sendable {
    public typealias ChangeHandler = @Sendable ([URL]) -> Void

    private let watchedDirectories: [URL]
    private let pollURLs: [URL]
    private let onChange: ChangeHandler

    private let queue = DispatchQueue(label: "vibra.filewatcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pollTimer: DispatchSourceTimer?
    private var lastPollSignatures: [URL: [PollStamp]] = [:]

    public init(
        watchedDirectories: [URL],
        pollURLs: [URL] = [],
        onChange: @escaping ChangeHandler
    ) {
        self.watchedDirectories = watchedDirectories
        self.pollURLs = pollURLs
        self.onChange = onChange
    }

    /// Starts watching. Fires an initial "rescan everything" callback so a
    /// caller that just launched sees the current state before the first event.
    public func start() {
        queue.async { [self] in
            self.onChange(self.watchedDirectories)
            self.startFSEvents()
            self.startPolling()
        }
    }

    /// Stops watching. Call from a thread other than the internal queue.
    public func stop() {
        queue.sync {
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
            self.pollTimer?.cancel()
            self.pollTimer = nil
        }
    }

    deinit { stop() }

    // MARK: - FSEvents

    private func startFSEvents() {
        guard !watchedDirectories.isEmpty else { return }
        let paths = watchedDirectories.map(\.path) as CFArray

        // The C callback cannot capture self, so it reaches the watcher through
        // an unmanaged pointer in the stream context. The app owns the watcher
        // for its whole lifetime, so the pointer stays valid.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            vibraFSEventCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    // MARK: - Polling

    private func startPolling() {
        guard !pollURLs.isEmpty else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.pollAll() }
        timer.resume()
        pollTimer = timer
    }

    private func pollAll() {
        for url in pollURLs { pollOnce(url) }
    }

    /// One file's (mtime, size), or nil when it does not exist.
    struct PollStamp: Equatable {
        var mtime: TimeInterval
        var size: UInt64
    }

    /// The database and its `-wal` / `-shm` sidecars. In WAL mode a write can
    /// land only in `-wal` while the main file's size and mtime sit still, so
    /// watching the main file alone can miss it until a checkpoint.
    static func pollSignature(of url: URL) -> [PollStamp]? {
        func stamp(_ path: String) -> PollStamp? {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
            return PollStamp(
                mtime: (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                size: (attrs[.size] as? UInt64) ?? 0
            )
        }
        guard let main = stamp(url.path) else { return nil }
        let sidecars = [url.path + "-wal", url.path + "-shm"].map { stamp($0) ?? PollStamp(mtime: 0, size: 0) }
        return [main] + sidecars
    }

    /// Fires `onChange` when the signature differs from the previous poll.
    /// Internal so a test can drive it without a timer.
    func pollOnce(_ url: URL) {
        guard let signature = Self.pollSignature(of: url) else { return }
        if let last = lastPollSignatures[url], last != signature {
            onChange([url])
        }
        lastPollSignatures[url] = signature
    }

    /// Called from the C callback. If FSEvents dropped events, we cannot know
    /// which files changed, so we signal a full rescan of every watched root.
    func handleEvents(paths: [URL], mustRescan: Bool) {
        if mustRescan {
            onChange(watchedDirectories)
        } else if !paths.isEmpty {
            onChange(paths)
        }
    }
}

private func vibraFSEventCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()

    let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    var changed: [URL] = []
    var mustRescan = false

    for i in 0..<numEvents {
        if eventFlags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
            mustRescan = true
        }
        let path = String(cString: paths[i])
        changed.append(URL(fileURLWithPath: path))
    }

    watcher.handleEvents(paths: changed, mustRescan: mustRescan)
}
