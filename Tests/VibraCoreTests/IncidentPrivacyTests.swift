import Foundation
import Testing

@testable import VibraCore

@Suite struct IncidentJSONShapeTests {
    private func row(_ detail: IncidentDetail, disposition: Disposition) -> IncidentJSON.Row {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        return IncidentJSON.Row(
            incident: Incident(
                id: IncidentID(agent: .claudeCode, session: "s", kind: .forcePushAttempt, anchor: "a"),
                kind: .forcePushAttempt, agent: .claudeCode, evidence: .commandLine,
                at: at, completedAt: at, posture: .unknown, detail: detail),
            disposition: disposition)
    }

    private func object(_ row: IncidentJSON.Row) throws -> [String: Any] {
        let data = try IncidentJSON.encode([row])
        let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return try #require(array.first)
    }

    @Test func topLevelKeysAreExactlyTheBoundedSet() throws {
        let keys = Set(try object(row(.authError, disposition: .open)).keys)
        #expect(keys == [
            "id", "kind", "severity", "agent", "evidence", "at", "completedAt", "posture", "detail", "disposition",
        ])
    }

    @Test func detailKeysCarryOnlyTheVariantsValues() throws {
        let day = try #require(UTCDay(iso: "2026-11-01"))
        let excess = VendorExcess(provider: .anthropic, day: day, vendorTokens: 900, localTokens: 100)
        let vendor = try #require(try object(row(.vendorExcess(excess), disposition: .open))["detail"] as? [String: Any])
        #expect(Set(vendor.keys) == ["type", "provider", "day", "vendorTokens", "localTokens"])
        #expect(vendor["day"] as? String == "2026-11-01")

        let write = try #require(try object(row(.write(.edit, .elsewhere), disposition: .open))["detail"] as? [String: Any])
        #expect(Set(write.keys) == ["type", "tool", "writeFamily"])
        #expect(write["writeFamily"] as? String == "elsewhere")

        let credential = try #require(try object(row(.credential(.sshKey), disposition: .open))["detail"] as? [String: Any])
        #expect(Set(credential.keys) == ["type", "credentialClass"])
    }

    @Test func openHasNoDateAndAClosedAnswerDoes() throws {
        let open = try #require(try object(row(.authError, disposition: .open))["disposition"] as? [String: Any])
        #expect(Set(open.keys) == ["state"])
        let closed = try #require(
            try object(row(.authError, disposition: .resolved(at: Date(timeIntervalSince1970: 1))))["disposition"] as? [String: Any])
        #expect(closed["state"] as? String == "resolved")
        #expect(closed["at"] as? String == "1970-01-01T00:00:01Z")
    }
}

@Suite struct IncidentFoundationTests {
    @Test func utcDayRejectsNonDates() {
        #expect(UTCDay(iso: "2026-02-30") == nil)
        #expect(UTCDay(iso: "2026-11-1") == nil)
        #expect(UTCDay(iso: "sk-ant-secret") == nil)
        #expect(UTCDay(iso: "2026-11-01")?.iso == "2026-11-01")
    }

    @Test func utcDayOfAnInstantIsTheUTCCalendarDay() {
        let lateEvening = Date(timeIntervalSince1970: 1_794_182_399)
        let afterMidnight = Date(timeIntervalSince1970: 1_794_182_400)
        #expect(UTCDay(date: lateEvening).iso == "2026-11-08")
        #expect(UTCDay(date: afterMidnight).iso == "2026-11-09")
    }

    @Test func idChangesWithEveryComponent() {
        let base = IncidentID(agent: .codex, session: "s", kind: .forcePushAttempt, anchor: "a")
        #expect(base != IncidentID(agent: .claudeCode, session: "s", kind: .forcePushAttempt, anchor: "a"))
        #expect(base != IncidentID(agent: .codex, session: "t", kind: .forcePushAttempt, anchor: "a"))
        #expect(base != IncidentID(agent: .codex, session: "s", kind: .authFailure, anchor: "a"))
        #expect(base != IncidentID(agent: .codex, session: "s", kind: .forcePushAttempt, anchor: "b"))
        #expect(base.hex.count == 64)
    }

