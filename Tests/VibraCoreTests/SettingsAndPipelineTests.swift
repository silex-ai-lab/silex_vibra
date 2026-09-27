import Foundation
import Testing
@testable import VibraCore

struct VibraSettingsTests {
    @Test func defaultsEqualTheShippedConstants() {
        let s = VibraSettings.load(from: DictionarySettingsStore())
        #expect(s == .defaults)
        #expect(s.stateEngineConfig == StateEngineConfig.default)
        #expect(s.activityWindowSeconds == 12 * 3600)
    }

    @Test func eachKeyClampsAtBothEnds() {
        let low = VibraSettings.load(from: DictionarySettingsStore([
            "stallThresholdSeconds": 1, "attentionDecaySeconds": 1, "activityWindowSeconds": 1,
        ]))
        #expect(low.stallThresholdSeconds == 60)
        #expect(low.attentionDecaySeconds == 3600)
        #expect(low.activityWindowSeconds == 3600)

        let high = VibraSettings.load(from: DictionarySettingsStore([
            "stallThresholdSeconds": 1e9, "attentionDecaySeconds": 1e9, "activityWindowSeconds": 1e9,
        ]))
        #expect(high.stallThresholdSeconds == 7200)
        #expect(high.attentionDecaySeconds == 172_800)
        #expect(high.activityWindowSeconds == 259_200)
    }

    @Test func garbageFallsBackToDefault() {
        let s = VibraSettings.load(from: DictionarySettingsStore([
            "stallThresholdSeconds": "ten minutes",
            "attentionDecaySeconds": true,
            "activityWindowSeconds": Double.nan,
        ]))
        #expect(s == .defaults)
        // A numeric string, as `defaults write` without -int writes, is a number.
        let str = VibraSettings.load(from: DictionarySettingsStore(["stallThresholdSeconds": "600"]))
        #expect(str.stallThresholdSeconds == 600)
    }

    @Test func stallCannotFallToTheWorkingWindow() {
        var s = VibraSettings.defaults
        s.stallThresholdSeconds = 1
        #expect(s.stateEngineConfig.stallThreshold > s.stateEngineConfig.workingWindow)
    }

    @Test func saveAndResetRoundTrip() {
        let store = DictionarySettingsStore()
        var s = VibraSettings.defaults
        s.stallThresholdSeconds = 900
        s.save(to: store)
        #expect(VibraSettings.load(from: store).stallThresholdSeconds == 900)
        VibraSettings.reset(in: store)
        #expect(VibraSettings.load(from: store) == .defaults)
    }

    /// The domain never depends on the process: the bare CLI and the app
    /// must read the same numbers.
    @Test func preferencesStoreUsesTheAppDomain() {
        #expect(PreferencesStore().domain == "ai.silexlab.vibra")
        #expect(PreferencesStore.domain == "ai.silexlab.vibra")

        let store = PreferencesStore(domain: "ai.silexlab.vibra.tests.\(UUID().uuidString)")
        store.set(1234.0, forKey: "stallThresholdSeconds")
        #expect(VibraSettings.load(from: store).stallThresholdSeconds == 1234)
        VibraSettings.reset(in: store)
        #expect(VibraSettings.load(from: store) == .defaults)
    }
}

