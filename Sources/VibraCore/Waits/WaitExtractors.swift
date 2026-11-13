import Foundation

// Folds one transcript into its human waits, for `--wait-stats`.
//
// Each extractor composes the History extractor of its agent and feeds it one
// line at a time, so a prompt keeps its position among the other records and
// there is exactly one definition of "the human typed" (the History rule).
// A record is a dispatch prompt when the History extractor turned it into a
// question whose text satisfies `isFleetDispatch`, or (Codex) when it arrives
// inside an automation turn; otherwise it is a human prompt. Only a record that
// yields no History record at all can be a human command (a slash command or a
// `!` shell run).
//
// Nothing here keeps prompt text: a line's text is searched for one of those
// shapes and then dropped. The output types carry times only.

/// One pending `tool_use` block: when it first appeared and the tool's name.
private struct ToolUse {
    let at: EpochMs
    let name: String
}

/// The wait state both agents share. `openResponse` and `uses` are only ever
/// set by Claude Code records; Codex has no per-response or tool-use ids.
private struct WaitState {
    var waits: [HumanWait] = []
    var humanEvents: [EpochMs] = []
    var hasHumanPrompt = false

    /// Start of the turn wait still open, and the `message.id` of the response
    /// that opened it (Claude Code writes one record per content block).
    var open: EpochMs?
    var openResponse: String?

    /// A fleet dispatch owns the current turn: its end is a delivered result,
    /// not a question. Only turn waits are suppressed by it.
    var dispatched = false

    /// Pending tool uses, by `tool_use` id, with the time of their FIRST
    /// appearance.
    var uses: [String: ToolUse] = [:]
    /// Every `tool_use` id seen in this transcript. Kept apart from `uses` so a
    /// repeated id is not re-added after its result consumed it.
    var seenUses: Set<String> = []

    /// A human prompt or a human command: closes any open turn wait, re-arms
    /// the turn, and is itself a human event.
    mutating func humanEvent(at time: EpochMs, isPrompt: Bool) {
        if let open {
            waits.append(HumanWait(kind: .turn, start: open, end: time))
        }
        open = nil
        openResponse = nil
        dispatched = false
        humanEvents.append(time)
        if isPrompt { hasHumanPrompt = true }
    }

    /// A fleet planner wrote this prompt, so this turn is not the person's.
    mutating func dispatch() {
        open = nil
        openResponse = nil
        dispatched = true
    }

    mutating func registerToolUse(id: String, name: String, at time: EpochMs) {
        guard !seenUses.contains(id) else { return }
        seenUses.insert(id)
        uses[id] = ToolUse(at: time, name: name)
    }

    /// The pending use for `id`, consumed once: a repeated result for the same
    /// id finds nothing.
    mutating func consumeToolUse(_ id: String) -> ToolUse? {
        uses.removeValue(forKey: id)
    }

    /// A source is eligible only with at least one human prompt anywhere; an
    /// ineligible one contributes nothing, whatever commands or dialogs it
    /// holds.
    func finish() -> WaitFold {
        guard hasHumanPrompt else { return WaitFold() }
        return WaitFold(
            waits: waits, humanEvents: humanEvents, hasHumanPrompt: hasHumanPrompt, openSince: open)
    }
}

/// The answer a tool result carries, from the record's top-level
/// `permissionDecision.decision`.
private func waitAnswer(_ record: [String: Any]) -> WaitAnswer {
    let decision = (record["permissionDecision"] as? [String: Any])?["decision"] as? String
    switch decision {
    case "accept": return .accept
    case "reject": return .reject
    default: return .unknown
    }
}

/// The record's text as a human command: a slash command (either form Claude
/// Code writes: `<command-name>` first, or `<command-message>` first with a
/// `<command-name>` element after it) or a `!` shell run.
private func isClaudeHumanCommand(_ content: Any?) -> Bool {
    let raw: String?
    switch content {
    case let text as String:
        raw = text
    case let blocks as [[String: Any]]:
        raw = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
    default:
        raw = nil
    }
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
    if trimmed.hasPrefix("<bash-input>") { return true }
    guard trimmed.hasPrefix("<command-name>") || trimmed.hasPrefix("<command-message>"),
          let opening = trimmed.range(of: "<command-name>")
    else { return false }
    return trimmed.range(of: "</command-name>", range: opening.upperBound..<trimmed.endIndex) != nil
}

/// A Codex user message with an `input_text` block that is exactly one
/// `<user_shell_command>` element: the person ran a command, not asked a
/// question. Codex can send it beside an injected context block.
private func isCodexHumanCommand(_ payload: [String: Any]) -> Bool {
    guard let blocks = payload["content"] as? [[String: Any]] else { return false }
    return blocks.contains { block in
        block["type"] as? String == "input_text"
            && (block["text"] as? String).map { isInjectedWrapper($0, tags: ["user_shell_command"]) } == true
    }
}

// MARK: - Claude Code

/// Claude Code waits: turn waits closed by a human prompt or command, question
/// and approval waits closed by a `tool_result`.
///
/// A turn opens at a response's `end_turn` block and is cleared by the next
/// record that shows the agent working again. `isSidechain`, `isMeta` and
/// timestamp-less records change no wait state; the History extractor still
/// sees them, so "the human typed" stays one rule.
public struct ClaudeWaitExtractor: WaitExtractor {
    private var history = ClaudeHistoryExtractor()
    private var state = WaitState()