    @Test func infoKindsNeverRouteAndBillingIsOnlyVendorFindings() {
        for kind in IncidentKind.allCases where kind.rule.severity == .info {
            #expect(kind.rule.route == .none)
        }
        let billing = IncidentKind.allCases.filter { $0.rule.route == .billing }
        #expect(billing == [.unexplainedVendorUsage])
    }
}

@Suite struct IncidentPrivacyTests {
    private static let sentinel = "SENTINEL9f3a"
    private static let session = "sk-ant-\(sentinel)"
    private static let cwd = "/Users/demo/\(sentinel)/proj"

    private func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    private func claudeCall(_ id: String, _ name: String, _ input: [String: Any], second: Int) throws -> [String] {
        let stamp = String(format: "2026-11-08T10:00:%02d.000Z", second)
        return [
            try json([
                "type": "assistant", "timestamp": stamp, "sessionId": Self.session, "cwd": Self.cwd,
                "message": ["role": "assistant", "content": [["type": "tool_use", "id": id, "name": name, "input": input] as [String: Any]]] as [String: Any],
            ]),
            try json([
                "type": "user", "timestamp": stamp, "sessionId": Self.session, "cwd": Self.cwd,
                "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": id, "content": "output \(Self.sentinel)"]]] as [String: Any],
            ]),
        ]
    }

    private func claudeIncidents() throws -> [Incident] {
        var lines = [try json([
            "type": "user", "timestamp": "2026-11-08T09:59:00.000Z", "sessionId": Self.session, "cwd": Self.cwd,
            "message": ["role": "user", "content": "prompt \(Self.sentinel)"] as [String: Any],
        ])]
        lines += try claudeCall("u1", "Bash", ["command": "cat ~/.aws/credentials \(Self.sentinel)"], second: 1)
        lines += try claudeCall("u2", "Read", ["file_path": "/opt/\(Self.sentinel)/.env"], second: 2)
        lines += try claudeCall("u3", "Write", ["file_path": "/opt/\(Self.sentinel)/x.swift", "content": Self.sentinel], second: 3)
        lines += try claudeCall("u4", "Bash", ["command": "git push --force origin \(Self.sentinel)"], second: 4)
        lines.append(try json([
            "type": "assistant", "timestamp": "2026-11-08T10:00:05.000Z", "sessionId": Self.session, "cwd": Self.cwd,
            "isApiErrorMessage": true, "error": "authentication_failed", "uuid": "uuid-\(Self.sentinel)",
            "message": ["role": "assistant", "content": [["type": "text", "text": Self.sentinel]]] as [String: Any],
        ]))
        var extractor = ClaudeIncidentExtractor()
        return extractor.fold(lines).map(\.incident)
    }

    private func codexIncidents() throws -> [Incident] {
        let lines = [
            try json(["type": "session_meta", "timestamp": "2026-11-08T10:00:00.000Z", "payload": ["session_id": Self.session, "cwd": Self.cwd]]),
            try json(["type": "turn_context", "timestamp": "2026-11-08T10:00:00.000Z", "payload": [
                "cwd": Self.cwd, "workspace_roots": [Self.cwd], "sandbox_policy": ["type": "danger-full-access"],
            ] as [String: Any]]),
            try json(["type": "event_msg", "timestamp": "2026-11-08T10:00:05.000Z", "payload": [
                "type": "item_completed",
                "item": ["type": "CommandExecution", "id": "i1", "status": "completed", "exit_code": 0,
                         "command": ["bash", "-lc", "cat ~/.ssh/id_rsa \(Self.sentinel)"], "aggregated_output": Self.sentinel] as [String: Any],
            ] as [String: Any]]),
            try json(["type": "event_msg", "timestamp": "2026-11-08T10:00:06.000Z", "payload": [
                "type": "item_completed",
                "item": ["type": "FileChange", "id": "i2", "status": "completed", "changes": ["/opt/\(Self.sentinel)/y.swift": [:] as [String: Any]]] as [String: Any],
            ] as [String: Any]]),
        ]
        var extractor = CodexIncidentExtractor()
        return extractor.fold(lines).map(\.incident)
    }

    private func vendorIncident() throws -> Incident {
        let now = Date(timeIntervalSince1970: 1_754_179_200)
        let file = try VendorUsage.parse(try JSONSerialization.data(withJSONObject: [
            "object": "page", "has_more": false, "next_page": NSNull(),
            "data": [["object": "bucket", "start_time": 1_754_006_400, "end_time": 1_754_092_800, "results": [[
                "input_tokens": 900_000, "output_tokens": 100_000, "api_key_id": "key_\(Self.sentinel)",
            ] as [String: Any]]] as [String: Any]],
        ] as [String: Any]), now: now)
        let local = [LocalDay(day: try #require(UTCDay(iso: "2025-07-31")), tokens: 1)]
        return try #require(VendorUsage.reconcile(file, local: local, now: now).incidents.first)
    }

    @Test func incidentSentinelsNeverLeak() async throws {
        let claude = try claudeIncidents()
        let codex = try codexIncidents()
        let vendor = try vendorIncident()
        #expect(Set(claude.map(\.kind)) == [.credentialReadAttempt, .writeToPathOutsideWorkspace, .forcePushAttempt, .authFailure])
        #expect(Set(codex.map(\.kind)) == [.unrestrictedSession, .credentialReadAttempt, .writeToPathOutsideWorkspace])

        let all = claude + codex + [vendor]
        let rows = all.map { IncidentJSON.Row(incident: $0, disposition: .open) }
        var surfaces = all.map { String(describing: $0) }
        surfaces.append(String(decoding: try IncidentJSON.encode(rows), as: UTF8.self))
        surfaces.append(IncidentText.render(rows))
        surfaces += rows.map(IncidentText.summary)

        for incident in all {
            guard let draft = VendorReport.draft(incident: incident, appVersion: "1", osVersion: "macOS") else { continue }
            surfaces += [draft.subject, draft.body]
            let mailto = try #require(VendorReport.mailtoURL(draft))
            surfaces.append(mailto.absoluteString)
            surfaces.append(try #require(mailto.absoluteString.removingPercentEncoding))
            let channel = try #require(VendorReport.channel(for: incident))
            surfaces += [channel.page.absoluteString, channel.securityPage?.absoluteString ?? "", channel.warning]
            #expect(channel.page.query == nil)
            #expect(channel.securityPage?.query == nil)
        }

        let directory = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("incidents.json")
        let store = IncidentStore(url: url)
        await store.commit(watermark: Date())
        for incident in all { await store.set(.resolved(at: Date()), for: incident.id) }
        let stored = try String(contentsOf: url, encoding: .utf8)
        surfaces.append(stored)

        let lowered = Self.sentinel.lowercased()
        for surface in surfaces {
            #expect(!surface.lowercased().contains(lowered), "leak: \(surface.prefix(160))")
        }

        let ids = Set(all.map(\.id.hex))
        let digests = stored.matches(of: /[0-9a-f]{64}/).map { String($0.output) }
        #expect(!digests.isEmpty)
        #expect(digests.allSatisfy(ids.contains))
    }

    @Test func aFailedImportNamesNeitherTheKeyNorAValue() throws {
        let page: [String: Any] = [
            "object": "page", "has_more": false, "next_page": NSNull(),
            "data": [["start_time": 1_754_006_400, "results": [
                ["input_tokens": 1, "output_tokens": 1, "api_key_id": "a_\(Self.sentinel)"],
                ["input_tokens": 1, "output_tokens": 1, "api_key_id": "b_\(Self.sentinel)"],
            ]] as [String: Any]],
        ]
        do {
            _ = try VendorUsage.parse(try JSONSerialization.data(withJSONObject: page), now: Date(timeIntervalSince1970: 1_754_179_200))
            Issue.record("two keys must be refused")
        } catch {
            #expect(!String(describing: error).contains(Self.sentinel))
        }
    }
}
