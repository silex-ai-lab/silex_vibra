import Foundation

/// Lists the `.jsonl` files under a root, re-reading only the directories
/// whose mtime moved since the previous scan.
///
/// A directory's mtime changes exactly when an entry is added, removed or
/// renamed in it, which is all a file listing depends on; appends to a
/// transcript do not touch it. So a steady-state scan costs one `lstat` per
/// directory instead of a full enumeration: on a 294-directory
/// `~/.claude/projects` that was 28 ms per refresh, every refresh.
///
/// A class so the cache outlives the value-type adapter holding it. All state
/// is guarded by `lock`, hence `@unchecked Sendable`.
public final class JSONLTreeScanner: @unchecked Sendable {
    private struct Listing {
        var seconds: Int
        var nanoseconds: Int
        var files: [URL]
        var subdirectories: [URL]
    }

    private var listings: [String: Listing] = [:]
    private let lock = NSLock()

    public init() {}

    public func files(under root: URL) -> [URL] {
        lock.lock()
        defer { lock.unlock() }

        var files: [URL] = []
        var visited: Set<String> = []
        var pending = [root]
        while let directory = pending.popLast() {
            let path = directory.path
            var info = stat()
            // lstat, so a symlinked directory is not descended into, matching
            // FileManager's enumerator.
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { continue }
            visited.insert(path)

            let seconds = info.st_mtimespec.tv_sec
            let nanoseconds = info.st_mtimespec.tv_nsec
            let listing: Listing
            if let cached = listings[path], cached.seconds == seconds, cached.nanoseconds == nanoseconds {
                listing = cached
            } else {
                // Stat before reading: an entry added in between moves the
                // mtime past the one cached here, so the next scan re-reads.
                listing = Self.read(directory, seconds: seconds, nanoseconds: nanoseconds)
                listings[path] = listing
            }
            files.append(contentsOf: listing.files)
            pending.append(contentsOf: listing.subdirectories)
        }

        // Forget directories that are gone, so the cache cannot grow without
        // bound as projects are deleted.
        listings = listings.filter { visited.contains($0.key) }
        return files
    }

    private static func read(_ directory: URL, seconds: Int, nanoseconds: Int) -> Listing {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )) ?? []
        var files: [URL] = []
        var subdirectories: [URL] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory == true, values?.isSymbolicLink != true {
                subdirectories.append(entry)
            } else if entry.pathExtension == "jsonl" {
                files.append(entry)
            }
        }
        return Listing(seconds: seconds, nanoseconds: nanoseconds, files: files, subdirectories: subdirectories)
    }
}
