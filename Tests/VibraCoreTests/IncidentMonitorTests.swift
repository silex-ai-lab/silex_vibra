import Foundation
import Testing
@testable import VibraCore

private struct LineExtractor: IncidentExtractor {
    mutating func fold(_ lines: [String]) -> [ExtractedIncident] {
        lines.compactMap { line in
            let parts = line.split(separator: ",").map(String.init)
            guard parts.count == 3, let completed = TimeInterval(parts[1]), let kind = IncidentKind(rawValue: parts[2])
            else { return nil }
            let date = Date(timeIntervalSince1970: completed)
            return ExtractedIncident(
                incident: Incident(
                    id: IncidentID(agent: .claudeCode, session: "s", kind: kind, anchor: parts[0]),
                    kind: kind, agent: .claudeCode, evidence: .toolResult,
                    at: date, completedAt: date, posture: .unknown, detail: .tool(.bash)),
                rawSessionID: "session-\(parts[0])")
        }
    }
}

private struct TreeAdapter: AgentAdapter {
    let kind = AgentKind.claudeCode
    let root: URL
    var isAvailable: Bool { true }

    func discoverSessions() throws -> [Session] { [] }

    func sources() throws -> [SourceDescriptor] {
        let names = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return names.compactMap(SourceDescriptor.describing)
    }

    func update(source: SourceDescriptor, input: SourceInput, previous: ParsedState?) throws -> ParsedState {
        throw SourceListError()
    }

    func incidentExtractor() -> (any IncidentExtractor)? { LineExtractor() }
}

private final class Delivered: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [AttentionNotification] = []

    func add(_ notification: AttentionNotification) {
        lock.lock(); defer { lock.unlock() }
        values.append(notification)
    }

    var all: [AttentionNotification] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ seconds: TimeInterval) { value = Date(timeIntervalSince1970: seconds) }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value = value.addingTimeInterval(seconds)
    }
}

@Suite struct IncidentMonitorTests {
    private static let launch: TimeInterval = 1_800_000_000

    private final class Tree {
        let root: URL
        let storeURL: URL
        let clock = Clock(IncidentMonitorTests.launch)

        init() throws {
            root = testScratchDirectory().appendingPathComponent(UUID().uuidString)
            storeURL = root.appendingPathComponent("state/incidents.json")
            try FileManager.default.createDirectory(at: transcripts, withIntermediateDirectories: true)
        }

        var transcripts: URL { root.appendingPathComponent("t") }

        deinit { try? FileManager.default.removeItem(at: root) }

        func url(_ name: String) -> URL { transcripts.appendingPathComponent(name) }

        func write(_ name: String, _ lines: [String], modified: Date? = nil) throws {
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url(name))
            try FileManager.default.setAttributes([.modificationDate: modified ?? clock.now], ofItemAtPath: url(name).path)
        }

        func append(_ name: String, _ line: String) throws {
            let handle = try FileHandle(forWritingTo: url(name))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
            try FileManager.default.setAttributes([.modificationDate: clock.now], ofItemAtPath: url(name).path)
        }

