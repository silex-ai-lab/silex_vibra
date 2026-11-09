import Foundation

/// Plain text for the `--incidents` command and the window. Every line is
/// built from closed values, so it inherits the incident's privacy guarantee.
public enum IncidentText {
    public static func summary(_ row: IncidentJSON.Row) -> String {
        let rule = row.incident.kind.rule
        return "\(rule.guidance) \(row.incident.evidence.sentence)"
    }

    public static func fact(_ detail: IncidentDetail) -> String {
        switch detail {
        case .credential(let value): "credential class: \(value.rawValue)"
        case .tool(let value): "tool: \(value.rawValue)"
        case .posture(let value): "posture: \(value.rawValue)"
        case .authError: "authentication_failed"
        case .vendorExcess(let excess):
            "\(excess.provider.rawValue) \(excess.day.iso): vendor \(excess.vendorTokens) tokens, this Mac \(excess.localTokens)"
        }
    }

    public static func owner(_ incident: Incident) -> String {
        if let agent = incident.agent { return agent.displayName }
        if case .vendorExcess(let excess) = incident.detail { return excess.provider.rawValue }
        return "-"
    }

    public static func render(_ rows: [IncidentJSON.Row]) -> String {
        var counts: [IncidentKind: Int] = [:]
        for row in rows { counts[row.incident.kind, default: 0] += 1 }
        var lines = IncidentKind.allCases.map { "\($0.rawValue): \(counts[$0] ?? 0)" }
        lines.append("")
        for row in rows {
            let incident = row.incident
            let date = incident.completedAt.formatted(.iso8601)
            lines.append(
                "\(date)  \(incident.kind.rule.severity.rawValue)  \(owner(incident))  \(incident.kind.rawValue)  \(incident.evidence.rawValue)  \(fact(incident.detail))  \(row.disposition.state)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