struct LivePipelineTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(
        _ id: String,
        _ agent: AgentKind = .claudeCode,
        quiet: TimeInterval,
        event: LastEventKind,
        entrypoint: String? = nil
    ) -> Session {
        Session(
            id: id, agent: agent, cwd: "/Users/demo/\(id)",
            startedAt: now.addingTimeInterval(-quiet - 60),
            lastActivity: now.addingTimeInterval(-quiet),
            lastEvent: event, entrypoint: entrypoint
        )
    }

    @Test func windowFilterUsesTheSettingOrTheOverride() {
        let raw = [session("fresh", quiet: 60, event: .turnComplete), session("old", quiet: 5 * 3600, event: .turnComplete)]
        var settings = VibraSettings.defaults
        settings.activityWindowSeconds = 3600
        #expect(LivePipeline.recent(raw, settings: settings, now: now).map(\.id) == ["fresh"])
        #expect(LivePipeline.recent(raw, settings: settings, activityWindow: .infinity, now: now).map(\.id) == ["fresh", "old"])
    }

    @Test func classificationUsesThePassedStallThreshold() {
        let raw = [session("mid-turn", quiet: 90, event: .producing)]
        #expect(LivePipeline.recent(raw, settings: .defaults, now: now).first?.state == .working)
        var strict = VibraSettings.defaults
        strict.stallThresholdSeconds = 60
        #expect(LivePipeline.recent(raw, settings: strict, now: now).first?.state == .stalled)
    }

    @Test func recentSortsNewestFirst() {
        let raw = [session("b", quiet: 300, event: .turnComplete), session("a", quiet: 10, event: .turnComplete)]
        #expect(LivePipeline.recent(raw, settings: .defaults, now: now).map(\.id) == ["a", "b"])
    }

    /// `finish` is the composition `SessionStore` used inline before the
    /// refactor, applied in the same order.
    @Test func finishMatchesTheFormerInlineComposition() {
        let raw = [
            session("titled", quiet: 10, event: .turnComplete),
            session("archived", quiet: 20, event: .turnComplete),
            session("exited", .codex, quiet: 30, event: .turnComplete),
            session("alive", .codex, quiet: 40, event: .turnComplete),
            session("vscode", .vsCode, quiet: 50, event: .producing),
            session("opencode", .openCode, quiet: 60, event: .turnComplete),
        ]
        let recent = LivePipeline.recent(raw, settings: .defaults, now: now)
        let desktop = [
            "titled": DesktopSessionInfo(localID: "local_1", title: "A title", isArchived: false),
            "archived": DesktopSessionInfo(localID: "local_2", title: nil, isArchived: true),
        ]
        let claudeStatus = ["titled": ClaudeLiveStatus(status: "waiting", waitingFor: nil)]
        let live: [AgentKind: Set<String>] = [.claudeCode: ["titled"], .codex: ["alive"]]
        let editorLaunch: [String: Date] = [:]  // VS Code not running

        let finished = LivePipeline.finish(
            recent, desktop: desktop, claudeStatus: claudeStatus, live: live, editorLaunch: editorLaunch)
        let former = Session.settlingOrphaned(
            Session.withoutExited(Session.enriched(recent, desktop: desktop, live: claudeStatus), live: live),
            editorLaunch: editorLaunch
        )
        #expect(finished == former)
        #expect(finished.map(\.id) == ["titled", "alive", "vscode", "opencode"])
        #expect(finished.first?.title == "A title")
        #expect(finished.first?.state == .blocked)
        #expect(finished.first { $0.id == "vscode" }?.state == .idle)
    }
}

struct SessionIngestHorizonTests {
    @Test func wideningTheHorizonReadsOlderSources() async throws {
        let dir = testScratchDirectory().appendingPathComponent("horizon-\(UUID().uuidString)")
        let project = dir.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = project.appendingPathComponent("old.jsonl")
        try FileManager.default.copyItem(at: fixtureURL("Fixtures/claude_session.jsonl"), to: file)
        let twoDaysAgo = Date().addingTimeInterval(-48 * 3600)
        try FileManager.default.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: file.path)

        let ingest = SessionIngest(adapters: [ClaudeCodeAdapter(projectsRoot: dir)], horizon: 12 * 3600)
        #expect(await ingest.refresh().isEmpty)
        await ingest.setHorizon(72 * 3600)
        #expect(await ingest.refresh().count == 1)
    }
}

struct FileWatcherPollTests {
    @Test func aWriteOnlyToTheWALFires() throws {
        let dir = testScratchDirectory().appendingPathComponent("poll-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("x.db")
        try Data("main".utf8).write(to: db)

        let fired = PreparedSQL()
        let watcher = FileWatcher(watchedDirectories: [], pollURLs: [db]) { urls in
            for url in urls { fired.record(url.lastPathComponent) }
        }
        watcher.pollOnce(db)          // baseline
        watcher.pollOnce(db)          // unchanged
        #expect(fired.all.isEmpty)
        try Data(repeating: 7, count: 32).write(to: URL(fileURLWithPath: db.path + "-wal"))
        watcher.pollOnce(db)
        #expect(fired.all == ["x.db"])
    }
}
