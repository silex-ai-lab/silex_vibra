import Foundation

/// The only encoder for incidents. Every value is a closed enum, a date, a
/// count or a hashed id, so no path, command or key can reach its output.
public enum IncidentJSON {
    public struct Row: Sendable, Equatable {
        public let incident: Incident
        public let disposition: Disposition

        public init(incident: Incident, disposition: Disposition) {
            self.incident = incident
            self.disposition = disposition
        }
    }

    private struct DispositionOutput: Encodable {
        let state: String
        let at: Date?
    }

    private struct DetailOutput: Encodable {
        var type: String
        var credentialClass: CredentialClass?
        var tool: ToolClass?
        var writeFamily: WriteFamily?
        var posture: SessionPosture?
        var provider: VendorProvider?
        var day: String?
        var vendorTokens: Int?
        var localTokens: Int?

        init(_ detail: IncidentDetail) {
            switch detail {
            case .credential(let value):
                type = "credential"
                credentialClass = value
            case .tool(let value):
                type = "tool"
                tool = value
            case .write(let value, let family):
                type = "write"
                tool = value
                writeFamily = family
            case .posture(let value):
                type = "posture"
                posture = value
            case .authError:
                type = "authError"
            case .vendorExcess(let excess):
                type = "vendorExcess"
                provider = excess.provider
                day = excess.day.iso
                vendorTokens = excess.vendorTokens
                localTokens = excess.localTokens
            }
        }
    }

    private struct RowOutput: Encodable {
        let id: String
        let kind: IncidentKind
        let severity: IncidentSeverity
        let agent: AgentKind?
        let evidence: FindingEvidence
        let at: Date
        let completedAt: Date
        let posture: SessionPosture
        let detail: DetailOutput
        let disposition: DispositionOutput

        init(_ row: Row) {
            id = row.incident.id.hex
            kind = row.incident.kind
            severity = row.incident.kind.rule.severity
            agent = row.incident.agent
            evidence = row.incident.evidence
            at = row.incident.at
            completedAt = row.incident.completedAt
            posture = row.incident.posture
            detail = DetailOutput(row.incident.detail)
            disposition = DispositionOutput(state: row.disposition.state, at: row.disposition.date)
        }
    }

    public static func encode(_ rows: [Row]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(rows.map(RowOutput.init))
    }
}
