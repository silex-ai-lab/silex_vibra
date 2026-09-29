import Foundation

/// Codex desktop's registered thread link. Only a UUID is accepted, so a
/// transcript ID cannot introduce another route, query, or URL scheme.
public enum CodexSessionLink {
    public static func url(sessionID: String) -> URL? {
        guard let id = UUID(uuidString: sessionID) else { return nil }
        return URL(string: "codex://threads/\(id.uuidString.lowercased())")
    }
}
