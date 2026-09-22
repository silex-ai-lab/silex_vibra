import Foundation
import Testing
@testable import VibraCore

/// VS Code's chat logs carry the whole conversation. The adapter replays them
/// onto a reduced state, so these tests check both that the replay follows VS
/// Code's own mutation semantics and that no message or response text survives.
struct VSCodeAdapterTests {

    private static let canary = "VIBRA_VSCODE_CANARY_MUST_NOT_LEAK"

    /// A fake VS Code `User` directory with one folder workspace.
    private func makeUserDirectory() throws -> (user: URL, chats: URL) {
        let user = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        let workspace = user.appendingPathComponent("workspaceStorage/abc123")
        let chats = workspace.appendingPathComponent("chatSessions")
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: user.appendingPathComponent("globalStorage/emptyWindowChatSessions"),
            withIntermediateDirectories: true)
        try #"{"folder":"file:///Users/dev/my%20app"}"#
            .write(to: workspace.appendingPathComponent("workspace.json"), atomically: true, encoding: .utf8)
        return (user, chats)
    }

    private func request(_ id: String, at ms: Int, state: Int?) -> String {
        let modelState = state.map { #","modelState":{"value":\#($0)}"# } ?? ""
        return #"{"requestId":"\#(id)","timestamp":\#(ms),"modelId":"copilot/gpt-5","message":{"text":"\#(Self.canary)"},"response":[{"value":"\#(Self.canary)"}],"promptTokens":100,"completionTokens":20\#(modelState)}"#
    }

    private func snapshot(_ id: String, requests: [String] = []) -> String {
        #"{"kind":0,"v":{"version":3,"creationDate":1790000000000,"sessionId":"\#(id)","responderUsername":"GitHub Copilot","requests":[\#(requests.joined(separator: ","))],"inputState":{"inputText":"\#(Self.canary)"}}}"#
    }

    private func write(_ lines: [String], to url: URL) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func append(_ lines: [String], to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    @Test func replaysTheLogOntoStateFromModelState() throws {
        let (user, chats) = try makeUserDirectory()
        defer { try? FileManager.default.removeItem(at: user) }
        let file = chats.appendingPathComponent("s1.jsonl")
        try write([
            snapshot("s1"),
            #"{"kind":1,"k":["responderUsername"],"v":"GitHub Copilot"}"#,
            #"{"kind":2,"k":["requests"],"v":[\#(request("r1", at: 1790000001000, state: 0))]}"#,
            #"{"kind":2,"k":["requests",0,"response"],"v":[{"value":"\#(Self.canary)"}]}"#,
        ], to: file)
        let adapter = VSCodeAdapter(userDirectories: [user])

        var session = try #require(adapter.discoverSessions().first)
        #expect(session.id == "s1")
        #expect(session.agent == .vsCode)
        #expect(session.lastEvent == .producing)
        #expect(session.cwd == "/Users/dev/my app")
        #expect(session.displayName == "my app")
        #expect(session.model == "copilot/gpt-5")
        #expect(session.usage == TokenUsage(input: 100, output: 20))
        #expect(session.entrypoint == "vscode")

        try append([#"{"kind":1,"k":["requests",0,"modelState"],"v":{"value":4}}"#], to: file)
        session = try #require(adapter.discoverSessions().first)
        #expect(session.lastEvent == .permissionPrompt)

        try append([
            #"{"kind":1,"k":["requests",0,"modelState"],"v":{"value":1,"completedAt":1790000009000}}"#,
            #"{"kind":1,"k":["customTitle"],"v":"Fix the login flow"}"#,
        ], to: file)
        session = try #require(adapter.discoverSessions().first)
        #expect(session.lastEvent == .turnComplete)
        #expect(session.displayName == "Fix the login flow")

        // Cancelling the reply settles the session rather than asking for you.
        try append([#"{"kind":1,"k":["requests",0,"modelState"],"v":{"value":2}}"#], to: file)
        #expect(try adapter.discoverSessions().first?.lastEvent == .settled)
    }

    @Test func pushTruncatesBeforeAppendingAndDeleteClears() throws {
        var checkpoint = VSCodeChatCheckpoint()
        checkpoint.fold(snapshot("s", requests: [
            request("a", at: 1, state: 1), request("b", at: 2, state: 1), request("c", at: 3, state: 1),
        ]))
        checkpoint.fold(#"{"kind":1,"k":["customTitle"],"v":"Old"}"#)
        // Editing request "b" drops it and everything after, then appends.
        checkpoint.fold(#"{"kind":2,"k":["requests"],"v":[\#(request("b2", at: 4, state: 0))],"i":1}"#)
        checkpoint.fold(#"{"kind":3,"k":["customTitle"]}"#)

        #expect(checkpoint.requests.map(\.timestampMS) == [1, 4])
        #expect(checkpoint.requests.last?.modelState == 0)
        #expect(checkpoint.customTitle == nil)

        // A fresh snapshot (VS Code compacting the log) replaces everything.
        checkpoint.fold(snapshot("s"))
        #expect(checkpoint.requests.isEmpty)
    }

    @Test func emptyChatsAndEmptyWindowsAreHandled() throws {
        let (user, chats) = try makeUserDirectory()
        defer { try? FileManager.default.removeItem(at: user) }
        // Opened but never used: VS Code does not list it, nor does Vibra.
        try write([snapshot("unused")], to: chats.appendingPathComponent("unused.jsonl"))
        try write(
            [snapshot("loose", requests: [request("r", at: 1790000001000, state: 1)])],
            to: user.appendingPathComponent("globalStorage/emptyWindowChatSessions/loose.jsonl"))

        let sessions = try VSCodeAdapter(userDirectories: [user]).discoverSessions()
        #expect(sessions.map(\.id) == ["loose"])
        #expect(sessions.first?.cwd == "")
        #expect(sessions.first?.displayName == "Copilot chat")
        #expect(sessions.first?.projectName == "(no folder)")
    }

    @Test func incrementalIngestMatchesFullParseAndSurvivesCompaction() async throws {
        let (user, chats) = try makeUserDirectory()
        defer { try? FileManager.default.removeItem(at: user) }
        let file = chats.appendingPathComponent("s1.jsonl")
        try write([snapshot("s1"), #"{"kind":2,"k":["requests"],"v":[\#(request("r1", at: 1790000001000, state: 0))]}"#], to: file)
        let adapter = VSCodeAdapter(userDirectories: [user])
        let ingest = SessionIngest(adapters: [adapter], horizon: nil)

        #expect(await ingest.refresh().first?.lastEvent == .producing)
        try append([#"{"kind":1,"k":["requests",0,"modelState"],"v":{"value":1}}"#], to: file)
        let incremental = await ingest.refresh()
        #expect(incremental == (try adapter.discoverSessions()))
        #expect(incremental.first?.lastEvent == .turnComplete)

        // Compaction rewrites the file as one shorter snapshot.
        try write([snapshot("s1", requests: [request("r1", at: 1790000001000, state: 4)])], to: file)
        #expect(await ingest.refresh().first?.lastEvent == .permissionPrompt)
    }

    @Test func conversationTextNeverSurfaces() throws {
        let (user, chats) = try makeUserDirectory()
        defer { try? FileManager.default.removeItem(at: user) }
        try write([
            snapshot("s1", requests: [request("r1", at: 1790000001000, state: 1)]),
            #"{"kind":1,"k":["requests",0,"message"],"v":{"text":"\#(Self.canary)"}}"#,
        ], to: chats.appendingPathComponent("s1.jsonl"))

        let sessions = try VSCodeAdapter(userDirectories: [user]).discoverSessions()
        #expect(sessions.count == 1)
        let encoded = String(decoding: try JSONEncoder().encode(sessions), as: UTF8.self)
        #expect(!String(describing: sessions).contains(Self.canary))
        #expect(!encoded.contains(Self.canary))
    }
}

/// A reply can only be live inside the editor process running now.
struct EditorOrphanTests {
    private func session(_ agent: AgentKind, _ state: SessionState, at seconds: Double,
                         entrypoint: String? = nil) -> Session {
        let at = Date(timeIntervalSince1970: seconds)
        return Session(id: "\(agent)-\(state)", agent: agent, cwd: "/p", state: state,
                       startedAt: at, lastActivity: at, entrypoint: entrypoint)
    }

    @Test func pendingRepliesSettleWhenTheEditorQuitOrRelaunched() {
        let vscode = "com.microsoft.VSCode"
        let blocked = session(.vsCode, .blocked, at: 100, entrypoint: "vscode")

        // Not running: VS Code stopped the reply when it quit.
        #expect(Session.settlingOrphaned([blocked], editorLaunch: [:]).first?.state == .idle)
        // Relaunched since: the log still says pending, but that process is gone.
        #expect(Session.settlingOrphaned([blocked], editorLaunch: [vscode: Date(timeIntervalSince1970: 200)])
            .first?.state == .idle)
        // Running since before the request: genuinely waiting on you.
        #expect(Session.settlingOrphaned([blocked], editorLaunch: [vscode: Date(timeIntervalSince1970: 50)])
            .first?.state == .blocked)
        // Insiders is its own app: stable VS Code running says nothing about it.
        let insiders = session(.vsCode, .working, at: 100, entrypoint: "vscode-insiders")
        #expect(Session.settlingOrphaned([insiders], editorLaunch: [vscode: Date(timeIntervalSince1970: 50)])
            .first?.state == .idle)
    }

    @Test func finishedChatsAndTerminalAgentsAreUntouched() {
        let done = session(.vsCode, .awaitingInput, at: 100, entrypoint: "vscode")
        let cursor = session(.cursor, .working, at: 100)
        let claude = session(.claudeCode, .blocked, at: 100)
        let out = Session.settlingOrphaned([done, cursor, claude], editorLaunch: [:])
        #expect(out.map(\.state) == [.awaitingInput, .idle, .blocked])
    }

    @Test func aStalledCursorTurnIsOneYouStopped() {
        let cursorID = "com.todesktop.230313mzl4w4u92"
        let launch = [cursorID: Date(timeIntervalSince1970: 50)]
        let stalled = session(.cursor, .stalled, at: 100)
        let working = session(.cursor, .working, at: 100)
        #expect(Session.settlingOrphaned([stalled, working], editorLaunch: launch).map(\.state) == [.idle, .working])
    }
}
