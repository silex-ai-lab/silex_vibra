import CryptoKit
import Foundation

public enum IncidentKind: String, Codable, Sendable, CaseIterable {
    case deniedCallRanLater, credentialReadAttempt, workspaceSecretFileNamed
    case writeToPathOutsideWorkspace, forcePushAttempt
    case unrestrictedSession, authFailure, unexplainedVendorUsage
}

public enum CredentialClass: String, Codable, Sendable, CaseIterable {
    case dotEnv, sshKey, awsCredentials, netrc, packageToken, gitHubCLI, agentCredential, keychain
}

public enum SessionPosture: String, Codable, Sendable, CaseIterable {
    case claudeBypassPermissions, codexDangerFullAccess
    case sandboxed, approvalsOn, unknown
}

public enum VendorProvider: String, Codable, Sendable, CaseIterable {
    case anthropic, openai
}

public enum ToolClass: String, Codable, Sendable, CaseIterable {
    case bash, edit, write, read, fileChange, other
}

/// Where an outside write went, as one bit. Sibling repositories are routine
/// on a multi-repository machine, and the rest are not.
public enum WriteFamily: String, Codable, Sendable, CaseIterable {
    case sibling, elsewhere

    public var label: String {
        switch self {
        case .sibling: "a sibling of the workspace"
        case .elsewhere: "elsewhere on this Mac"
        }
    }
}

public enum FindingEvidence: String, Codable, Sendable, CaseIterable {
    /// A non-shell tool call, or a sole foreground shell command that exited 0.
    case toolResult
    /// Named in shell text that may not have run that branch.
    case commandLine
    /// A posture or API error record in the transcript.
    case transcriptRecord
    /// The imported usage file.
    case vendorFile

    public var sentence: String {
        switch self {
        case .toolResult: "The tool call completed."
        case .commandLine: "It was named in a shell command line and may not have run."
        case .transcriptRecord: "Recorded in the agent's transcript."
        case .vendorFile: "Calculated from the usage file you imported."
        }
    }
}

/// A calendar day in UTC, as vendors report it. Kept as text so it never
/// displays as the previous local evening.
public struct UTCDay: Sendable, Hashable, Comparable, Codable {
    public let iso: String

    public init?(iso: String) {
        guard iso.utf8.count == 10, let date = try? Self.style.parse(iso), Self.style.format(date) == iso
        else { return nil }
        self.iso = iso
    }

    public init(date: Date) {
        iso = Self.style.format(date)
    }

    /// Midnight UTC at the start of this day.
    public var start: Date { (try? Self.style.parse(iso)) ?? .distantPast }

    public static func < (lhs: UTCDay, rhs: UTCDay) -> Bool { lhs.iso < rhs.iso }

    private static let style = Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: .gmt).year().month().day()
}

public struct VendorExcess: Sendable, Equatable {
    public let provider: VendorProvider
    public let day: UTCDay
    public let vendorTokens: Int
    public let localTokens: Int

    public init(provider: VendorProvider, day: UTCDay, vendorTokens: Int, localTokens: Int) {
        self.provider = provider
        self.day = day
        self.vendorTokens = vendorTokens
        self.localTokens = localTokens
    }
}

public enum IncidentDetail: Sendable, Equatable {
    case credential(CredentialClass)
    case tool(ToolClass)
    case write(ToolClass, WriteFamily)
    case posture(SessionPosture)
    case authError
    case vendorExcess(VendorExcess)
}

public struct IncidentID: Sendable, Hashable, Codable {
    public let hex: String

    public init(hex: String) {
        self.hex = hex
    }

