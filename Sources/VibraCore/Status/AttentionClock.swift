import Foundation

public struct AttentionClock: Sendable {
    public init() {}

    public mutating func advance(to sessions: [Session], now: Date) -> [SessionKey: AttentionStart] {
        [:]
    }
}
