import Foundation
import SQLite3

/// Resolves a path under the test bundle's copied `Fixtures` directory.
func fixtureURL(_ relativePath: String) -> URL {
    guard let resourceURL = Bundle.module.resourceURL else {
        fatalError("test bundle has no resource URL")
    }
    return resourceURL.appendingPathComponent(relativePath)
}

/// A scratch directory rooted in the repo's `.build` directory, so tests never
/// touch the developer's real agent state or any system temp directory.
func testScratchDirectory() -> URL {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("vibra-test-tmp", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

enum TestDBError: Error {
    case openFailed
    case execFailed(String)
}

/// Creates a fresh SQLite database from the given statements.
func makeDB(at url: URL, statements: [String]) throws {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw TestDBError.openFailed }
    defer { sqlite3_close(db) }
    for sql in statements {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(err)
            throw TestDBError.execFailed(message)
        }
    }
}

struct FileSignature: Equatable {
    let size: Int
    let mtime: TimeInterval
}

func fileSignature(_ url: URL) throws -> FileSignature {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let size = (attributes[.size] as? Int) ?? 0
    let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return FileSignature(size: size, mtime: mtime)
}