    /// `anchor` is positional and never derived from transcript content.
    public init(agent: AgentKind?, session: String?, kind: IncidentKind, anchor: String) {
        let material = [agent?.rawValue ?? "-", session ?? "-", kind.rawValue, anchor].joined(separator: "|")
        hex = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct Incident: Sendable, Equatable, Identifiable {
    public let id: IncidentID
    public let kind: IncidentKind
    /// Nil for a vendor file finding.
    public let agent: AgentKind?
    public let evidence: FindingEvidence
    /// When the action began.
    public let at: Date
    /// The result record, else equal to `at`.
    public let completedAt: Date
    public let posture: SessionPosture
    public let detail: IncidentDetail

    public init(
        id: IncidentID,
        kind: IncidentKind,
        agent: AgentKind?,
        evidence: FindingEvidence,
        at: Date,
        completedAt: Date,
        posture: SessionPosture,
        detail: IncidentDetail
    ) {
        self.id = id
        self.kind = kind
        self.agent = agent
        self.evidence = evidence
        self.at = at
        self.completedAt = completedAt
        self.posture = posture
        self.detail = detail
    }
}

public enum Disposition: Sendable, Equatable {
    case open
    /// "This was me, or I allow it."
    case expected(at: Date)
    case resolved(at: Date)
    /// Set by the user. Vibra cannot see a send.
    case reported(at: Date)

    public var state: String {
        switch self {
        case .open: "open"
        case .expected: "expected"
        case .resolved: "resolved"
        case .reported: "reported"
        }
    }

    public var date: Date? {
        switch self {
        case .open: nil
        case .expected(let at), .resolved(let at), .reported(let at): at
        }
    }

    public init?(state: String, at: Date) {
        switch state {
        case "expected": self = .expected(at: at)
        case "resolved": self = .resolved(at: at)
        case "reported": self = .reported(at: at)
        default: return nil
        }
    }
}

public enum IncidentSeverity: String, Codable, Sendable {
    case review, info
}

public enum ReportRoute: String, Codable, Sendable {
    case none, agentBug, billing
}

public struct IncidentRule: Sendable {
    public let severity: IncidentSeverity
    public let title: String
    public let guidance: String
    public let route: ReportRoute
}

extension IncidentKind {
    /// Related OWASP Top 10 for Agentic Applications 2026 categories, empty
    /// when the kind is not an agent behaviour. Exhaustive on purpose: a new
    /// kind must decide its category rather than inherit an empty one.
    public var owaspAgentic: [String] {
        switch self {
        case .credentialReadAttempt, .workspaceSecretFileNamed, .unrestrictedSession:
            ["ASI03"]
        case .deniedCallRanLater, .writeToPathOutsideWorkspace, .forcePushAttempt:
            ["ASI02"]
        case .authFailure, .unexplainedVendorUsage:
            []
        }
    }

    /// The one place that decides severity, wording and route for a kind.
    public var rule: IncidentRule {
        switch self {
        case .deniedCallRanLater:
            IncidentRule(
                severity: .review, title: "A denied call ran later",
                guidance: "A call was denied and the identical call ran later. You or a rule may have approved the retry.",
                route: .agentBug)
        case .credentialReadAttempt:
            IncidentRule(
                severity: .review, title: "A credential read",
                guidance: "A read of a credential. Rotate the secret if you did not expect this.",
                route: .agentBug)
        case .workspaceSecretFileNamed:
            IncidentRule(
                severity: .info, title: "This project's .env was named",
                guidance: "This project's own .env was named in this session.",
                route: .none)
        case .writeToPathOutsideWorkspace:
            IncidentRule(
                severity: .review, title: "A write outside the workspace",
                guidance: "A tool edited a path outside the workspace as written, at least once in this session. A --add-dir grant or a symlink looks the same. Mark it expected if so.",
                route: .agentBug)
        case .forcePushAttempt:
            IncidentRule(
                severity: .review, title: "A force push",
                guidance: "A force push. Check the branch history.",
                route: .agentBug)
        case .unrestrictedSession:
            IncidentRule(
                severity: .info, title: "Guardrails were off",
                guidance: "You or your config turned guardrails off. Not a vendor fault.",
                route: .none)
        case .authFailure:
            IncidentRule(
                severity: .info, title: "The vendor rejected the credentials",
                guidance: "Sign in again, or rotate the key if you did not change it.",
                route: .none)
        case .unexplainedVendorUsage:
            IncidentRule(
                severity: .review, title: "Vendor usage this Mac cannot explain",
                guidance: "Another of your machines or apps looks the same. If not, rotate the key.",
                route: .billing)
        }
    }
}

/// An incident and its raw session id. The id stays beside the incident, in
/// memory, for Jump to session only, and is never serialized.
public struct ExtractedIncident: Sendable, Equatable {
    public let incident: Incident
    public let rawSessionID: String

    public init(incident: Incident, rawSessionID: String) {
        self.incident = incident
        self.rawSessionID = rawSessionID
    }
}

/// Folds one transcript's lines, in order, and returns incidents as they
/// complete. Commands, paths and tool output are read and dropped inside `fold`.
public protocol IncidentExtractor {
    mutating func fold(_ lines: [String]) -> [ExtractedIncident]
}
