import Foundation

/// Identity and change-detection metadata for one unit of readable state:
/// a single JSONL transcript, or a SQLite database.
///
/// Identity is `(device, fileID)`, not the path. A path can be reused by a
/// different file, and `(size, modified)` alone can collide — a transcript
/// replaced by a different file of the same length within the same second
/// would look unchanged and the stale session would persist. Carrying the
/// inode makes replacement detectable.
public struct SourceDescriptor: Hashable, Sendable {
    public let url: URL
    public let deviceID: UInt64
    public let fileID: UInt64
    public let size: Int64
    public let modified: Date

    public init(url: URL, deviceID: UInt64, fileID: UInt64, size: Int64, modified: Date) {
        self.url = url
        self.deviceID = deviceID
        self.fileID = fileID
        self.size = size
        self.modified = modified
    }

    /// Stats a path without reading it. Returns nil if it cannot be stat'd,
    /// which is normal: agents delete and rotate their own files.
    ///
    /// A bare `lstat`, the same call `attributesOfItem` makes, without the
    /// extended-attribute and owner-name lookups it adds on top - those were
    /// 25x the cost of the stat itself, paid for every transcript every refresh.
    public static func describing(_ url: URL) -> SourceDescriptor? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        let mtime = info.st_mtimespec
        return SourceDescriptor(
            url: url,
            // The device and inode together identify the file itself rather
            // than the name pointing at it.
            deviceID: UInt64(UInt32(bitPattern: info.st_dev)),
            fileID: UInt64(info.st_ino),
            size: Int64(info.st_size),
            // Built the way Foundation builds it, from the reference date, so
            // it equals `contentModificationDate` bit for bit. Going through
            // 1970 rounds differently for about half of all files.
            modified: Date(timeIntervalSinceReferenceDate:
                (TimeInterval(mtime.tv_sec) - Date.timeIntervalBetween1970AndReferenceDate)
                + 1.0e-9 * TimeInterval(mtime.tv_nsec))
        )
    }

    /// True when this is the same file as `other`, regardless of content.
    public func isSameFile(as other: SourceDescriptor) -> Bool {
        deviceID == other.deviceID && fileID == other.fileID
    }

    /// True when the file was replaced, or shrank — either invalidates any
    /// byte offset held against it.
    public func requiresReset(comparedTo previous: SourceDescriptor) -> Bool {
        !isSameFile(as: previous) || size < previous.size
    }

    /// True when there is genuinely nothing new to read.
    public func isUnchanged(from previous: SourceDescriptor) -> Bool {
        isSameFile(as: previous) && size == previous.size && modified == previous.modified
    }
}
