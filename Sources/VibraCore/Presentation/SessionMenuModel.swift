import Foundation

public enum MenuSectionKind: Sendable, CaseIterable {
    case needsYou, running, recent
}

public enum RowClick: Sendable, Equatable {
    case returnToSession, openDetails
}

public struct MenuRow: Sendable, Equatable {
    public let key: SessionKey
    public let title: String
    public let tooltip: String
    public let click: RowClick
}

public struct MenuSection: Sendable, Equatable {
    public let kind: MenuSectionKind
    public let rows: [MenuRow]
}

public struct SessionMenuModel: Sendable, Equatable {
    public let sections: [MenuSection]
    public let detailRows: [MenuRow]
    public let emptyMessage: String?
    public let notices: [String]

    public static func build(_ snapshot: StatusSnapshot, now: Date) -> SessionMenuModel {
        let titles = disambiguatedLabels(for: snapshot.sessions)
        let attention = snapshot.attention

        func row(for session: Session) -> MenuRow {
            MenuRow(
                key: session.key,
                title: "\(titles[session.key] ?? session.displayName) · "
                    + "\(session.agent.displayName) · \(stateText(session, start: attention[session.key], now: now))",
                tooltip: tooltipText(session),
                click: ReturnRoute.of(session) == .none ? .openDetails : .returnToSession
            )
        }

        let waiting = snapshot.sessions
            .filter { $0.state.needsAttention }
            .sorted { needsYouKey($0, attention) < needsYouKey($1, attention) }
        let running = snapshot.sessions
            .filter { $0.state == .working || $0.state == .stalled }
            .sorted { activityKey($0) < activityKey($1) }
        let recent = snapshot.sessions
            .filter { $0.state == .idle }
            .sorted { activityKey($0) < activityKey($1) }

        var sections: [MenuSection] = []
        for (kind, group) in [
            (MenuSectionKind.needsYou, waiting),
            (.running, running),
            (.recent, recent),
        ] where !group.isEmpty {
            sections.append(MenuSection(kind: kind, rows: group.map(row(for:))))
        }

        return SessionMenuModel(
            sections: sections,
            detailRows: sections.flatMap(\.rows),
            emptyMessage: emptyMessage(for: snapshot),
            notices: notices(for: snapshot, now: now)
        )
    }

    /// One line per row and then per failing agent, for `--dump-menu` and the
    /// env-guarded dump. Deliberately codes only: a title, path, branch,
    /// tooltip, model or token count must never reach a diagnostic file.
    public func diagnosticLines(_ snapshot: StatusSnapshot, now: Date) -> [String] {
        let sessions = Dictionary(
            snapshot.sessions.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first })

