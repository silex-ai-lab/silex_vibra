import Foundation
import Testing
@testable import VibraCore

/// Detection decides what gets polled at all, so a wrong answer either hides
/// a working agent or costs CPU on one that was never installed.
struct AgentDetectorTests {

    /// Minimal stand-in: presence and sources are whatever the test says.
    private struct FakeAdapter: AgentAdapter {
        let kind: AgentKind
        let isAvailable: Bool
        let fakeSources: [SourceDescriptor]

        func discoverSessions() throws -> [Session] { [] }
        func sources() throws -> [SourceDescriptor] { fakeSources }
        func update(source: SourceDescriptor, input: SourceInput, previous: ParsedState?) throws -> ParsedState {
            .empty
        }
    }

    private func descriptor(_ name: String, modified: Date) -> SourceDescriptor {
        SourceDescriptor(
            url: URL(fileURLWithPath: "/fake/\(name)"),
            deviceID: 1, fileID: UInt64(abs(name.hashValue % 100_000)),
            size: 10, modified: modified
        )
    }

    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func absentAgentIsNotPolled() {
        let adapters: [any AgentAdapter] = [
            FakeAdapter(kind: .claudeCode, isAvailable: true, fakeSources: [descriptor("a", modified: now)]),
            FakeAdapter(kind: .codex, isAvailable: false, fakeSources: []),
        ]
        let detector = AgentDetector(adapters: adapters)
        #expect(detector.activeAdapters().map(\.kind) == [.claudeCode],
                "an agent with no state on disk must not be polled")
    }

    @Test func detectionReportsSourceCountAndLatestWrite() {
        let newest = now
        let older = now.addingTimeInterval(-86_400)
        let adapter = FakeAdapter(
            kind: .claudeCode,
            isAvailable: true,
            fakeSources: [descriptor("a", modified: older), descriptor("b", modified: newest)]
        )
        let d = AgentDetector(adapters: [adapter]).detect(adapter)
        #expect(d.isPresent)
        #expect(d.sourceCount == 2)
        #expect(d.lastActivity == newest, "must report the most recent write, not the first")
    }

    @Test func absentAgentReportsNoActivity() {
        let adapter = FakeAdapter(kind: .codex, isAvailable: false, fakeSources: [])
        let d = AgentDetector(adapters: [adapter]).detect(adapter)
        #expect(!d.isPresent)
        #expect(d.sourceCount == 0)
        #expect(d.lastActivity == nil)
        #expect(!d.isActive(within: 12 * 3600, now: now))
    }

    @Test func presentButStaleAgentIsNotActive() {
        // Installed and has transcripts, but nothing recent: it should still be
        // detected (its history is readable) yet not counted as active.
        let adapter = FakeAdapter(
            kind: .openCode,
            isAvailable: true,
            fakeSources: [descriptor("old", modified: now.addingTimeInterval(-30 * 86_400))]
        )
        let d = AgentDetector(adapters: [adapter]).detect(adapter)
        #expect(d.isPresent)
        #expect(!d.isActive(within: 12 * 3600, now: now))
    }

    @Test func detectAllCoversEveryKnownKindThatHasAnAdapter() {
        let adapters: [any AgentAdapter] = AgentKind.allCases.map {
            FakeAdapter(kind: $0, isAvailable: true, fakeSources: [descriptor("x\($0.rawValue)", modified: now)])
        }
        let all = AgentDetector(adapters: adapters).detectAll()
        #expect(Set(all.map(\.kind)) == Set(AgentKind.allCases))
    }

    @Test func unknownAdapterlessKindIsSkippedNotCrashed() {
        // Only one adapter supplied: detectAll must not invent entries.
        let adapters: [any AgentAdapter] = [
            FakeAdapter(kind: .codex, isAvailable: true, fakeSources: [descriptor("c", modified: now)])
        ]
        let all = AgentDetector(adapters: adapters).detectAll()
        #expect(all.map(\.kind) == [.codex])
    }
}
