import Foundation
import Testing
@testable import VibraCore

/// Every rule in the plan's wait spec, on synthetic records. The expected folds
/// are written out in full: waits (kind, start, end, answer), `humanEvents`,
/// `hasHumanPrompt` and `openSince`.
struct WaitExtractorTests {
    // MARK: - Builders

    private func json(_ record: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: record), as: UTF8.self)
    }

    /// A 2026-11-12 10:MM:SS.000Z stamp: every scenario here is minutes long.
    private func at(_ minutesSeconds: String) -> String { "2026-11-12T10:\(minutesSeconds).000Z" }

    /// Epoch ms for one of those stamps, through the function the extractors
    /// read timestamps with. The literal-number test below pins that function.
    private func t(_ minutesSeconds: String) -> EpochMs {
        guard let ms = epochMs(fromTimestamp: at(minutesSeconds)) else {
            fatalError("test stamp \(at(minutesSeconds)) must parse")
        }
        return ms
    }

    private func turn(_ start: String, _ end: String) -> HumanWait {
        HumanWait(kind: .turn, start: t(start), end: t(end))
    }

    private func question(_ start: String, _ end: String, _ answer: WaitAnswer) -> HumanWait {
        HumanWait(kind: .question, start: t(start), end: t(end), answer: answer)
    }

    private func approval(_ start: String, _ end: String, _ answer: WaitAnswer) -> HumanWait {
        HumanWait(kind: .approval, start: t(start), end: t(end), answer: answer)
    }

    private func foldClaude(_ lines: [String]) -> WaitFold {
        var extractor = ClaudeWaitExtractor()
        extractor.fold(lines)
        return extractor.finish()
    }

    private func foldCodex(_ lines: [String]) -> WaitFold {
        var extractor = CodexWaitExtractor()
        extractor.fold(lines)
        return extractor.finish()
    }

    // Claude Code records

    private func text(_ text: String) -> [String: Any] { ["type": "text", "text": text] }

    private func toolUse(_ id: String, _ name: String) -> [String: Any] {
        ["type": "tool_use", "id": id, "name": name]
    }

    private func toolResult(_ id: String) -> [String: Any] {
        ["type": "tool_result", "tool_use_id": id, "content": "ok"]
    }

    private func claudeUser(_ content: Any, at stamp: String?, extra: [String: Any] = [:]) -> String {
        var record: [String: Any] = [
            "type": "user", "sessionId": "c-1", "cwd": "/Users/demo/alpha",
            "entrypoint": "cli", "message": ["role": "user", "content": content],
        ]
        if let stamp { record["timestamp"] = stamp }
        record.merge(extra) { $1 }
        return json(record)
    }

    private func claudeAssistant(
        _ blocks: [[String: Any]], stop: String, id: String, at stamp: String?
    ) -> String {
        var record: [String: Any] = [
            "type": "assistant", "sessionId": "c-1", "cwd": "/Users/demo/alpha",
            "message": ["id": id, "role": "assistant", "content": blocks, "stop_reason": stop],
        ]
        if let stamp { record["timestamp"] = stamp }
        return json(record)
    }

    // Codex records

    private func codex(_ type: String, _ payload: [String: Any], at stamp: String) -> String {
        json(["type": type, "payload": payload, "timestamp": stamp])
    }

    private func codexMeta(_ fields: [String: Any] = [:]) -> String {
        var payload: [String: Any] = [
            "session_id": "x-1", "cwd": "/Users/demo/beta", "originator": "codex-tui",
        ]
        payload.merge(fields) { $1 }
        return codex("session_meta", payload, at: at("00:00"))
    }

    private func codexUser(_ text: String, at stamp: String) -> String {
        codex("response_item", [
            "type": "message", "role": "user",
            "content": [["type": "input_text", "text": text]],
        ], at: stamp)
    }

    private func codexItem(_ payload: [String: Any], at stamp: String) -> String {
        codex("response_item", payload, at: stamp)
    }

    private func codexEvent(_ name: String, at stamp: String, extra: [String: Any] = [:]) -> String {
        var payload: [String: Any] = ["type": name]
        payload.merge(extra) { $1 }
        return codex("event_msg", payload, at: stamp)
    }

    private func taskStarted(_ trigger: String? = nil, at stamp: String) -> String {
        var payload: [String: Any] = ["type": "task_started"]
        if let trigger { payload["turn_attribution"] = ["turn_trigger": trigger] }
        return codex("event_msg", payload, at: stamp)
    }

    // MARK: - Claude Code turn waits

    @Test func turnWaitEndTurnThenPrompt() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
            claudeUser("next", at: at("02:00")),
        ])
        #expect(fold == WaitFold(
            waits: [turn("00:05", "02:00")],
            humanEvents: [t("00:00"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    /// Claude Code writes one record per content block of the same response.
    /// The response's turn ends at its LAST `end_turn` block, and a response
    /// that only starts (text, then a tool_use) opens nothing yet.
    @Test func oneResponseAsSeveralRecordsOpensOnceAtItsLastEndTurnBlock() {
        let severalEndTurns = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("first block")], stop: "end_turn", id: "m1", at: at("00:05")),
            claudeAssistant([text("second block")], stop: "end_turn", id: "m1", at: at("00:09")),
            claudeUser("answer", at: at("02:00")),
        ])
        #expect(severalEndTurns == WaitFold(
            waits: [turn("00:09", "02:00")],
            humanEvents: [t("00:00"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))

        let textThenToolUse = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("working")], stop: "tool_use", id: "m1", at: at("00:05")),
            claudeAssistant([toolUse("u1", "Bash")], stop: "end_turn", id: "m1", at: at("00:09")),
            claudeUser("answer", at: at("02:00")),
        ])
        #expect(textThenToolUse == WaitFold(
            waits: [turn("00:09", "02:00")],
            humanEvents: [t("00:00"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))

        // A later block of the same response that is NOT the turn's end does
        // not clear the wait the response already opened.
        let laterBlockWithoutEndTurn = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
            claudeAssistant([toolUse("u1", "Bash")], stop: "tool_use", id: "m1", at: at("00:09")),
            claudeUser("answer", at: at("02:00")),
        ])
        #expect(laterBlockWithoutEndTurn == WaitFold(
            waits: [turn("00:05", "02:00")],
            humanEvents: [t("00:00"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    @Test func aNewResponseIDAfterEndTurnClears() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
            claudeAssistant([text("still working")], stop: "tool_use", id: "m2", at: at("00:09")),
            claudeUser("next", at: at("02:00")),
        ])
        #expect(fold == WaitFold(
            waits: [],
            humanEvents: [t("00:00"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    @Test func wrapperOnlyUserRecordIsNotAPrompt() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
            claudeUser("<task-notification>\n<task-id>b1</task-id>\n</task-notification>", at: at("00:10")),
            claudeUser("answer", at: at("02:00")),
        ])
        #expect(fold == WaitFold(
            waits: [turn("00:05", "02:00")],
            humanEvents: [t("00:00"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    @Test func isMetaSidechainAndTimestamplessRecordsChangeNothing() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
            claudeUser("injected", at: at("00:10"), extra: ["isMeta": true]),
            claudeUser("a subagent's prompt", at: at("00:20"), extra: ["isSidechain": true]),
            claudeUser("no stamp at all", at: nil),
            claudeAssistant([text("no stamp")], stop: "end_turn", id: "m2", at: nil),
            claudeUser("answer", at: at("02:00")),
        ])
        #expect(fold == WaitFold(
            waits: [turn("00:05", "02:00")],
            humanEvents: [t("00:00"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    /// The ms come from the timestamp string with integer arithmetic: the first
    /// three fraction digits (right-padded, the rest dropped) and the offset.
    @Test func recordTimesComeFromTheTimestampString() {
        var extractor = ClaudeWaitExtractor()
        extractor.fold([
            claudeUser("hello", at: "2026-11-12T10:00:00.5Z"),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1",
                            at: "2026-11-12T10:00:05.123456Z"),
            claudeUser("answer", at: "2026-11-12T12:02:00+02:00"),
        ])
        let fold = extractor.finish()
        #expect(fold.waits == [HumanWait(
            kind: .turn, start: 1_794_477_605_123, end: 1_794_477_720_000)])
        #expect(fold.humanEvents == [1_794_477_600_500, 1_794_477_720_000])
        #expect(fold.openSince == nil)
    }

    @Test func dispatchPromptClearsAndItsTurnOpensNothing() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
            claudeUser("Dispatch task-y: read /tmp/fleet/task.txt", at: at("01:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m2", at: at("02:00")),
            claudeUser("what did you change?", at: at("03:00")),
        ])
        #expect(fold == WaitFold(
            waits: [],
            humanEvents: [t("00:00"), t("03:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    @Test func aHumanPromptAfterADispatchedTurnReArms() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
            claudeUser("Dispatch task-y: read /tmp/fleet/task.txt", at: at("01:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m2", at: at("02:00")),
            claudeUser("what did you change?", at: at("03:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m3", at: at("04:00")),
            claudeUser("and the tests?", at: at("05:00")),
        ])
        #expect(fold == WaitFold(
            waits: [turn("04:00", "05:00")],
            humanEvents: [t("00:00"), t("03:00"), t("05:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    /// A slash command in either form and a `!` run are the human acting, not
    /// asking: they close a turn wait and are not questions.
    @Test func humanCommandsCloseAWaitButAreNotPrompts() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
            claudeUser("<command-name>/model</command-name>\n<command-args></command-args>", at: at("01:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m2", at: at("02:00")),
            claudeUser("<command-message>review</command-message>\n<command-name>/review</command-name>", at: at("03:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m3", at: at("04:00")),
            claudeUser("<bash-input>git status</bash-input>", at: at("05:00")),
        ])
        #expect(fold == WaitFold(
            waits: [turn("00:05", "01:00"), turn("02:00", "03:00"), turn("04:00", "05:00")],
            humanEvents: [t("00:00"), t("01:00"), t("03:00"), t("05:00")],
            hasHumanPrompt: true,
            openSince: nil))
        // A record that only quotes a `<command-name>` element further in is no
        // command: it starts with its notification tag.
        let quoted = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
            claudeUser("<task-notification>ran <command-name>/model</command-name></task-notification>",
                       at: at("01:00")),
            claudeUser("answer", at: at("02:00")),
        ])
        #expect(quoted.waits == [turn("00:05", "02:00")])
    }

    @Test func localCommandStdoutDoesNotCloseAWait() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
            claudeUser("<local-command-stdout>ok</local-command-stdout>", at: at("00:10")),
            claudeUser("answer", at: at("02:00")),
        ])
        #expect(fold == WaitFold(
            waits: [turn("00:05", "02:00")],
            humanEvents: [t("00:00"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    /// A background notification that restarts the agent after `end_turn` does
    /// not close the wait; the wait then starts at the later `end_turn`.
    @Test func taskNotificationRestartMovesTheWaitToTheLaterEndTurn() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
            claudeUser("<task-notification>background done</task-notification>", at: at("00:10")),
            claudeAssistant([toolUse("u1", "Bash")], stop: "tool_use", id: "m2", at: at("00:15")),
            claudeAssistant([text("done again")], stop: "end_turn", id: "m3", at: at("00:20")),
            claudeUser("answer", at: at("02:00")),
        ])
        #expect(fold == WaitFold(
            waits: [turn("00:20", "02:00")],
            humanEvents: [t("00:00"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    @Test func stopSequenceAndMaxTokensOpenNoWait() {
        let fold = foldClaude([
            claudeUser("one", at: at("00:00")),
            claudeAssistant([text("cut")], stop: "stop_sequence", id: "m1", at: at("00:05")),
            claudeUser("two", at: at("01:00")),
            claudeAssistant([text("long")], stop: "max_tokens", id: "m2", at: at("01:05")),
            claudeUser("three", at: at("02:00")),
        ])
        #expect(fold == WaitFold(
            waits: [],
            humanEvents: [t("00:00"), t("01:00"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    @Test func anOpenFinalWaitIsReportedAsOpenSince() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
        ])
        #expect(fold == WaitFold(
            waits: [],
            humanEvents: [t("00:00")],
            hasHumanPrompt: true,
            openSince: t("00:05")))
    }

    // MARK: - Claude Code question and approval waits

    @Test func questionAnswersAreAcceptRejectAndUnknown() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([toolUse("a1", "AskUserQuestion")], stop: "tool_use", id: "m1", at: at("00:05")),
            claudeUser([toolResult("a1")], at: at("00:10"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
            claudeAssistant([toolUse("a2", "AskUserQuestion")], stop: "tool_use", id: "m2", at: at("00:20")),
            claudeUser([toolResult("a2")], at: at("00:30"),
                       extra: ["permissionDecision": ["decision": "reject", "source": "user"]]),
            claudeAssistant([toolUse("a3", "AskUserQuestion")], stop: "tool_use", id: "m3", at: at("00:40")),
            claudeUser([toolResult("a3")], at: at("00:50")),
        ])
        #expect(fold == WaitFold(
            waits: [
                question("00:05", "00:10", .accept),
                question("00:20", "00:30", .reject),
                question("00:40", "00:50", .unknown),
            ],
            humanEvents: [t("00:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    /// The decision is the user record's top-level `permissionDecision`; a tool
    /// the config answered is no wait at all.
    @Test func bashIsAnApprovalOnlyWhenTheHumanAnswered() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([toolUse("b1", "Bash")], stop: "tool_use", id: "m1", at: at("00:05")),
            claudeUser([toolResult("b1")], at: at("00:10"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user_temporary"]]),
            claudeAssistant([toolUse("b2", "Bash")], stop: "tool_use", id: "m2", at: at("00:20")),
            claudeUser([toolResult("b2")], at: at("00:30"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "config"]]),
        ])
        #expect(fold == WaitFold(
            waits: [approval("00:05", "00:10", .accept)],
            humanEvents: [t("00:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    @Test func twoToolUseBlocksAnsweredSeparatelyGiveTwoWaits() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant(
                [toolUse("a1", "AskUserQuestion"), toolUse("b1", "Bash")], stop: "tool_use",
                id: "m1", at: at("00:05")),
            claudeUser([toolResult("a1")], at: at("00:10"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
            claudeUser([toolResult("b1")], at: at("00:20"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
        ])
        #expect(fold == WaitFold(
            waits: [question("00:05", "00:10", .accept), approval("00:05", "00:20", .accept)],
            humanEvents: [t("00:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    /// One user record with several results handles each block in order, all
    /// with that record's one answer.
    @Test func oneRecordWithTwoResultsGivesTwoWaitsWithTheSameAnswer() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant(
                [toolUse("a1", "AskUserQuestion"), toolUse("a2", "AskUserQuestion")], stop: "tool_use",
                id: "m1", at: at("00:05")),
            claudeUser([toolResult("a1"), toolResult("a2")], at: at("00:30"),
                       extra: ["permissionDecision": ["decision": "reject", "source": "user"]]),
        ])
        #expect(fold == WaitFold(
            waits: [question("00:05", "00:30", .reject), question("00:05", "00:30", .reject)],
            humanEvents: [t("00:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    /// The first appearance of an id wins, also while its use is still pending.
    @Test func aRepeatedToolUseIDKeepsItsFirstTime() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([toolUse("a1", "AskUserQuestion")], stop: "tool_use", id: "m1", at: at("00:05")),
            claudeAssistant([toolUse("a1", "AskUserQuestion")], stop: "tool_use", id: "m2", at: at("00:20")),
            claudeUser([toolResult("a1")], at: at("00:30"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
        ])
        #expect(fold == WaitFold(
            waits: [question("00:05", "00:30", .accept)],
            humanEvents: [t("00:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    /// An id repeated after its result consumed it is not re-added, so a second
    /// result yields nothing.
    @Test func anIDRepeatedAfterConsumptionYieldsOneWait() {
        let fold = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([toolUse("a1", "AskUserQuestion")], stop: "tool_use", id: "m1", at: at("00:05")),
            claudeUser([toolResult("a1")], at: at("00:10"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
            claudeAssistant([toolUse("a1", "AskUserQuestion")], stop: "tool_use", id: "m2", at: at("00:20")),
            claudeUser([toolResult("a1")], at: at("00:30"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
        ])
        #expect(fold == WaitFold(
            waits: [question("00:05", "00:10", .accept)],
            humanEvents: [t("00:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    @Test func aDuplicateResultAndAnUnknownIDGiveNothing() {
        let duplicate = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeAssistant([toolUse("a1", "AskUserQuestion")], stop: "tool_use", id: "m1", at: at("00:05")),
            claudeUser([toolResult("a1")], at: at("00:10"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
            claudeUser([toolResult("a1")], at: at("00:20"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
        ])
        #expect(duplicate == WaitFold(
            waits: [question("00:05", "00:10", .accept)],
            humanEvents: [t("00:00")],
            hasHumanPrompt: true,
            openSince: nil))

        let unknown = foldClaude([
            claudeUser("hello", at: at("00:00")),
            claudeUser([toolResult("never-seen")], at: at("00:10"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
        ])
        #expect(unknown == WaitFold(
            waits: [], humanEvents: [t("00:00")], hasHumanPrompt: true, openSince: nil))
    }

    /// A fleet seat's dialogs block until a person answers them, so they count
    /// even though the turn itself is the planner's.
    @Test func dialogsInsideADispatchedTurnStillCount() {
        let fold = foldClaude([
            claudeUser("Dispatch task-z: read /tmp/fleet/z.txt", at: at("00:00")),
            claudeAssistant([toolUse("a1", "AskUserQuestion")], stop: "tool_use", id: "m1", at: at("00:05")),
            claudeUser([toolResult("a1")], at: at("00:30"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
            claudeAssistant([toolUse("b1", "Bash")], stop: "tool_use", id: "m2", at: at("00:40")),
            claudeUser([toolResult("b1")], at: at("00:50"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
            claudeUser("thanks", at: at("01:00")),
        ])
        #expect(fold == WaitFold(
            waits: [question("00:05", "00:30", .accept), approval("00:40", "00:50", .accept)],
            humanEvents: [t("01:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    /// A transcript that holds no human prompt contributes nothing, whatever
    /// its dialogs were.
    @Test func aSourceWithoutAHumanPromptFoldsEmpty() {
        let dispatchOnlyWithDialog = foldClaude([
            claudeUser("Dispatch task-y: read /tmp/fleet/task.txt", at: at("00:00")),
            claudeAssistant([toolUse("a1", "AskUserQuestion")], stop: "tool_use", id: "m1", at: at("00:05")),
            claudeUser([toolResult("a1")], at: at("00:30"),
                       extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
            claudeAssistant([text("done")], stop: "end_turn", id: "m2", at: at("00:35")),
        ])
        #expect(dispatchOnlyWithDialog == WaitFold())

        let wrappersOnly = foldClaude([
            claudeUser("<task-notification>background done</task-notification>", at: at("00:00")),
            claudeAssistant([text("done")], stop: "end_turn", id: "m1", at: at("00:05")),
        ])
        #expect(wrappersOnly == WaitFold())
    }

    // MARK: - Codex turn waits

    @Test func codexTaskCompleteThenPrompt() {
        let fold = foldCodex([
            codexMeta(),
            codexUser("fix the build", at: at("00:00")),
            codexEvent("task_complete", at: at("00:05")),
            codexUser("now the tests", at: at("02:00")),
        ])
        #expect(fold == WaitFold(
            waits: [turn("00:05", "02:00")],
            humanEvents: [t("00:00"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    @Test func codexTurnAbortedClears() {
        let fold = foldCodex([
            codexMeta(),
            codexUser("fix the build", at: at("00:00")),
            codexEvent("task_complete", at: at("00:05")),
            codexEvent("turn_aborted", at: at("00:10")),
            codexUser("try again", at: at("02:00")),
        ])
        #expect(fold == WaitFold(
            waits: [],
            humanEvents: [t("00:00"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    /// The agent working again without a prompt clears the wait.
    @Test func codexAgentRecordsClearTheWait() {
        let items: [[String: Any]] = [
            ["type": "function_call", "name": "shell", "arguments": "{}"],
            ["type": "custom_tool_call", "name": "apply_patch", "input": ""],
            ["type": "reasoning", "summary": []],
            ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "hi"]]],
        ]
        for item in items {
            let fold = foldCodex([
                codexMeta(),
                codexUser("fix the build", at: at("00:00")),
                codexEvent("task_complete", at: at("00:05")),
                codexItem(item, at: at("00:10")),
                codexUser("next", at: at("02:00")),
            ])
            #expect(fold == WaitFold(
                waits: [],
                humanEvents: [t("00:00"), t("02:00")],
                hasHumanPrompt: true,
                openSince: nil), "\(item["type"] ?? "")")
        }
    }

    /// `item_completed` and a person's `task_started` are not the agent working.
    @Test func codexItemCompletedAndATaskStartedDoNotClear() {
        let records: [[String]] = [
            [codexEvent("item_completed", at: at("00:10"))],
            [taskStarted(at: at("00:10"))],
            [taskStarted("realtime", at: at("00:10"))],
        ]
        for middle in records {
            let fold = foldCodex(
                [codexMeta(), codexUser("fix the build", at: at("00:00")),
                 codexEvent("task_complete", at: at("00:05"))]
                    + middle + [codexUser("next", at: at("02:00"))])
            #expect(fold == WaitFold(
                waits: [turn("00:05", "02:00")],
                humanEvents: [t("00:00"), t("02:00")],
                hasHumanPrompt: true,
                openSince: nil))
        }
    }

    @Test func codexUserShellCommandClosesAWait() {
        let fold = foldCodex([
            codexMeta(),
            codexUser("fix the build", at: at("00:00")),
            codexEvent("task_complete", at: at("00:05")),
            codexUser("<user_shell_command>\n{\"command\":\"ls\"}\n</user_shell_command>", at: at("00:10")),
            codexUser("and now?", at: at("02:00")),
        ])
        #expect(fold == WaitFold(
            waits: [turn("00:05", "00:10")],
            humanEvents: [t("00:00"), t("00:10"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    /// A Codex app automation's turn is not the person's: it clears an open
    /// wait, its prompt is no human event and its `task_complete` opens nothing.
    @Test func codexAutomationTurnClearsAndOpensNothing() {
        let fold = foldCodex([
            codexMeta(),
            codexUser("fix the build", at: at("00:00")),
            codexEvent("task_complete", at: at("00:05")),
            taskStarted("automation_heartbeat_scheduled", at: at("00:09")),
            codexUser("<heartbeat>tick</heartbeat>", at: at("00:10")),
            codexEvent("task_complete", at: at("00:20")),
        ])
        #expect(fold == WaitFold(
            waits: [],
            humanEvents: [t("00:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    @Test func codexAutomationTurnThenAHumanTurnGivesOneWait() {
        let fold = foldCodex([
            codexMeta(),
            taskStarted("automation_heartbeat_scheduled", at: at("00:00")),
            codexUser("<heartbeat>tick</heartbeat>", at: at("00:01")),
            codexEvent("task_complete", at: at("00:02")),
            taskStarted(at: at("00:03")),
            codexUser("what changed?", at: at("00:04")),
            codexEvent("task_complete", at: at("00:09")),
            codexUser("and the tests?", at: at("02:00")),
        ])
        #expect(fold == WaitFold(
            waits: [turn("00:09", "02:00")],
            humanEvents: [t("00:04"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    @Test func codexAutomationTurnEndedByAnAbortGivesOneWait() {
        let fold = foldCodex([
            codexMeta(),
            taskStarted("automation_heartbeat_scheduled", at: at("00:00")),
            codexUser("<heartbeat>tick</heartbeat>", at: at("00:01")),
            codexEvent("turn_aborted", at: at("00:02")),
            taskStarted(at: at("00:03")),
            codexUser("what changed?", at: at("00:04")),
            codexEvent("task_complete", at: at("00:09")),
            codexUser("and the tests?", at: at("02:00")),
        ])
        #expect(fold == WaitFold(
            waits: [turn("00:09", "02:00")],
            humanEvents: [t("00:04"), t("02:00")],
            hasHumanPrompt: true,
            openSince: nil))
    }

    @Test func codexExecAndSubagentSessionsFoldEmpty() {
        let metas = [
            codexMeta(["originator": "codex_exec"]),
            codexMeta(["source": ["subagent": ["other": "guardian"]]]),
            codexMeta(["source": ["subagent": ["thread_spawn": ["depth": 1]]]]),
        ]
        for meta in metas {
            let fold = foldCodex([
                meta,
                codexUser("a prompt from the parent", at: at("00:00")),
                codexEvent("task_complete", at: at("00:05")),
                codexUser("<user_shell_command>ls</user_shell_command>", at: at("00:10")),
                codexUser("another prompt", at: at("02:00")),
            ])
            #expect(fold == WaitFold(), "meta \(meta)")
        }
    }

    /// Both adapters hand out their wait extractor, so `WaitIngest` can run.
    @Test func adaptersReturnTheirExtractor() {
        let claude = ClaudeCodeAdapter(file: URL(fileURLWithPath: "/nonexistent.jsonl")).waitExtractor()
        #expect((claude as? ClaudeWaitExtractor) != nil)
        let codex = CodexAdapter(file: URL(fileURLWithPath: "/nonexistent.jsonl")).waitExtractor()
        #expect((codex as? CodexWaitExtractor) != nil)
    }
}
