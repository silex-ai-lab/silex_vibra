import Foundation
import Testing
@testable import VibraCore

/// Drives the incident extractors from `Fixtures/incident-cases.json`, one line
/// at a time, and pins the mechanism that the case table cannot express
/// (timestamps, the JSON shape of every evidence value, a secret-shaped session
/// id).
struct IncidentExtractorTests {
    private struct Expected: Equatable {
        let kind: String
        let evidence: String
        let detail: String
    }

    private struct Case {
        let name: String
        let agent: String
        let lines: [String]
        let expected: [Expected]
    }

    private struct MalformedFixture: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: - Fixture

    private static func line(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// A case's `lines` holds records, or a `{"repeat": n, "lines": [...]}`
    /// block whose `{i}` is replaced by the 1-based index. The cap case needs
    /// 257 distinct calls, and writing them out by hand is how a fixture rots.
    private static func expand(_ element: [String: Any]) -> [String] {
        guard let count = element["repeat"] as? Int,
              let lines = element["lines"] as? [[String: Any]]
        else { return [line(element)] }
        var out: [String] = []
        for index in 1...count {
            for object in lines {
                out.append(line(object).replacingOccurrences(of: "{i}", with: "\(index)"))
            }
        }
        return out
    }

    private static func load() throws -> [Case] {
        let url = fixtureURL("Fixtures/incident-cases.json")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        guard let raws = root?["cases"] as? [[String: Any]] else {
            throw MalformedFixture(description: "no cases array")
        }
        var cases: [Case] = []
        for raw in raws {
            guard let name = raw["name"] as? String,
                  let agent = raw["agent"] as? String,
                  let elements = raw["lines"] as? [[String: Any]],
                  let expected = raw["expect"] as? [[String: String]]
            else { throw MalformedFixture(description: "a case is missing a field") }
            cases.append(Case(
                name: name,
                agent: agent,
                lines: elements.flatMap(expand),
                expected: expected.map {
                    Expected(kind: $0["kind"] ?? "", evidence: $0["evidence"] ?? "", detail: $0["detail"] ?? "")
                }))
        }
        return cases
    }

    // MARK: - Running

    private func run(_ testCase: Case) -> [ExtractedIncident] {
        switch testCase.agent {
        case "codex":
            var extractor = CodexIncidentExtractor()
            return testCase.lines.flatMap { extractor.fold([$0]) }
        default:
            var extractor = ClaudeIncidentExtractor()
            return testCase.lines.flatMap { extractor.fold([$0]) }
        }
    }

    private func render(_ detail: IncidentDetail) -> String {
        switch detail {
        case .credential(let value): "credential:\(value.rawValue)"
        case .tool(let value): "tool:\(value.rawValue)"
        case .posture(let value): "posture:\(value.rawValue)"
        case .authError: "authError"
        case .vendorExcess(let value): "vendorExcess:\(value.provider.rawValue):\(value.day.iso)"
        }
    }

    private func signature(_ incidents: [ExtractedIncident]) -> [String] {
        incidents
            .map { "\($0.incident.kind.rawValue)|\($0.incident.evidence.rawValue)|\(render($0.incident.detail))" }
            .sorted()
    }

    // MARK: - The case table

    @Test func fixtureParsesEveryCase() throws {
        let cases = try Self.load()
        #expect(cases.count >= 80)
        #expect(Set(cases.map(\.name)).count == cases.count, "duplicate case name")
        #expect(cases.contains { $0.agent == "codex" })
    }

    @Test func caseTableMatches() throws {
        for testCase in try Self.load() {
            let incidents = run(testCase)
            let expected = testCase.expected
                .map { "\($0.kind)|\($0.evidence)|\($0.detail)" }
                .sorted()
            #expect(signature(incidents) == expected, "case: \(testCase.name)")
            for incident in incidents {
                #expect(!incident.rawSessionID.isEmpty, "case: \(testCase.name)")
            }
        }
    }

    // MARK: - Evidence

    @Test func allFourEvidenceValuesReachJSON() throws {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        for evidence in FindingEvidence.allCases {
            let incident = Incident(
                id: IncidentID(agent: .claudeCode, session: "s", kind: .credentialReadAttempt, anchor: "a"),
                kind: .credentialReadAttempt, agent: .claudeCode, evidence: evidence,
                at: at, completedAt: at, posture: .unknown, detail: .credential(.sshKey))
            let json = String(
                decoding: try IncidentJSON.encode([.init(incident: incident, disposition: .open)]),
                as: UTF8.self)
            #expect(json.contains("\"\(evidence.rawValue)\""), "evidence \(evidence.rawValue)")
        }
    }

    @Test func aSecretShapedSessionIDReachesNoOutput() throws {
        let sentinel = "sk-ant-SENTINEL-DO-NOT-LEAK"
        let testCase = try #require(try Self.load().first {
            $0.name == "a secret-shaped session id reaches no incident"
        })
        let incidents = run(testCase)
        #expect(incidents.count == 1)
        #expect(incidents.allSatisfy { $0.rawSessionID == sentinel })
        let json = String(
            decoding: try IncidentJSON.encode(incidents.map {
                IncidentJSON.Row(incident: $0.incident, disposition: .open)
            }),
            as: UTF8.self)
        for needle in [sentinel, "sk-ant", "/Users", ".aws", "credentials"] {
            #expect(!json.contains(needle), "leaked \(needle)")
        }
        #expect(!String(describing: incidents.map(\.incident)).contains(sentinel))
    }

    // MARK: - Timestamps

    private func claudeUse(_ id: String, _ command: String, at seconds: TimeInterval) -> String {
        EvidenceFixtures.json([
            "type": "assistant", "sessionId": "s", "cwd": "/Users/demo/workplace/sample",
            "timestamp": EvidenceFixtures.stamp(seconds),
            "message": ["role": "assistant", "content": [
                ["type": "tool_use", "id": id, "name": "Bash", "input": ["command": command]] as [String: Any],
            ]] as [String: Any],
        ])
    }

    private func claudeResult(_ id: String, _ text: String, isError: Bool = false, at seconds: TimeInterval) -> String {
        EvidenceFixtures.json([
            "type": "user", "sessionId": "s", "timestamp": EvidenceFixtures.stamp(seconds),
            "message": ["role": "user", "content": [
                ["type": "tool_result", "tool_use_id": id, "content": text, "is_error": isError] as [String: Any],
            ]] as [String: Any],
        ])
    }

    @Test func aDeniedRetryIsDatedAtTheDenialAndCompletesAtTheRetry() throws {
        let lines = [
            claudeUse("u1", "cat ~/.netrc", at: 10),
            claudeResult("u1", "The user doesn't want to proceed with this tool use.", isError: true, at: 11),
            claudeUse("u2", "cat ~/.netrc", at: 20),
            claudeResult("u2", "ok", at: 21),
        ]
        var extractor = ClaudeIncidentExtractor()
        let incidents = lines.flatMap { extractor.fold([$0]) }
        let denied = try #require(incidents.first { $0.incident.kind == .deniedCallRanLater })
        #expect(denied.incident.at == parseISODate(EvidenceFixtures.stamp(10)))
        #expect(denied.incident.completedAt == parseISODate(EvidenceFixtures.stamp(21)))
        let read = try #require(incidents.first { $0.incident.kind == .credentialReadAttempt })
        #expect(read.incident.at == parseISODate(EvidenceFixtures.stamp(20)))
    }

    @Test func aTimestamplessModeRecordUsesTheFirstTimestampedRecord() throws {
        let lines = [
            EvidenceFixtures.json(["type": "permission-mode", "sessionId": "s", "permissionMode": "bypassPermissions"]),
            claudeUse("u1", "ls", at: 5),
            claudeResult("u1", "ok", at: 6),
        ]
        var extractor = ClaudeIncidentExtractor()
        let incidents = lines.flatMap { extractor.fold([$0]) }
        let unrestricted = try #require(incidents.first { $0.incident.kind == .unrestrictedSession })
        #expect(unrestricted.incident.at == parseISODate(EvidenceFixtures.stamp(5)))
        #expect(unrestricted.incident.evidence == .transcriptRecord)
    }

    @Test func aCodexCommandStartsAtCompletionMinusItsDuration() throws {
        let meta = EvidenceFixtures.json([
            "type": "session_meta", "timestamp": EvidenceFixtures.stamp(0),
            "payload": ["session_id": "s", "id": "s", "cwd": "/Users/demo/workplace/sample"],
        ])
        let turn = EvidenceFixtures.json([
            "type": "turn_context", "timestamp": EvidenceFixtures.stamp(0),
            "payload": ["cwd": "/Users/demo/workplace/sample", "workspace_roots": ["/Users/demo/workplace/sample"]],
        ])
        let command = EvidenceFixtures.codexItem([
            "type": "CommandExecution", "id": "c1", "command": ["zsh", "-lc", "git push -f"],
            "aggregated_output": "", "duration": ["secs": 8, "nanos": 0],
            "status": "failed", "exit_code": 1,
        ], at: 20)
        var extractor = CodexIncidentExtractor()
        let incidents = [meta, turn, command].flatMap { extractor.fold([$0]) }
        let force = try #require(incidents.first { $0.incident.kind == .forcePushAttempt })
        #expect(force.incident.at == parseISODate(EvidenceFixtures.stamp(12)))
        #expect(force.incident.completedAt == parseISODate(EvidenceFixtures.stamp(20)))
        #expect(force.incident.evidence == .commandLine)
    }

    @Test func aBackgroundedShellCommandIsNeverToolResult() throws {
        let lines = [
            EvidenceFixtures.json([
                "type": "assistant", "sessionId": "s", "cwd": "/Users/demo/workplace/sample",
                "timestamp": EvidenceFixtures.stamp(1),
                "message": ["role": "assistant", "content": [
                    ["type": "tool_use", "id": "u1", "name": "Bash",
                     "input": ["command": "cat ~/.netrc", "run_in_background": true]] as [String: Any],
                ]] as [String: Any],
            ]),
            claudeResult("u1", "Command running in background with ID: bash_1", at: 2),
        ]
        var extractor = ClaudeIncidentExtractor()
        let incidents = lines.flatMap { extractor.fold([$0]) }
        #expect(incidents.count == 1)
        #expect(incidents.first?.incident.evidence == .commandLine)
    }
}
