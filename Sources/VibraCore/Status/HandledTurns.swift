import Foundation

/// "Your turn" sessions you have already gone back to, with when you did.
///
/// A turn stays handled until the session shows activity after that moment:
/// you replied, or the agent wrote again. Kept in preferences so a relaunch
/// does not bring back every turn you already dealt with.
public struct HandledTurns: Sendable, Equatable {
    public static let key = "handledTurns"

    private var handledAt: [SessionKey: Date] = [:]

    public init() {}

    public static func load(from store: any SettingsStore) -> HandledTurns {
        var turns = HandledTurns()
        guard let stored = store.value(forKey: key) as? [String: Any] else { return turns }
        for (name, value) in stored {
            let parts = name.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let agent = AgentKind(rawValue: parts[0]),
                  let seconds = (value as? NSNumber)?.doubleValue
            else { continue }
            turns.handledAt[SessionKey(agent: agent, id: parts[1])] = Date(timeIntervalSince1970: seconds)
        }
        return turns
    }

    public func save(to store: any SettingsStore) {
        let stored = Dictionary(uniqueKeysWithValues: handledAt.map { key, date in
            ("\(key.agent.rawValue)|\(key.id)", date.timeIntervalSince1970)
        })
        store.set(stored, forKey: Self.key)
    }

    /// Only "your turn" can be handled by going back to it. An approval prompt
    /// stays blocking until it is answered.
    public mutating func markHandled(_ session: Session, now: Date) {
        guard session.state == .awaitingInput else { return }
        handledAt[session.key] = now
    }

    public func applied(to sessions: [Session]) -> [Session] {
        sessions.map { session in
            guard session.state == .awaitingInput, let at = handledAt[session.key],
                  session.lastActivity <= at
            else { return session }
            var settled = session
            settled.state = .idle
            return settled
        }
    }

    /// Drops entries whose session is gone or has moved past them.
    public mutating func prune(keeping sessions: [Session]) {
        let lastActivity = Dictionary(sessions.map { ($0.key, $0.lastActivity) },
                                      uniquingKeysWith: { first, _ in first })
        handledAt = handledAt.filter { key, at in
            lastActivity[key].map { $0 <= at } ?? false
        }
    }
}
