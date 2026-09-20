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
    public static func describing(_ url: URL) -> SourceDescriptor? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        // systemFileNumber is the inode and systemNumber the device; together
        // they identify the file itself rather than the name pointing at it.
        let fileID = (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let deviceID = (a[.systemNumber] as? NSNumber)?.uint64Value ?? 0
        let size = (a[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (a[.modificationDate] as? Date) ?? .distantPast
        return SourceDescriptor(
            url: url,
            deviceID: deviceID,
            fileID: fileID,
            size: size,
            modified: modified
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
