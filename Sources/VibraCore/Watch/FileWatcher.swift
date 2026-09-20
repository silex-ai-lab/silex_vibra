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

/// Watches the JSONL trees with FSEvents and polls a SQLite database with a
/// timer, invoking `onChange` whenever something changes.
///
/// `@unchecked Sendable` because all mutable state is confined to the private
/// serial `queue`; the only value that crosses threads is the `@Sendable`
/// `onChange` handler.
public final class FileWatcher: @unchecked Sendable {
    public typealias ChangeHandler = @Sendable ([URL]) -> Void

    private let watchedDirectories: [URL]
    private let pollURL: URL?
    private let onChange: ChangeHandler

    private let queue = DispatchQueue(label: "vibra.filewatcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pollTimer: DispatchSourceTimer?
    private var lastPollSignature: (mtime: TimeInterval, size: UInt64)?

    public init(
        watchedDirectories: [URL],
        pollURL: URL? = nil,
        onChange: @escaping ChangeHandler
    ) {
        self.watchedDirectories = watchedDirectories
        self.pollURL = pollURL
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
        guard let pollURL else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.pollOnce(pollURL) }
        timer.resume()
        pollTimer = timer
    }

    private func pollOnce(_ url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? UInt64) ?? 0
        let signature = (mtime, size)
        if let last = lastPollSignature, last != signature {
            onChange([url])
        }
        lastPollSignature = signature
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