        func monitor(store: IncidentStore? = nil, into sink: Delivered, interval: TimeInterval = 0) -> (IncidentMonitor, IncidentStore) {
            let clock = self.clock
            let resolved = store ?? IncidentStore(url: storeURL, now: { clock.now })
            let monitor = IncidentMonitor(
                adapters: [TreeAdapter(root: transcripts)], store: resolved, now: { clock.now },
                deliveryInterval: interval, deliver: { sink.add($0) })
            return (monitor, resolved)
        }
    }

    private func line(_ anchor: String, after seconds: TimeInterval, _ kind: IncidentKind = .forcePushAttempt) -> String {
        "\(anchor),\(Self.launch + seconds),\(kind.rawValue)"
    }

    @Test func firstRunFindsBackfillWithoutNotifying() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("old", after: -100)])
        let sink = Delivered()
        let (monitor, _) = tree.monitor(into: sink)

        let stats = await monitor.poll()

        #expect(stats.newIncidents == 1)
        #expect(sink.all.isEmpty)
        #expect(await monitor.rows().count == 1)
    }

    @Test func idlePollReadsNothing() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("a", after: -100)])
        let (monitor, _) = tree.monitor(into: Delivered())
        await monitor.poll()

        let idle = await monitor.poll()

        #expect(idle.bytesRead == 0)
    }

    @Test func aNewFindingNotifiesOnceWithACountOnlyBody() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("a", after: -100)])
        let sink = Delivered()
        let (monitor, _) = tree.monitor(into: sink)
        await monitor.poll()

        tree.clock.advance(30)
        try tree.append("a.jsonl", line("b", after: 20))
        await monitor.poll()
        await monitor.poll()

        #expect(sink.all.count == 1)
        #expect(sink.all.first?.key == "incident:review")
        #expect(sink.all.first?.body == "1 item to review.")
    }

    @Test func infoSeverityNeverNotifies() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("a", after: -100)])
        let sink = Delivered()
        let (monitor, _) = tree.monitor(into: sink)
        await monitor.poll()

        tree.clock.advance(30)
        try tree.append("a.jsonl", line("b", after: 20, .authFailure))
        await monitor.poll()

        #expect(sink.all.isEmpty)
    }

    @Test func restartReplaysTheSameIdsAndDoesNotReNotify() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("a", after: -100)])
        let first = Delivered()
        let (monitor, store) = tree.monitor(into: first)
        await monitor.poll()
        tree.clock.advance(30)
        try tree.append("a.jsonl", line("b", after: 20))
        await monitor.poll()
        #expect(first.all.count == 1)
        let ids = await monitor.rows().map(\.incident.id)
        await store.set(.resolved(at: tree.clock.now), for: ids[0])

        let second = Delivered()
        let (restarted, _) = tree.monitor(into: second)
        await restarted.poll()

        #expect(await restarted.rows().map(\.incident.id) == ids)
        #expect(await restarted.rows()[0].disposition == .resolved(at: tree.clock.now))
        #expect(second.all.isEmpty)
    }

    @Test func aFindingCompletedWhileClosedNotifiesAtTheNextLaunch() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("a", after: -100)])
        let (monitor, _) = tree.monitor(into: Delivered())
        await monitor.poll()

        tree.clock.advance(300)
        try tree.append("a.jsonl", line("b", after: 200))
        let sink = Delivered()
        let (restarted, _) = tree.monitor(into: sink)
        await restarted.poll()

        #expect(sink.all.count == 1)
    }

    @Test func aFailedCommitDeliversNothingAndTheNextReplayFindsTheBatch() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("a", after: -100)])
        let dead = Delivered()
        let (monitor, _) = tree.monitor(into: dead)
        await monitor.poll()

        let directory = tree.storeURL.deletingLastPathComponent()
        tree.clock.advance(30)
        try tree.append("a.jsonl", line("b", after: 20))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        await monitor.poll()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        #expect(dead.all.isEmpty)

        let sink = Delivered()
        let (restarted, _) = tree.monitor(into: sink)
        await restarted.poll()

        #expect(sink.all.count == 1)
    }

    @Test func aCrashBetweenCommitAndDeliveryNeverDuplicates() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("a", after: -100)])
        let lost = Delivered()
        let (monitor, _) = tree.monitor(into: lost)
        await monitor.poll()
        tree.clock.advance(30)
        try tree.append("a.jsonl", line("b", after: 20))
        await monitor.poll()

        let sink = Delivered()
        let (restarted, _) = tree.monitor(into: sink)
        await restarted.poll()

        #expect(sink.all.isEmpty)
        #expect(await restarted.rows().count == 2)
    }

    @Test func aDeferredBatchIsCommittedWhenDelivered() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("a", after: -100)])
        let sink = Delivered()
        let (monitor, store) = tree.monitor(into: sink, interval: 60)
        await monitor.poll()

        tree.clock.advance(5)
        try tree.append("a.jsonl", line("b", after: 3))
        await monitor.poll()
        #expect(sink.all.count == 1)

        tree.clock.advance(10)
        try tree.append("a.jsonl", line("c", after: 12))
        await monitor.poll()
        #expect(sink.all.count == 1)
        #expect(await store.watermark() == Date(timeIntervalSince1970: Self.launch + 3))

        tree.clock.advance(60)
        await monitor.poll()
        #expect(sink.all.count == 2)
        #expect(await store.watermark() == Date(timeIntervalSince1970: Self.launch + 12))
    }

    @Test func aBatchOlderThanTheWatermarkCannotMoveItBack() async throws {
        let tree = try Tree()
        let store = IncidentStore(url: tree.storeURL, now: { [clock = tree.clock] in clock.now })
        let high = Date(timeIntervalSince1970: Self.launch + 500)
        await store.commit(watermark: high)

        await store.commit(watermark: Date(timeIntervalSince1970: Self.launch))

        #expect(await store.watermark() == high)
    }

    @Test func aFileAgingOutDropsItsStateAndItsLaterAppendDoesNotReAlert() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("a", after: -100)])
        let sink = Delivered()
        let (monitor, _) = tree.monitor(into: sink)
        await monitor.poll()

        tree.clock.advance(8 * 86_400)
        await monitor.poll()
        #expect(await monitor.rows().isEmpty)
        #expect(await monitor.rawSessionID(for: IncidentID(agent: .claudeCode, session: "s", kind: .forcePushAttempt, anchor: "a")) == nil)

        try tree.append("a.jsonl", line("z", after: -50))
        await monitor.poll()
        #expect(await monitor.rows().count == 2)
        #expect(sink.all.isEmpty)
    }

    private func expectReplay(after change: (Tree) throws -> Void, expected: Int) async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("first-long-anchor", after: -100), line("b", after: -90)])
        let (monitor, _) = tree.monitor(into: Delivered())
        await monitor.poll()
        tree.clock.advance(30)

        try change(tree)
        let stats = await monitor.poll()

        #expect(stats.bytesRead > 0)
        #expect(await monitor.rows().count == expected)
    }

    @Test func aShrunkFileIsReadFromTheStart() async throws {
        try await expectReplay(after: { try $0.write("a.jsonl", [self.line("x", after: -80)]) }, expected: 1)
    }

    @Test func aReplacedInodeIsReadFromTheStart() async throws {
        try await expectReplay(
            after: { tree in
                let replacement = tree.root.appendingPathComponent("replacement.jsonl")
                let lines = [self.line("first-long-anchor", after: -100), self.line("b", after: -90), self.line("c", after: -70)]
                try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: replacement)
                _ = try FileManager.default.replaceItemAt(tree.url("a.jsonl"), withItemAt: replacement)
                try FileManager.default.setAttributes([.modificationDate: tree.clock.now], ofItemAtPath: tree.url("a.jsonl").path)
            },
            expected: 3)
    }

    @Test func aSameSizeRewriteIsReadFromTheStart() async throws {
        try await expectReplay(
            after: { try $0.write("a.jsonl", [self.line("FIRST-LONG-ANCHOR", after: -100), self.line("B", after: -90)]) },
            expected: 2)
    }

    @Test func aSameSizeRewriteWithAPartialFinalLineIsReadFromTheStart() async throws {
        let tree = try Tree()
        let first = line("aaaa", after: -100)
        try Data((first + "\npartial").utf8).write(to: tree.url("a.jsonl"))
        let (monitor, _) = tree.monitor(into: Delivered())
        await monitor.poll()
        let before = await monitor.rows().map(\.incident.id)

        tree.clock.advance(30)
        let rewritten = line("bbbb", after: -100)
        try Data((rewritten + "\npartial").utf8).write(to: tree.url("a.jsonl"))
        try FileManager.default.setAttributes([.modificationDate: tree.clock.now], ofItemAtPath: tree.url("a.jsonl").path)
        await monitor.poll()

        let after = await monitor.rows().map(\.incident.id)
        #expect(after.count == 1)
        #expect(after != before)
    }

    @Test func theSameIdInTwoFilesKeepsTheEarliestAndSurvivesOneLeaving() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("same", after: -50)])
        try tree.write("b.jsonl", [line("same", after: -100)])
        let (monitor, _) = tree.monitor(into: Delivered())
        await monitor.poll()
        #expect(await monitor.rows().count == 1)
        #expect(await monitor.rows()[0].incident.at == Date(timeIntervalSince1970: Self.launch - 100))

        try FileManager.default.removeItem(at: tree.url("a.jsonl"))
        await monitor.poll()

        #expect(await monitor.rows().count == 1)
    }

    @Test func vendorFindingsNeverNotifyNorTouchTheWatermark() async throws {
        let tree = try Tree()
        let sink = Delivered()
        let (monitor, store) = tree.monitor(into: sink)
        await monitor.poll()
        let before = await store.watermark()
        let day = try #require(UTCDay(iso: "2026-11-01"))
        let excess = VendorExcess(provider: .openai, day: day, vendorTokens: 900, localTokens: 1)
        let at = tree.clock.now.addingTimeInterval(1000)

        let id = IncidentID(agent: nil, session: nil, kind: .unexplainedVendorUsage, anchor: "openai|2026-11-01|k")
        let incident = Incident(
            id: id, kind: .unexplainedVendorUsage, agent: nil, evidence: .vendorFile,
            at: at, completedAt: at, posture: .unknown, detail: .vendorExcess(excess))
        #expect(await monitor.replaceVendorIncidents(scope: [id], with: [incident]))
        await monitor.poll()

        #expect(await monitor.rows().count == 1)
        #expect(sink.all.isEmpty)
        #expect(await store.watermark() == before)
    }

    private func outside(_ after: TimeInterval) -> String {
        line("family", after: after, .writeToPathOutsideWorkspace)
    }

    @Test func aLaterWriteReopensAnAnsweredSessionFindingAndNotifies() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [outside(-100)])
        let sink = Delivered()
        let (monitor, store) = tree.monitor(into: sink)
        await monitor.poll()
        let id = await monitor.rows()[0].incident.id
        await store.set(.expected(at: tree.clock.now), for: id)
        #expect(await monitor.rows()[0].disposition == .expected(at: tree.clock.now))

        tree.clock.advance(30)
        try tree.append("a.jsonl", outside(20))
        await monitor.poll()

        #expect(await monitor.rows().count == 1)
        #expect(await monitor.rows()[0].disposition == .open)
        #expect(sink.all.count == 1)
    }

    @Test func aWriteBeforeTheAnswerDoesNotReopenItAcrossARestart() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [outside(-100), outside(-50)])
        let (monitor, store) = tree.monitor(into: Delivered())
        await monitor.poll()
        let answeredAt = tree.clock.now
        await store.set(.resolved(at: answeredAt), for: await monitor.rows()[0].incident.id)

        let sink = Delivered()
        let (restarted, _) = tree.monitor(into: sink)
        await restarted.poll()

        #expect(await restarted.rows()[0].disposition == .resolved(at: answeredAt))
        #expect(sink.all.isEmpty)
    }

    @Test func aReopenedFindingStaysOpenAcrossARestart() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [outside(-100)])
        let (monitor, store) = tree.monitor(into: Delivered())
        await monitor.poll()
        await store.set(.expected(at: tree.clock.now), for: await monitor.rows()[0].incident.id)
        tree.clock.advance(30)
        try tree.append("a.jsonl", outside(20))
        await monitor.poll()

        let sink = Delivered()
        let (restarted, _) = tree.monitor(into: sink)
        await restarted.poll()

        #expect(await restarted.rows()[0].disposition == .open)
        #expect(sink.all.isEmpty)
    }

    @Test func aRepeatWhileStillOpenDoesNotNotifyAgain() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [outside(-100)])
        let sink = Delivered()
        let (monitor, _) = tree.monitor(into: sink)
        await monitor.poll()

        tree.clock.advance(30)
        try tree.append("a.jsonl", outside(20))
        await monitor.poll()

        #expect(sink.all.isEmpty)
    }

    @Test func aCorrectedReimportRemovesAFindingThatNoLongerHolds() async throws {
        let tree = try Tree()
        let (monitor, _) = tree.monitor(into: Delivered())
        let day = try #require(UTCDay(iso: "2026-11-01"))
        let id = IncidentID(agent: nil, session: nil, kind: .unexplainedVendorUsage, anchor: "openai|2026-11-01|k")
        let at = tree.clock.now
        let incident = Incident(
            id: id, kind: .unexplainedVendorUsage, agent: nil, evidence: .vendorFile, at: at, completedAt: at,
            posture: .unknown, detail: .vendorExcess(VendorExcess(provider: .openai, day: day, vendorTokens: 9, localTokens: 1)))
        _ = await monitor.replaceVendorIncidents(scope: [id], with: [incident])
        #expect(await monitor.rows().count == 1)

        _ = await monitor.replaceVendorIncidents(scope: [id], with: [])

        #expect(await monitor.rows().isEmpty)
    }

    @Test func aDiscardedImportChangesNothing() async throws {
        let tree = try Tree()
        let (monitor, _) = tree.monitor(into: Delivered())
        let day = try #require(UTCDay(iso: "2026-11-01"))
        let id = IncidentID(agent: nil, session: nil, kind: .unexplainedVendorUsage, anchor: "openai|2026-11-01|k")
        let at = tree.clock.now
        let incident = Incident(
            id: id, kind: .unexplainedVendorUsage, agent: nil, evidence: .vendorFile, at: at, completedAt: at,
            posture: .unknown, detail: .vendorExcess(VendorExcess(provider: .openai, day: day, vendorTokens: 9, localTokens: 1)))

        let applied = await monitor.replaceVendorIncidents(scope: [id], with: [incident], isCurrent: { false })

        #expect(!applied)
        #expect(await monitor.rows().isEmpty)
    }

    @Test func onlyTheFirstWriteAfterAnAnswerNotifies() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [outside(-100)])
        let sink = Delivered()
        let (monitor, store) = tree.monitor(into: sink)
        await monitor.poll()
        await store.set(.expected(at: tree.clock.now), for: await monitor.rows()[0].incident.id)

        tree.clock.advance(30)
        try tree.append("a.jsonl", outside(20))
        await monitor.poll()
        tree.clock.advance(30)
        try tree.append("a.jsonl", outside(50))
        await monitor.poll()

        #expect(sink.all.count == 1)
    }

    @Test func anAnswerGivenWhileABatchWaitsSettlesIt() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("a", after: -100)])
        let sink = Delivered()
        let (monitor, store) = tree.monitor(into: sink, interval: 60)
        await monitor.poll()
        tree.clock.advance(5)
        try tree.append("a.jsonl", line("b", after: 3))
        await monitor.poll()
        #expect(sink.all.count == 1)

        tree.clock.advance(10)
        try tree.append("a.jsonl", line("c", after: 12))
        await monitor.poll()
        let waiting = try #require(await monitor.rows().first?.incident.id)
        tree.clock.advance(1)
        await store.set(.resolved(at: tree.clock.now), for: waiting)

        tree.clock.advance(60)
        await monitor.poll()

        #expect(sink.all.count == 1)
    }

    @Test func anUnansweredItemInTheSameBatchIsStillDelivered() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("a", after: -100)])
        let sink = Delivered()
        let (monitor, store) = tree.monitor(into: sink, interval: 60)
        await monitor.poll()
        tree.clock.advance(5)
        try tree.append("a.jsonl", line("b", after: 3))
        await monitor.poll()
        #expect(sink.all.count == 1)

        tree.clock.advance(10)
        try tree.append("a.jsonl", line("c", after: 12))
        try tree.append("a.jsonl", line("d", after: 13))
        await monitor.poll()
        let waiting = await monitor.rows().prefix(2).map(\.incident.id)
        tree.clock.advance(1)
        await store.set(.resolved(at: tree.clock.now), for: waiting[0])

        tree.clock.advance(60)
        await monitor.poll()

        #expect(sink.all.count == 2)
        #expect(sink.all.last?.body == "1 item to review.")
    }

    @Test func aFileThatShrinksPastAPartialLineIsReadFromTheStart() async throws {
        let tree = try Tree()
        let first = line("aaaa", after: -100)
        try Data((first + "\n" + String(repeating: "p", count: 400)).utf8).write(to: tree.url("a.jsonl"))
        let (monitor, _) = tree.monitor(into: Delivered())
        await monitor.poll()
        let before = await monitor.rows().map(\.incident.id)

        tree.clock.advance(30)
        let rewritten = line("bbbb", after: -100)
        try Data((rewritten + "\n" + String(repeating: "p", count: 200)).utf8).write(to: tree.url("a.jsonl"))
        try FileManager.default.setAttributes([.modificationDate: tree.clock.now], ofItemAtPath: tree.url("a.jsonl").path)
        await monitor.poll()

        let after = await monitor.rows().map(\.incident.id)
        #expect(after.count == 1)
        #expect(after != before)
    }

    @Test func rowsSortNewestCompletedFirst() async throws {
        let tree = try Tree()
        try tree.write("a.jsonl", [line("older", after: -200), line("newer", after: -100)])
        let (monitor, _) = tree.monitor(into: Delivered())
        await monitor.poll()

        let dates = await monitor.rows().map(\.incident.completedAt.timeIntervalSince1970)

        #expect(dates == [Self.launch - 100, Self.launch - 200])
    }
}

