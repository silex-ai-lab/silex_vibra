import Foundation

/// The only reader and writer of `incidents.json`. Everything else sends it
/// a merge by id, so a window holding a stale copy cannot drop a monitor update
/// or rewind the watermark.
///
/// Holds hashed ids, the user's answers and the notification watermark. Dates
/// are stored as `Date`'s own reference-date value: the watermark is compared
/// exactly against `completedAt` after a restart, and converting through the
/// Unix epoch can move a `Date` by one unit in the last place.
public actor IncidentStore {
    private struct Entry: Codable {
        let state: String
        let at: Date
    }

    private struct Contents: Codable {
        var version: Int
        var watermark: Date?
        var dispositions: [String: Entry]

        static let empty = Contents(version: IncidentStore.schemaVersion, watermark: nil, dispositions: [:])
    }

    public static let schemaVersion = 1
    private static let retention: TimeInterval = 90 * 86_400

    public static var defaultURL: URL {
        VibraPaths.home.appendingPathComponent("Library/Application Support/Vibra/incidents.json")
    }

    private let url: URL
    private let now: @Sendable () -> Date
    private let readOnly: Bool
    private var contents: Contents
    /// True when a corrupt file was set aside at load, so the window can say
    /// the user's answers were reset.
    public nonisolated let wasReset: Bool

    /// `readOnly` is for the diagnostic commands, which must write nothing, even
    /// the rename of a corrupt file.
    public init(
        url: URL = IncidentStore.defaultURL,
        now: @escaping @Sendable () -> Date = { Date() },
        readOnly: Bool = false
    ) {
        self.url = url
        self.now = now
        self.readOnly = readOnly
        (contents, wasReset) = Self.load(url: url, now: now(), readOnly: readOnly)
    }

    private static func load(url: URL, now: Date, readOnly: Bool) -> (Contents, wasReset: Bool) {
        guard let data = try? Data(contentsOf: url) else { return (.empty, false) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            Date(timeIntervalSinceReferenceDate: try decoder.singleValueContainer().decode(Double.self))
        }
        if let decoded = try? decoder.decode(Contents.self, from: data), decoded.version == schemaVersion {
            return (decoded, false)
        }
        if readOnly { return (.empty, false) }
        let aside = url.deletingLastPathComponent()
            .appendingPathComponent("incidents.corrupt-\(Int(now.timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        return (.empty, true)
    }

    public func watermark() -> Date? { contents.watermark }

    public func dispositions() -> [IncidentID: Disposition] {
        var result: [IncidentID: Disposition] = [:]
        for (hex, entry) in contents.dispositions {
            if let disposition = Disposition(state: entry.state, at: entry.at) {
                result[IncidentID(hex: hex)] = disposition
            }
        }
        return result
    }

    /// Sets the watermark on the first run only, and returns the one in force.
    public func initializeWatermark(_ date: Date) -> Date {
        if let existing = contents.watermark { return existing }
        contents.watermark = date
        _ = save()
        return date
    }

    /// Advances the watermark and refuses to lower it. Returns false only when
    /// the new value could not be persisted, so the caller must not deliver.
    @discardableResult
    public func commit(watermark: Date) -> Bool {
        let previous = contents.watermark
        if let previous, watermark <= previous { return true }
        contents.watermark = watermark
        if save() { return true }
        contents.watermark = previous
        return false
    }

    /// `.open` removes the answer, which is what Reopen means.
    @discardableResult
    public func set(_ disposition: Disposition, for id: IncidentID) -> Bool {
        let previous = contents.dispositions[id.hex]
        if let date = disposition.date {
            contents.dispositions[id.hex] = Entry(state: disposition.state, at: date)
        } else {
            contents.dispositions[id.hex] = nil
        }
        if save() { return true }
        contents.dispositions[id.hex] = previous
        return false
    }

    private func save() -> Bool {
        if readOnly { return false }
        let cutoff = now().addingTimeInterval(-Self.retention)
        contents.dispositions = contents.dispositions.filter { $0.value.at >= cutoff }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(contents).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
