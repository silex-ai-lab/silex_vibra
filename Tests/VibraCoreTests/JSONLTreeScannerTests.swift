import Foundation
import Testing
@testable import VibraCore

struct JSONLTreeScannerTests {
    private func scratchTree() throws -> URL {
        let root = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("proj/sub"), withIntermediateDirectories: true)
        try Data("a\n".utf8).write(to: root.appendingPathComponent("proj/one.jsonl"))
        try Data("b\n".utf8).write(to: root.appendingPathComponent("proj/sub/two.jsonl"))
        try Data("c\n".utf8).write(to: root.appendingPathComponent("proj/notes.txt"))
        return root
    }

    private func names(_ urls: [URL]) -> Set<String> { Set(urls.map(\.lastPathComponent)) }

    @Test func matchesAFullEnumeration() throws {
        let root = try scratchTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = JSONLTreeScanner()
        #expect(names(scanner.files(under: root)) == names(try jsonlFiles(under: root)))
        #expect(names(scanner.files(under: root)) == ["one.jsonl", "two.jsonl"])
    }

    @Test func seesFilesAddedAndRemovedBetweenScans() throws {
        let root = try scratchTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = JSONLTreeScanner()
        _ = scanner.files(under: root)

        // A new transcript in a nested directory, a new directory, and a
        // deletion: each moves only its own parent's mtime.
        try Data("d\n".utf8).write(to: root.appendingPathComponent("proj/sub/three.jsonl"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("other"), withIntermediateDirectories: true)
        try Data("e\n".utf8).write(to: root.appendingPathComponent("other/four.jsonl"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("proj/one.jsonl"))

        #expect(names(scanner.files(under: root)) == ["two.jsonl", "three.jsonl", "four.jsonl"])
    }

    @Test func aRemovedDirectoryDropsItsFiles() throws {
        let root = try scratchTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = JSONLTreeScanner()
        _ = scanner.files(under: root)

        try FileManager.default.removeItem(at: root.appendingPathComponent("proj/sub"))
        #expect(names(scanner.files(under: root)) == ["one.jsonl"])
    }
}