        var lines: [String] = []
        for section in sections {
            for row in section.rows {
                guard let session = sessions[row.key] else { continue }
                let waitKind: String
                let waitSeconds: String
                switch snapshot.attention[row.key] {
                case .observed(let date):
                    waitKind = "observed"
                    waitSeconds = "\(max(0, Int(now.timeIntervalSince(date))))"
                case .firstSeen(let date):
                    waitKind = "firstSeen"
                    waitSeconds = "\(max(0, Int(now.timeIntervalSince(date))))"
                case nil:
                    waitKind = "none"
                    waitSeconds = "-"
                }
                lines.append([
                    section.kind.diagnosticName,
                    session.agent.rawValue,
                    session.id,
                    session.state.rawValue,
                    waitKind,
                    waitSeconds,
                    row.click == .returnToSession ? "return" : "details",
                ].joined(separator: "\t"))
            }
        }
        for agent in AgentKind.allCases {
            guard case .failing(let problem, lastSuccess: _)? = snapshot.health[agent] else { continue }
            lines.append(["health", agent.rawValue, problem.rawValue].joined(separator: "\t"))
        }
        return lines
    }

    // MARK: - Rows

    private static func needsYouKey(
        _ session: Session,
        _ attention: [SessionKey: AttentionStart]
    ) -> (Int, Date, Double, String, String) {
        // An approval blocks work outright, so it outranks a finished turn.
        let rank = session.state == .blocked ? 0 : 1
        // A session with no recorded start sorts after one with a known wait.
        let start = attention[session.key]?.date ?? .distantFuture
        return (rank, start, -session.lastActivity.timeIntervalSince1970,
                session.agent.rawValue, session.id)
    }

    private static func activityKey(_ session: Session) -> (Double, String, String) {
        (-session.lastActivity.timeIntervalSince1970, session.agent.rawValue, session.id)
    }

    // MARK: - Empty state and notices

    private static func emptyMessage(for snapshot: StatusSnapshot) -> String? {
        guard snapshot.sessions.isEmpty else { return nil }
        // A failing source is explained by its notice, not by a claim that
        // nothing is happening.
        let failing = snapshot.health.values.contains { if case .failing = $0 { return true }; return false }
        guard !failing else { return nil }
        let ready = snapshot.health.values.contains { if case .ready = $0 { return true }; return false }
        if ready {
            return "No active sessions"
        }
        return "No sessions yet. Start Claude Code, Codex, Cursor, VS Code, OpenCode or Hermes "
            + "and it appears here."
    }

    private static func notices(for snapshot: StatusSnapshot, now: Date) -> [String] {
        AgentKind.allCases.compactMap { agent in
            guard case .failing(_, lastSuccess: let lastSuccess)? = snapshot.health[agent] else { return nil }
            let when = lastSuccess.map { "last read \(formatDuration(now.timeIntervalSince($0))) ago" }
                ?? "never read"
            return "Couldn't read \(agent.displayName) data (\(when))"
        }
    }

    // MARK: - Label disambiguation

    /// Titles for every session, refined only where labels collide.
    ///
    /// Rows are compared by label across all sections, so two sessions in one
    /// project are distinct even when one is working and one is idle. Each
    /// refinement stage applies only to the rows still tied after the one
    /// before it.
    private static func disambiguatedLabels(for sessions: [Session]) -> [SessionKey: String] {
        var titles: [SessionKey: String] = [:]
        for (label, group) in Dictionary(grouping: sessions, by: { $0.displayName }) {
            if group.count == 1 {
                titles[group[0].key] = label
                continue
            }
            var text = Dictionary(uniqueKeysWithValues: group.map { ($0.key, label) })
            var remaining = group
            for stage in 0..<3 where remaining.count > 1 {
                for session in remaining {
                    switch stage {
                    case 0:
                        if let branch = session.gitBranch, !branch.isEmpty {
                            text[session.key]? += " / \(branch)"
                        }
                    case 1:
                        text[session.key]? += " / \(pathSuffix(session.cwd))"
                    default:
                        text[session.key]? += " #\(idPrefix(session.id, among: remaining.map(\.id)))"
                    }
                }
                remaining = Dictionary(grouping: remaining, by: { text[$0.key] ?? $0.displayName })
                    .values.filter { $0.count > 1 }.flatMap { $0 }
            }
            titles.merge(text) { current, _ in current }
        }
        return titles
    }

    private static func pathSuffix(_ cwd: String) -> String {
        let components = URL(fileURLWithPath: cwd).pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
        let tail = components.suffix(2)
        return tail.isEmpty ? "(no folder)" : tail.joined(separator: "/")
    }

    private static func idPrefix(_ id: String, among ids: [String]) -> String {
        let characters = Array(id)
        guard characters.count > 4 else { return id }
        for length in 4...characters.count {
            let prefix = String(characters.prefix(length))
            if ids.filter({ $0 != id }).allSatisfy({ !$0.hasPrefix(prefix) }) {
                return prefix
            }
        }
        return id
    }
}

// MARK: - Shared row text

/// "<1m", "4m", "2h", "3d". Coarse on purpose: a menu row does not need
/// seconds, and a floor keeps "59m" from reading like an hour.
func formatDuration(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval))
    if seconds < 60 { return "<1m" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    if seconds < 86_400 { return "\(seconds / 3600)h" }
    return "\(seconds / 86_400)d"
}

func stateText(_ session: Session, start: AttentionStart?, now: Date) -> String {
    switch session.state {
    case .blocked:
        return waitingText("needs approval", start, now)
    case .awaitingInput:
        return waitingText("your turn", start, now)
    case .working:
        return "working"
    case .idle:
        return "idle"
    case .stalled:
        return "no activity for \(formatDuration(now.timeIntervalSince(session.lastActivity)))"
    }
}

private func waitingText(_ base: String, _ start: AttentionStart?, _ now: Date) -> String {
    guard let start else { return base }
    let elapsed = formatDuration(now.timeIntervalSince(start.date))
    switch start {
    case .observed:
        return "\(base) · \(elapsed)"
    case .firstSeen:
        return "\(base) · first seen \(elapsed) ago"
    }
}

func tooltipText(_ session: Session) -> String {
    let tokens = session.usage.total > 0 ? "\(session.usage.total)" : "none reported"
    let action: String
    if session.desktopSessionID != nil {
        action = "Click to open it in Claude."
    } else {
        switch ReturnRoute.of(session) {
        case .attempt:
            action = "Click to return to this session, or see its history if the window can't be found."
        case .focusApp:
            action = "Click to open \(session.agent.displayName) window."
        case .none:
            action = "\(session.agent.displayName) publishes no link between its session and its "
                + "process, so click opens details."
        }
    }
    return "\(session.cwd)\n\(session.model ?? "unknown model")\nTokens: \(tokens)\n\n\(action)"
}

private extension MenuSectionKind {
    var diagnosticName: String {
        switch self {
        case .needsYou: "needsYou"
        case .running: "running"
        case .recent: "recent"
        }
    }
}
