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

    /// Creates a stream for `roots` but does not attach or start it. Internal
    /// and injectable so a test can make an arm fail and check the retry.
    typealias StreamFactory = @Sendable ([URL]) -> FSEventStreamRef?

    private let watchedDirectories: [URL]
    private let pollURLs: [URL]
    private let onChange: ChangeHandler
    private let createStream: StreamFactory?

    private let queue = DispatchQueue(label: "vibra.filewatcher", qos: .utility)
    private var stream: FSEventStreamRef?
    /// What the running stream actually covers: path -> identity. A path alone
    /// cannot tell a recreated root from the one the stream was armed on.
    private var armedRoots: [String: RootIdentity] = [:]
    private var pollTimer: DispatchSourceTimer?
    /// A present key with a nil value means "polled, and absent". A missing key
    /// means "never polled": the first poll only seeds.
    private var lastPollSignatures: [URL: [PollStamp]?] = [:]

    public init(
        watchedDirectories: [URL],
        pollURLs: [URL] = [],
        onChange: @escaping ChangeHandler
    ) {
        self.watchedDirectories = watchedDirectories
        self.pollURLs = pollURLs
        self.onChange = onChange
        self.createStream = nil
    }

    init(
        watchedDirectories: [URL],
        pollURLs: [URL] = [],
        createStream: StreamFactory?,
        onChange: @escaping ChangeHandler
    ) {
        self.watchedDirectories = watchedDirectories
        self.pollURLs = pollURLs
        self.onChange = onChange
        self.createStream = createStream
    }

    /// Starts watching. Fires an initial "rescan everything" callback so a
    /// caller that just launched sees the current state before the first event.
    public func start() {
        queue.async { [self] in
            self.onChange(self.watchedDirectories)
            self.rearmStreams()
            self.startPolling()
        }
    }

    /// Stops watching. Call from a thread other than the internal queue.
    public func stop() {
        queue.sync {
            if let stream {
                Self.release(stream)
                self.stream = nil
            }
            self.armedRoots = [:]
            self.pollTimer?.cancel()
            self.pollTimer = nil
        }
    }

    deinit { stop() }

    // MARK: - FSEvents

    /// Identity of a watched directory, from `stat`.
    struct RootIdentity: Equatable {
        let device: UInt64
        let inode: UInt64

        static func describing(_ url: URL) -> RootIdentity? {
            var info = stat()
            guard stat(url.path, &info) == 0 else { return nil }
            return RootIdentity(
                device: UInt64(UInt32(bitPattern: info.st_dev)),
                inode: UInt64(info.st_ino)
            )
        }
    }

    /// Creates a stream for `roots`. Not started: `arm` attaches it to the
    /// queue and starts it, so a failed arm leaves the old stream running.
    private func createStreamObject(for roots: [URL]) -> FSEventStreamRef? {
        let paths = roots.map(\.path) as CFArray

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
        return FSEventStreamCreate(
            kCFAllocatorDefault,
            vibraFSEventCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        )
    }

    /// Starts a stream over exactly `desired`, then stops the old one: new
    /// before old, so no event can fall between them. On failure nothing is
    /// armed, so `armedRoots` stays behind and the next tick retries.
    private func arm(_ desired: [String: RootIdentity]) -> Bool {
        let roots = desired.keys.sorted().map { URL(fileURLWithPath: $0) }
        let newStream: FSEventStreamRef?
        if let createStream {
            newStream = createStream(roots)
        } else {
            newStream = createStreamObject(for: roots)
        }
        guard let newStream else { return false }

        FSEventStreamSetDispatchQueue(newStream, queue)
        guard FSEventStreamStart(newStream) else {
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            return false
        }
        if let stream { Self.release(stream) }
        stream = newStream
        return true
    }

    /// Arms, re-arms or tears down the stream to match the roots that exist
    /// now. Called once per poll tick, so a root created after launch is
    /// covered within a second: a stream created on a path that does not
    /// exist yet delivers nothing for the life of the process.
    private func rearmStreams() {
        let desired = Self.rootIdentities(of: watchedDirectories)
        guard desired != armedRoots else { return }
        let changed = Self.changedRoots(from: armedRoots, to: desired)

        guard !desired.isEmpty else {
            if let stream {
                Self.release(stream)
                self.stream = nil
            }
            armedRoots = [:]
            onChange(changed)
            return
        }
        guard arm(desired) else { return }
        armedRoots = desired
        onChange(changed)
    }

    private static func rootIdentities(of roots: [URL]) -> [String: RootIdentity] {
        var identities: [String: RootIdentity] = [:]
        for root in roots {
            if let identity = RootIdentity.describing(root) {
                identities[root.path] = identity
            }
        }
        return identities
    }

    /// The identity the running stream is armed on for `path`. Internal for
    /// tests: FSEvents keeps delivering for a replaced directory at the same
    /// path, so a re-arm is otherwise invisible from the outside.
    func armedIdentity(of path: String) -> RootIdentity? {
        queue.sync { armedRoots[path] }
    }

    /// Paths added, removed, or pointing at a different directory than before.
    private static func changedRoots(
        from old: [String: RootIdentity],
        to new: [String: RootIdentity]
    ) -> [URL] {
        var changed: [URL] = []
        for (path, identity) in new where old[path] != identity {
            changed.append(URL(fileURLWithPath: path))
        }
        for path in old.keys where new[path] == nil {
            changed.append(URL(fileURLWithPath: path))
        }
        return changed.sorted { $0.path < $1.path }
    }

    private static func release(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    // MARK: - Polling

    private func startPolling() {
        guard !pollURLs.isEmpty || !watchedDirectories.isEmpty else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.pollAll() }
        timer.resume()
        pollTimer = timer
    }

    private func pollAll() {
        for url in pollURLs { pollOnce(url) }
        rearmStreams()
    }

    /// One file's (mtime, size), or nil when it does not exist.
    struct PollStamp: Equatable {
        var mtime: TimeInterval
        var size: UInt64
    }

    /// The database and its `-wal` sidecar. In WAL mode a write can land only
    /// in `-wal` while the main file's size and mtime sit still, so watching
    /// the main file alone can miss it until a checkpoint. `-shm` is not
    /// watched: readers write to it too, so our own refresh would re-trigger
    /// the poll.
    static func pollSignature(of url: URL) -> [PollStamp]? {
        func stamp(_ path: String) -> PollStamp? {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
            return PollStamp(
                mtime: (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                size: (attrs[.size] as? UInt64) ?? 0
            )
        }
        guard let main = stamp(url.path) else { return nil }
        return [main, stamp(url.path + "-wal") ?? PollStamp(mtime: 0, size: 0)]
    }

    /// Fires on an absent -> present or present -> absent transition. The first
    /// poll for a URL only seeds: a database already there at launch is not
    /// news, but one created afterwards is.
    /// Internal so a test can drive it without a timer.
    func pollOnce(_ url: URL) {
        let signature = Self.pollSignature(of: url)
        guard let previous = lastPollSignatures[url] else {
            lastPollSignatures[url] = .some(signature)
            return
        }
        lastPollSignatures[url] = .some(signature)
        if previous != signature {
            onChange([url])
        }
    }

    /// Called from the C callback. If FSEvents dropped events, we cannot know
    /// which files changed, so we signal a full rescan of every watched root.
    ///
    /// A SQLite `-shm` change is dropped: readers write the wal-index too, so
    /// it says nothing about new data, and acting on it lets Vibra's own reads
    /// keep re-triggering refreshes.
    func handleEvents(paths: [URL], mustRescan: Bool) {
        if mustRescan {
            onChange(watchedDirectories)
            return
        }
        let relevant = paths.filter { !Self.isReaderSideEffect($0) }
        if !relevant.isEmpty {
            onChange(relevant)
        }
    }

    static func isReaderSideEffect(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix("-shm")
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