    public init() {}

    public mutating func fold(_ lines: [String]) {
        for line in lines {
            guard let record = jsonObject(line) else { continue }
            // One line at a time, so a prompt keeps its position.
            let prompts = history.fold([line])
            guard let time = (record["timestamp"] as? String).flatMap(epochMs(fromTimestamp:)) else {
                continue
            }
            if record["isMeta"] as? Bool == true || record["isSidechain"] as? Bool == true { continue }

            switch record["type"] as? String {
            case "assistant":
                foldAssistant(record, at: time)
            case "user":
                guard let message = record["message"] as? [String: Any] else { continue }
                if let blocks = message["content"] as? [[String: Any]],
                   blocks.contains(where: { $0["type"] as? String == "tool_result" }) {
                    foldToolResults(blocks, record: record, at: time)
                    continue
                }
                if let prompt = prompts.first {
                    if isFleetDispatch(prompt.text) {
                        state.dispatch()
                    } else {
                        state.humanEvent(at: time, isPrompt: true)
                    }
                } else if isClaudeHumanCommand(message["content"]) {
                    state.humanEvent(at: time, isPrompt: false)
                }
            default:
                break
            }
        }
    }

    public func finish() -> WaitFold { state.finish() }

    private mutating func foldAssistant(_ record: [String: Any], at time: EpochMs) {
        let message = record["message"] as? [String: Any] ?? [:]
        let responseID = message["id"] as? String
        let endedTurn = message["stop_reason"] as? String == "end_turn"

        if let responseID, responseID == state.openResponse {
            // A later record of the same response: the turn ends at its last
            // `end_turn` block.
            if endedTurn { state.open = time }
        } else if endedTurn && !state.dispatched {
            state.open = time
            state.openResponse = responseID
        } else {
            state.open = nil
            state.openResponse = nil
        }

        for block in (message["content"] as? [[String: Any]]) ?? []
        where block["type"] as? String == "tool_use" {
            guard let id = block["id"] as? String else { continue }
            state.registerToolUse(id: id, name: block["name"] as? String ?? "", at: time)
        }
    }

    private mutating func foldToolResults(
        _ blocks: [[String: Any]], record: [String: Any], at time: EpochMs
    ) {
        let answer = waitAnswer(record)
        let byHuman = ((record["permissionDecision"] as? [String: Any])?["source"] as? String)?
            .hasPrefix("user") == true
        for block in blocks where block["type"] as? String == "tool_result" {
            guard let id = block["tool_use_id"] as? String,
                  let use = state.consumeToolUse(id)
            else { continue }
            if use.name == "AskUserQuestion" {
                state.waits.append(
                    HumanWait(kind: .question, start: use.at, end: time, answer: answer))
            } else if byHuman {
                state.waits.append(
                    HumanWait(kind: .approval, start: use.at, end: time, answer: answer))
            }
        }
    }
}

// MARK: - Codex

/// Codex waits: turn waits only. Codex records no approval prompts, and
/// `request_user_input_async` does not block the turn.
///
/// `automation` covers one turn, from its `task_started` to its `task_complete`
/// or `turn_aborted`; every History record inside it is a dispatch prompt. A
/// `codex exec` or subagent session yields no History record at all, so it
/// holds no human prompt and its fold is empty.
public struct CodexWaitExtractor: WaitExtractor {
    private var history = CodexHistoryExtractor()
    private var state = WaitState()
    private var automation = false

    public init() {}

    public mutating func fold(_ lines: [String]) {
        for line in lines {
            guard let record = jsonObject(line),
                  let payload = record["payload"] as? [String: Any]
            else { continue }
            let prompts = history.fold([line])
            guard let time = (record["timestamp"] as? String).flatMap(epochMs(fromTimestamp:)) else {
                continue
            }

            if record["type"] as? String == "event_msg" {
                foldEvent(payload, at: time)
                continue
            }
            guard record["type"] as? String == "response_item" else { continue }
            let type = payload["type"] as? String
            if type == "function_call" || type == "custom_tool_call" || type == "reasoning"
                || (type == "message" && payload["role"] as? String == "assistant") {
                // The agent worked without a human prompt.
                state.open = nil
                continue
            }
            guard type == "message", payload["role"] as? String == "user" else { continue }

            if let prompt = prompts.first {
                if automation || isFleetDispatch(prompt.text) {
                    state.dispatch()
                } else {
                    state.humanEvent(at: time, isPrompt: true)
                }
            } else if !automation, isCodexHumanCommand(payload) {
                state.humanEvent(at: time, isPrompt: false)
            }
        }
    }

    public func finish() -> WaitFold { state.finish() }

    private mutating func foldEvent(_ payload: [String: Any], at time: EpochMs) {
        switch payload["type"] as? String {
        case "task_started":
            automation = codexTurnIsAutomation(payload)
            if automation { state.dispatch() }
        case "task_complete":
            if !state.dispatched { state.open = time }
            automation = false
        case "turn_aborted":
            state.open = nil
            automation = false
        default:
            break
        }
    }
}
