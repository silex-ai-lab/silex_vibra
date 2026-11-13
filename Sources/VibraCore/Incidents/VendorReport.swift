import Foundation

/// An editable report for one finding. Every fact in it is a closed enum, a
/// count or a date taken from the incident, so the draft can never carry a
/// command, a path, a session id, a key id or an incident id.
public struct VendorDraft: Sendable, Equatable {
    public var subject: String
    public var body: String

    public init(subject: String, body: String) {
        self.subject = subject
        self.body = body
    }
}

/// Where a finding can be reported, with the warning that belongs beside the
/// link.
public struct VendorChannel: Sendable, Equatable {
    public let title: String
    public let page: URL
    /// The security programme, offered beside the bug page. The human chooses;
    /// Vibra never concludes a finding is a vulnerability.
    public let securityPage: URL?
    public let warning: String
}

/// The local draft and the vendor channel table. Pure: it sees an `Incident`
/// and returns text and URLs. It opens nothing and sends nothing.
public enum VendorReport {
    /// The `mailto:` cap. The window opens the URL through `NSWorkspace`.
    public static let maxMailtoBytes = 1800

    // MARK: - Draft

    /// Nil for a kind whose route is `none`: those are facts for the user, not
    /// something to send a vendor.
    public static func draft(incident: Incident, appVersion: String, osVersion: String) -> VendorDraft? {
        let rule = incident.kind.rule
        guard rule.route != .none else { return nil }
        let who = name(of: incident)

        var lines: [String] = []
        lines.append("\(incident.agent == nil ? "Provider" : "Agent"): \(who)")
        lines.append("Kind: \(rule.title)")
        lines.append("Session posture: \(label(incident.posture))")
        switch incident.detail {
        case .credential(let credential):
            lines.append("Credential: \(label(credential))")
        case .tool(let tool):
            lines.append("Tool: \(label(tool))")
        case .write(let tool, let family):
            lines.append("Tool: \(label(tool))")
            lines.append("Destination: \(family.label)")
        default:
            break
        }
        if case .vendorExcess(let excess) = incident.detail {
            lines.append("Day: \(excess.day.iso) UTC")
            lines.append("Vendor tokens: \(excess.vendorTokens)")
            lines.append("Local tokens: \(excess.localTokens)")
        } else {
            lines.append("Time: \(utcMinute(incident.at))")
        }
        lines.append("OS: \(osVersion)")
        lines.append("Vibra: \(appVersion)")
        lines.append("")
        lines.append(rule.guidance)
        lines.append(incident.evidence.sentence)
        // A related category, offered as context: an agent can misuse a tool
        // without a vendor defect, and this line sits after the facts so it
        // cannot read as a finding against the vendor.
        if !incident.kind.owaspAgentic.isEmpty {
            lines.append(
                "Related OWASP category (Top 10 for Agentic Applications 2026): "
                    + incident.kind.owaspAgentic.joined(separator: ", "))
        }
        lines.append("")
        lines.append("What I expected")

        return VendorDraft(
            subject: "Vibra incident: \(rule.title) (\(who))",
            body: lines.joined(separator: "\n") + "\n")
    }

    // MARK: - Channel

    public static func channel(for incident: Incident) -> VendorChannel? {
        switch incident.kind.rule.route {
        case .none:
            return nil
        case .agentBug:
            guard let agent = incident.agent else { return nil }
            switch agent {
            case .claudeCode:
                return VendorChannel(
                    title: "Claude Code issues on GitHub",
                    page: URL(string: "https://github.com/anthropics/claude-code/issues/new")!,
                    securityPage: URL(string: "https://hackerone.com/anthropic")!,
                    warning: agentWarning)
            case .codex:
                return VendorChannel(
                    title: "Codex issues on GitHub",
                    page: URL(string: "https://github.com/openai/codex/issues/new")!,
                    securityPage: URL(string: "https://bugcrowd.com/engagements/openai")!,
                    warning: agentWarning)
            default:
                return nil
            }
        case .billing:
            guard case .vendorExcess(let excess) = incident.detail else { return nil }
            switch excess.provider {
            case .anthropic:
                return VendorChannel(
                    title: "Anthropic support",
                    page: URL(string: "https://support.claude.com")!,
                    securityPage: nil,
                    warning: billingWarning)
            case .openai:
                return VendorChannel(
                    title: "OpenAI support",
                    page: URL(string: "https://help.openai.com")!,
                    securityPage: nil,
                    warning: billingWarning)
            }
        }
    }

    private static let agentWarning =
        "Issues are public, so anyone can read what you post. The security program wants "
        + "validated findings: confirm first."
    private static let billingWarning =
        "A support request may need account details, and nothing else."

    // MARK: - Mailto

    /// `mailto:` with an empty recipient. The subject is never truncated; the
    /// body stops at a character boundary so a percent escape is never split.
    public static func mailtoURL(_ draft: VendorDraft) -> URL? {
        let prefix = "mailto:?subject=" + percentEncode(draft.subject) + "&body="
        let budget = maxMailtoBytes - prefix.utf8.count
        guard budget >= 0 else { return nil }

        var body = ""
        var used = 0
        for character in draft.body {
            let encoded = percentEncode(String(character))
            let size = encoded.utf8.count
            if used + size > budget { break }
            body += encoded
            used += size
        }
        return URL(string: prefix + body)
    }

    /// Everything outside the unreserved set is escaped, so `+`, `&`, `%` and
    /// newlines survive the round trip.
    private static func percentEncode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x2E, 0x5F, 0x7E:
                out.append(Character(UnicodeScalar(byte)))
            default:
                out += String(format: "%%%02X", Int(byte))
            }
        }
        return out
    }

    // MARK: - Labels

    /// The agent, or the provider for a vendor file finding.
    private static func name(of incident: Incident) -> String {
        if let agent = incident.agent { return agent.displayName }
        if case .vendorExcess(let excess) = incident.detail {
            switch excess.provider {
            case .anthropic: return "Anthropic"
            case .openai: return "OpenAI"
            }
        }
        return "the vendor"
    }

    private static func label(_ posture: SessionPosture) -> String {
        switch posture {
        case .claudeBypassPermissions: "bypassPermissions"
        case .codexDangerFullAccess: "danger-full-access"
        case .sandboxed: "sandboxed"
        case .approvalsOn: "approvals on"
        case .unknown: "unknown"
        }
    }

    private static func label(_ tool: ToolClass) -> String {
        switch tool {
        case .bash: "Bash"
        case .edit: "Edit"
        case .write: "Write"
        case .read: "Read"
        case .fileChange: "File change"
        case .other: "Other tool"
        }
    }

    private static func label(_ credential: CredentialClass) -> String {
        switch credential {
        case .dotEnv: ".env file"
        case .sshKey: "SSH key"
        case .awsCredentials: "AWS credentials"
        case .netrc: ".netrc"
        case .packageToken: "package token"
        case .gitHubCLI: "GitHub CLI token"
        case .agentCredential: "agent credential"
        case .keychain: "keychain item"
        }
    }

    /// `2026-11-09 10:04 UTC`, decided in UTC so it reads the same everywhere.
    private static func utcMinute(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d UTC",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }
}
