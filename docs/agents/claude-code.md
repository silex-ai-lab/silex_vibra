# Claude Code

Vibra reads Claude Code transcripts and shows working, your turn, needs approval, stalled and idle from the menu bar; clicking a session jumps to its terminal tab, or brings the hosting app (Claude desktop app, VS Code, Cursor) forward.

## What Vibra reads

`~/.claude/projects/<slug>/<uuid>.jsonl` (CLI, Claude desktop app, VS Code / Cursor extension)

Vibra is a passive, read-only reader. It sums usage across the `assistant`
records, keeps the model and `stop_reason`, and reads only the scheduled-task
name from the first `user` record. **History…** additionally reads the
questions you typed, on demand and only while its window is open — see
[../features.md](../features.md). It never writes to these files — see
[../privacy.md](../privacy.md).

## States shown

- 🔵 **working** — can show, from `stop_reason: "tool_use"` (`.producing`) in the
  transcript, or from a live `busy` status (`Session.enriched`).
- 🟠 **your turn** — can show, from `stop_reason: "end_turn"` (`.turnComplete`).
- 🔴 **needs approval** — can show, from a trailing `permission-mode` record
  (`.permissionPrompt`), or from a live `waiting` status (`Session.enriched`).
- 🟡 **stalled** — can show, from `.producing` that went quiet past the stall
  threshold (`StateEngine`).
- ⚪️ **idle** — can show, from a `your turn` that decayed (older than the
  attention decay) or an unrecognised last event.

## Verified vs. unverified

| State | Status | Evidence |
|---|---|---|
| working | fixture-tested | `ClaudeDesktopTests.liveStatusOverridesTheTranscriptGuess` (`busy` → working) |
| your turn | fixture-tested | `MalformedInputTests.tornFinalLineIsIgnoredButValidRecordsSurvive` (`end_turn` → `.turnComplete`) |
| needs approval | fixture-tested | `ClaudeCodeAdapterTests.lastEventIsPermissionPrompt` (`permission-mode` → `.permissionPrompt`); `ClaudeDesktopTests.liveStatusOverridesTheTranscriptGuess` (`waiting` → blocked) |
| stalled | fixture-tested | `LivePipelineTests.classificationUsesThePassedStallThreshold` (`SettingsAndPipelineTests.swift`) (`.producing` quiet → stalled) |
| idle | not observed | reachable from a decayed turn or an unrecognised event (`StateEngine`); no live observation and no test |

## Limits

No agent-specific known limitations in the base README. See
[../troubleshooting.md](../troubleshooting.md) for the limitations that apply to
every agent (notifications, terminal jump-back, history coverage).

## Check it yourself

From the cloned repo:

```sh
make probe
```

Or ask the installed app, filtered to Claude Code:

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --query --agent claudeCode
```
