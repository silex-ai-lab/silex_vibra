import Foundation
import Testing
@testable import VibraCore

/// Pins the exact draft text, the channel table, and the `mailto:` cap.
struct VendorReportTests {
    // MARK: - Helpers

    private func instant(_ iso: String) -> Date { parseISODate(iso)! }

    private func incident(
        kind: IncidentKind,
        agent: AgentKind?,
        evidence: FindingEvidence = .toolResult,
        at: Date = Date(timeIntervalSince1970: 1_800_000_000),
        posture: SessionPosture = .unknown,
        detail: IncidentDetail = .tool(.bash),
        anchor: String = "a",
        session: String? = nil
    ) -> Incident {
        Incident(
            id: IncidentID(agent: agent, session: session, kind: kind, anchor: anchor),
            kind: kind,
            agent: agent,
            evidence: evidence,
            at: at,
            completedAt: at,
            posture: posture,
            detail: detail)
    }

    private func vendor(_ tokens: Int = 900_000, local: Int = 100, provider: VendorProvider = .anthropic) -> Incident {
        incident(
            kind: .unexplainedVendorUsage,
            agent: nil,
            evidence: .vendorFile,
            at: instant("2026-11-01T00:00:00Z"),
            detail: .vendorExcess(VendorExcess(
                provider: provider,
                day: UTCDay(iso: "2026-11-01")!,
                vendorTokens: tokens,
                localTokens: local)))
    }

    private func draft(_ incident: Incident) throws -> VendorDraft {
        try #require(VendorReport.draft(incident: incident, appVersion: "1.2.3", osVersion: "macOS 15.1"))
    }

    /// The subject and body as the mail client would read them back.
    private func decoded(_ url: URL) throws -> (subject: String, body: String) {
        let prefix = "mailto:?subject="
        let string = url.absoluteString
        #expect(string.hasPrefix(prefix))
        let rest = String(string.dropFirst(prefix.count))
        let parts = rest.split(separator: "&", maxSplits: 1, omittingEmptySubsequences: false)
        #expect(parts.count == 2)
        let subject = try #require(String(parts[0]).removingPercentEncoding)
        let bodyPart = String(try #require(parts.last))
        #expect(bodyPart.hasPrefix("body="))
        let body = try #require(String(bodyPart.dropFirst("body=".count)).removingPercentEncoding)
        return (subject, body)
    }

    private func hasWholeEscapes(_ text: String) -> Bool {
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            if characters[index] == "%" {
                guard index + 2 < characters.count,
                      characters[index + 1].isHexDigit,
                      characters[index + 2].isHexDigit
                else { return false }
                index += 3
            } else {
                index += 1
            }
        }
        return true
    }

    // MARK: - Exact drafts

