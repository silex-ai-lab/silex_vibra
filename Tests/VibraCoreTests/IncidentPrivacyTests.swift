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
