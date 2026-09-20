import Foundation

/// Reads newline-complete lines from a byte offset, in bounded memory.
///
/// Replaces `String(contentsOf:)`, which loaded whole transcripts into RAM —
/// on a 262 MB tree that was the direct cause of a 626 MB resident size.
/// Here the peak allocation is one chunk plus whatever trailing bytes have not
/// yet been terminated by a newline.
///
/// A partial final line is never returned. A live agent appends continuously,
/// so the last bytes in the file are frequently half a JSON object; those are
/// carried forward and only surfaced once a later read completes the line.
public struct IncrementalLineReader: Sendable {
    public struct Result: Sendable {
        /// Complete, newline-terminated lines, newline stripped.
        public let lines: [String]
        /// Offset to resume from next time: the byte after the last complete
        /// line consumed. Trailing partial bytes are deliberately NOT included.
        public let nextOffset: UInt64
        /// Bytes actually read from disk. Asserting this is zero is how the
        /// regression test proves an unchanged file costs nothing.
        public let bytesRead: Int
    }

    public let chunkSize: Int

    public init(chunkSize: Int = 256 * 1024) {
        self.chunkSize = chunkSize
    }

    /// Reads complete lines starting at `offset`.
    ///
    /// Returns `bytesRead == 0` without opening the file when there is nothing
    /// past the offset, which is the common case on every poll.
    public func read(url: URL, from offset: UInt64) throws -> Result {
        guard let descriptor = SourceDescriptor.describing(url) else {
            return Result(lines: [], nextOffset: offset, bytesRead: 0)
        }
        let size = UInt64(max(descriptor.size, 0))
        guard size > offset else {
            // Nothing appended. Do not open the file at all.
            return Result(lines: [], nextOffset: min(offset, size), bytesRead: 0)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        var pending = Data()
        var lines: [String] = []
        var consumed: UInt64 = offset
        var bytesRead = 0

        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            bytesRead += chunk.count
            pending.append(chunk)

            // Split on newline, keeping any trailing fragment in `pending`.
            while let nl = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = pending[pending.startIndex..<nl]
                let advance = pending.distance(from: pending.startIndex, to: nl) + 1
                consumed += UInt64(advance)
                pending.removeSubrange(pending.startIndex...nl)
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    lines.append(line)
                }
            }
        }

        // `pending` now holds an unterminated tail. It is intentionally
        // dropped from the offset so it is re-read once completed.
        return Result(lines: lines, nextOffset: consumed, bytesRead: bytesRead)
    }
}