    @Test func anAgentDraftWithCommandLineEvidenceIsExact() throws {
        let prepared = incident(
            kind: .credentialReadAttempt,
            agent: .claudeCode,
            evidence: .commandLine,
            at: instant("2026-11-09T10:04:05Z"),
            posture: .approvalsOn,
            detail: .tool(.bash))
        let preparedDraft = try draft(prepared)
        #expect(preparedDraft.subject == "Vibra incident: A credential read (Claude Code)")
        // The body ends with the heading plus a newline: the blank line the
        // user types their answer on.
        #expect(preparedDraft.body == """
            Agent: Claude Code
            Kind: A credential read
            Session posture: approvals on
            Tool: Bash
            Time: 2026-11-09 10:04 UTC
            OS: macOS 15.1
            Vibra: 1.2.3

            A read of a credential. Rotate the secret if you did not expect this.
            It was named in a shell command line and may not have run.

            What I expected
            """ + "\n")
    }

    @Test func aVendorDraftIsExact() throws {
        let vendorDraft = try draft(vendor())
        #expect(vendorDraft.subject == "Vibra incident: Vendor usage this Mac cannot explain (Anthropic)")
        #expect(vendorDraft.body == """
            Provider: Anthropic
            Kind: Vendor usage this Mac cannot explain
            Session posture: unknown
            Day: 2026-11-01 UTC
            Vendor tokens: 900000
            Local tokens: 100
            OS: macOS 15.1
            Vibra: 1.2.3

            Another of your machines or apps looks the same. If not, rotate the key.
            Calculated from the usage file you imported.

            What I expected
            """ + "\n")
    }

    // MARK: - Kinds and routes

    @Test func everyInfoKindHasNoDraftAndNoChannel() {
        let details: [IncidentKind: IncidentDetail] = [
            .workspaceSecretFileNamed: .credential(.dotEnv),
            .unrestrictedSession: .posture(.claudeBypassPermissions),
            .authFailure: .authError,
        ]
        for kind in IncidentKind.allCases where kind.rule.route == .none {
            let prepared = incident(kind: kind, agent: .claudeCode, detail: details[kind] ?? .tool(.bash))
            #expect(VendorReport.draft(incident: prepared, appVersion: "1", osVersion: "macOS") == nil, "\(kind)")
            #expect(VendorReport.channel(for: prepared) == nil, "\(kind)")
        }
    }

    @Test func everyOtherKindHasADraftAndAChannel() throws {
        let agentDetail: [IncidentKind: IncidentDetail] = [
            .deniedCallRanLater: .tool(.bash),
            .credentialReadAttempt: .tool(.bash),
            .writeToPathOutsideWorkspace: .tool(.edit),
            .forcePushAttempt: .tool(.bash),
        ]
        for kind in IncidentKind.allCases where kind.rule.route != .none {
            let prepared: Incident
            if let detail = agentDetail[kind] {
                prepared = incident(kind: kind, agent: .claudeCode, detail: detail)
            } else {
                prepared = vendor()
            }
            let preparedDraft = try draft(prepared)
            #expect(!preparedDraft.subject.isEmpty)
            #expect(!preparedDraft.body.isEmpty)
            #expect(VendorReport.channel(for: prepared) != nil, "\(kind)")
        }
    }

    @Test func bothAgentsAndBothProvidersGetAChannel() throws {
        for agent in [AgentKind.claudeCode, .codex] {
            let prepared = incident(kind: .forcePushAttempt, agent: agent)
            let channel = try #require(VendorReport.channel(for: prepared))
            #expect(channel.page.host?.hasSuffix("github.com") == true)
            #expect(channel.securityPage != nil)
            #expect(channel.warning.contains("public"))
            #expect(channel.warning.contains("confirm first"))
        }
        for provider in VendorProvider.allCases {
            let prepared = vendor(provider: provider)
            let channel = try #require(VendorReport.channel(for: prepared))
            #expect(channel.securityPage == nil)
            #expect(channel.warning.contains("account details"))
            #expect(channel.page.absoluteString.hasPrefix("https://"))
        }
    }

    @Test func everyEvidenceValueThatCanReachADraftDoes() throws {
        let sentences: [(FindingEvidence, IncidentKind)] = [
            (.toolResult, .credentialReadAttempt),
            (.commandLine, .credentialReadAttempt),
            (.vendorFile, .unexplainedVendorUsage),
        ]
        for (evidence, kind) in sentences {
            let prepared = kind == .unexplainedVendorUsage
                ? vendor()
                : incident(kind: kind, agent: .claudeCode, evidence: evidence)
            let body = try draft(prepared).body
            #expect(body.contains(evidence.sentence), "\(evidence)")
        }
        // `transcriptRecord` kinds are info and never reach a draft.
        for kind in IncidentKind.allCases where kind.rule.severity == .info {
            #expect(VendorReport.draft(incident: incident(kind: kind, agent: .claudeCode), appVersion: "1", osVersion: "o") == nil)
        }
    }

    @Test func noPageCarriesAQuery() throws {
        var channels: [VendorChannel] = []
        for kind in IncidentKind.allCases where kind.rule.route != .none {
            for agent in [AgentKind.claudeCode, .codex] {
                if let channel = VendorReport.channel(for: incident(kind: kind, agent: agent)) {
                    channels.append(channel)
                    _ = kind
                }
            }
            if let channel = VendorReport.channel(for: vendor()) { channels.append(channel) }
        }
        #expect(!channels.isEmpty)
        for channel in channels {
            #expect(channel.page.query == nil)
            #expect(!channel.page.absoluteString.contains("?"))
            #expect(channel.page.scheme == "https")
            if let security = channel.securityPage {
                #expect(security.query == nil)
                #expect(!security.absoluteString.contains("?"))
                #expect(security.scheme == "https")
            }
        }
    }

    // MARK: - Mailto

    @Test func theMailtoHasNoRecipientAndRoundTrips() throws {
        let preparedDraft = try draft(incident(
            kind: .forcePushAttempt, agent: .codex, evidence: .commandLine,
            at: instant("2026-11-09T10:04:05Z")))
        let url = try #require(VendorReport.mailtoURL(preparedDraft))
        let string = url.absoluteString
        #expect(string.hasPrefix("mailto:?subject="))
        #expect(string.contains("?subject="))
        let read = try decoded(url)
        #expect(read.subject == preparedDraft.subject)
        #expect(read.body == preparedDraft.body)
    }

    @Test func theMailtoStaysWithinTheCapForAHugeBody() throws {
        var prepared = try draft(incident(kind: .forcePushAttempt, agent: .claudeCode))
        prepared.body = String(repeating: "a", count: 5_000)
        let url = try #require(VendorReport.mailtoURL(prepared))
        #expect(url.absoluteString.utf8.count <= VendorReport.maxMailtoBytes)
        let read = try decoded(url)
        #expect(read.subject == prepared.subject)
        #expect(prepared.body.hasPrefix(read.body))
        #expect(read.body.utf8.count > 1_000)
    }

    @Test func theMailtoCutsMultiByteCharactersWhole() throws {
        var prepared = try draft(incident(kind: .forcePushAttempt, agent: .claudeCode))
        prepared.body = String(repeating: "é", count: 2_000)
        let url = try #require(VendorReport.mailtoURL(prepared))
        #expect(url.absoluteString.utf8.count <= VendorReport.maxMailtoBytes)
        let read = try decoded(url)
        #expect(!read.body.isEmpty)
        #expect(read.body.allSatisfy { $0 == "é" })
        #expect(prepared.body.hasPrefix(read.body))

        // The encoded body never ends inside a percent escape.
        let parts = url.absoluteString.split(separator: "&", maxSplits: 1)
        let encodedBody = String(try #require(parts.last)).dropFirst("body=".count)
        #expect(hasWholeEscapes(String(encodedBody)))
        #expect(!encodedBody.hasSuffix("%"))
    }

    @Test func theMailtoSurvivesReservedCharacters() throws {
        var prepared = try draft(incident(kind: .forcePushAttempt, agent: .codex))
        prepared.body = "a+b & c=d % e#f ?g\nsecond line"
        let url = try #require(VendorReport.mailtoURL(prepared))
        let read = try decoded(url)
        #expect(read.body == prepared.body)
        let encoded = url.absoluteString
        #expect(!encoded.contains("+"))
        #expect(encoded.split(separator: "&").count == 2)
    }

    @Test func aSubjectTooLargeGivesNoURL() throws {
        var prepared = try draft(incident(kind: .forcePushAttempt, agent: .codex))
        prepared.subject = String(repeating: "s", count: VendorReport.maxMailtoBytes + 10)
        #expect(VendorReport.mailtoURL(prepared) == nil)
    }

    @Test func anAgentWithNoChannelRowHasADraftButNoChannel() throws {
        let prepared = incident(kind: .forcePushAttempt, agent: .openCode)
        _ = try draft(prepared)
        #expect(VendorReport.channel(for: prepared) == nil)
    }

    @Test func sentinelStringsNeverReachTheDraftOrTheURL() throws {
        let sentinel = "sk-ant-SENTINEL-DO-NOT-LEAK"
        let prepared = incident(
            kind: .credentialReadAttempt,
            agent: .claudeCode,
            at: instant("2026-11-09T10:04:05Z"),
            detail: .tool(.bash),
            anchor: sentinel,
            session: sentinel)
        let preparedDraft = try draft(prepared)
        let url = try #require(VendorReport.mailtoURL(preparedDraft))
        for text in [preparedDraft.subject, preparedDraft.body, url.absoluteString] {
            #expect(!text.contains(sentinel))
            #expect(!text.contains("sk-ant"))
            #expect(!text.contains(prepared.id.hex))
        }
    }
}
