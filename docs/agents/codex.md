# Codex

Vibra reads Codex rollout logs and shows working, your turn, stalled and idle from the menu bar; Codex never reports needs approval, and clicking a session jumps to its terminal tab, or brings the hosting app (Codex desktop app, VS Code, Cursor) forward.

## What Vibra reads

`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` (CLI, `codex exec`, desktop app, IDE extension)

Vibra is a passive, read-only reader. It reads `session_meta` (id, cwd, model,
originator), `token_usage_record` (cumulative `thread_token_usage`) and the
`event_msg` payload that carries the end-of-turn signal. **History…**
additionally reads the questions you typed, on demand and only while its
window is open — see [../features.md](../features.md). It never writes to
these files — see [../privacy.md](../privacy.md).

## States shown

- 🔵 **working** — can show, from an `event_msg` payload of `task_started` or
  `item_completed` (`.producing`).
- 🟠 **your turn** — can show, from an `event_msg` payload of `task_complete`
  (`.turnComplete`).
- 🔴 **needs approval** — never, because `CodexCheckpoint` never emits
  `.permissionPrompt` (and no live-status enrichment applies to Codex).
- 🟡 **stalled** — can show, from `.producing` that went quiet past the stall
  threshold (`StateEngine`).
- ⚪️ **idle** — can show, from a `your turn` that decayed (older than the
  attention decay) or an unrecognised last event.

## Verified vs. unverified

| State | Status | Evidence |
|---|---|---|
| working | observed live | [docs/STATUS.md@d40c4fb:263-264](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/docs/STATUS.md#L263-L264) ("`working` at t+2s"); `CodexAdapterTests.trailingItemCompletedMeansStillProducing` |
| your turn | observed live | [docs/STATUS.md@d40c4fb:263-264](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/docs/STATUS.md#L263-L264) ("`awaitingInput` at t+4s"); `CodexAdapterTests.trailingTaskCompleteMeansTurnIsOver` |
| needs approval | never shown | `CodexCheckpoint.buildSession` maps only `task_complete`/`task_started`/`item_completed`/`token_count`, never `.permissionPrompt` |
| stalled | fixture-tested | `LivePipelineTests.classificationUsesThePassedStallThreshold` (`SettingsAndPipelineTests.swift`) (`.producing` quiet → stalled) |
| idle | not observed | reachable from a decayed turn or an unrecognised event (`StateEngine`); no live observation and no test |

## Limits

No agent-specific known limitations in the base README. See
[../troubleshooting.md](../troubleshooting.md) for the limitations that apply to
every agent (notifications, terminal jump-back, history coverage — including a
note that a Codex version writing prompts only as `event_msg` would show no
history).

## Check it yourself

From the cloned repo:

```sh
make probe
```

Or ask the installed app, filtered to Codex:

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --query --agent codex
```