@Suite struct IncidentStoreTests {
    private func scratch() -> URL {
        testScratchDirectory().appendingPathComponent(UUID().uuidString).appendingPathComponent("incidents.json")
    }

    @Test func answersAndWatermarkSurviveReload() async throws {
        let url = scratch()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = IncidentID(hex: "abc")
        let stamp = Date()
        let store = IncidentStore(url: url, now: { stamp })
        await store.set(.expected(at: stamp), for: id)
        await store.commit(watermark: Date(timeIntervalSince1970: 1_800_000_000.25))

        let reloaded = IncidentStore(url: url, now: { stamp })

        #expect(await reloaded.dispositions()[id] == .expected(at: stamp))
        #expect(await reloaded.watermark() == Date(timeIntervalSince1970: 1_800_000_000.25))
    }

    @Test func aWindowWriteAndAMonitorCommitCannotDropEachOther() async throws {
        let url = scratch()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let stamp = Date()
        let store = IncidentStore(url: url, now: { stamp })

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask { await store.set(.resolved(at: stamp), for: IncidentID(hex: "id\(index)")) }
                group.addTask { await store.commit(watermark: stamp.addingTimeInterval(Double(index))) }
            }
        }

        let reloaded = IncidentStore(url: url, now: { stamp })
        #expect(await reloaded.dispositions().count == 50)
        #expect(await reloaded.watermark() == stamp.addingTimeInterval(49))
    }

    @Test func reopenRemovesTheAnswer() async throws {
        let url = scratch()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = IncidentID(hex: "abc")
        let stamp = Date()
        let store = IncidentStore(url: url, now: { stamp })
        await store.set(.resolved(at: stamp), for: id)

        await store.set(.open, for: id)

        #expect(await store.dispositions()[id] == nil)
    }

    @Test func aReadOnlyStoreNeverTouchesACorruptFile() async throws {
        let url = scratch()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)

        let store = IncidentStore(url: url, readOnly: true)
        #expect(!store.wasReset)
        await store.set(.resolved(at: Date()), for: IncidentID(hex: "abc"))

        #expect(try String(contentsOf: url, encoding: .utf8) == "{not json")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["incidents.json"])
    }

    @Test func aCorruptFileIsKeptAsideAndReported() async throws {
        let url = scratch()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)

        let store = IncidentStore(url: url, now: { Date(timeIntervalSince1970: 1_800_000_000) })

        #expect(store.wasReset)
        #expect(await store.dispositions().isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.contains("incidents.corrupt-1800000000.json"))
    }

    @Test func answersOlderThanNinetyDaysArePrunedOnSave() async throws {
        let url = scratch()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let store = IncidentStore(url: url, now: { stamp })
        await store.set(.resolved(at: stamp.addingTimeInterval(-91 * 86_400)), for: IncidentID(hex: "old"))
        await store.set(.resolved(at: stamp.addingTimeInterval(-89 * 86_400)), for: IncidentID(hex: "kept"))

        let kept = await store.dispositions().keys.map(\.hex)

        #expect(kept == ["kept"])
    }
}
