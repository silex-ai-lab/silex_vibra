# VS Code (Copilot Chat)

Vibra reads GitHub Copilot Chat sessions (Ask, Edit and Agent mode) from VS Code and VS Code Insiders and shows working, your turn, needs approval and idle from VS Code's own per-reply state.

### Visual Studio Code

Vibra covers VS Code in two ways:

- **Copilot Chat sessions** appear under their own **VS Code** heading. VS Code
  records each reply's state itself, so nothing is guessed from timing: a reply
  in progress is 🔵 working, a tool call or terminal command waiting for you to
  click **Allow** is 🔴 needs approval, and a finished reply is 🟠 your turn. A
  cancelled reply is ⚪️ idle. The row is named by the chat's title when it has
  one, else by the folder the window has open. Chats you opened but never sent
  anything in are left out, as VS Code's own session list does.
- **Claude Code and Codex running inside VS Code** (their VS Code extensions)
  are listed under Claude Code and Codex as usual, since they write the same
  session files as their CLIs.

Clicking a Copilot chat focuses the VS Code window that has the chat's folder
open (VS Code has no link to a single chat, so select it in the Chat view from
there). A chat in an empty window just brings VS Code forward. Clicking a
Claude Code or Codex session running in the extension brings VS Code forward
too. Vibra never launches VS Code: if it is closed, nothing is on screen to
jump to. Stable and Insiders are both read, and a click opens the edition the
chat belongs to.

**Quitting VS Code stops a pending reply** (it asks first), but VS Code leaves
the chat's log saying "in progress" or "waiting for confirmation", and does not
correct it when relaunched. Vibra therefore treats a working or blocked VS Code
chat as idle when VS Code is not running, or when nothing has happened in the
chat since VS Code last launched: a reply can only be live inside the VS Code
process that started it.

Tested live against VS Code 1.135: working, needs approval, your turn, a reply
stopped by quitting, and click-to-focus. VS Code has changed this file format before (older
releases kept each chat as one `.json` file), so a future release may need an
adapter update. The adapter only reads `.jsonl` logs, so the older format is
ignored rather than misread.

## What Vibra reads

`~/Library/Application Support/Code/User/workspaceStorage/<id>/chatSessions/*.jsonl` and `…/globalStorage/emptyWindowChatSessions/*.jsonl` (also `Code - Insiders`)

Vibra replays each chat's mutation log onto a reduced state (title, folder, and
per request its timestamps, model, token counts and `modelState`) and discards
every message and response body as it parses. It never writes to these files —
see [../privacy.md](../privacy.md).

## States shown

- 🔵 **working** — can show, from `modelState.value == 0` (a reply in progress;
  `.producing`).
- 🟠 **your turn** — can show, from `modelState.value == 1` or `3` (`.turnComplete`).
- 🔴 **needs approval** — can show, from `modelState.value == 4` (waiting on a
  confirmation; `.permissionPrompt`).
- 🟡 **stalled** — can show, while VS Code runs, from `.producing` that went quiet
  past the stall threshold (`StateEngine`).
- ⚪️ **idle** — can show, from `modelState.value == 2` (`.settled`) or a working /
  blocked / stalled reply whose editor has quit (`Session.settlingOrphaned`).

## Verified vs. unverified

| State | Status | Evidence |
|---|---|---|
| working | observed live | [README@d40c4fb:74](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L74) ("Tested live against VS Code 1.135: working…"); `VSCodeAdapterTests.replaysTheLogOntoStateFromModelState` |
| your turn | observed live | [README@d40c4fb:74](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L74) ("… your turn …"); `VSCodeAdapterTests.replaysTheLogOntoStateFromModelState` |
| needs approval | observed live | [README@d40c4fb:74](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L74) ("… needs approval …"); `VSCodeAdapterTests.replaysTheLogOntoStateFromModelState` |
| stalled | fixture-tested | `LivePipelineTests.classificationUsesThePassedStallThreshold` (`SettingsAndPipelineTests.swift`) (`.producing` quiet → stalled); shown only while VS Code runs (`EditorOrphanTests`) |
| idle | observed live | [README@d40c4fb:74](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L74) ("… a reply stopped by quitting"); `VSCodeAdapterTests.replaysTheLogOntoStateFromModelState` (`.settled`) |

## Limits

- **VS Code token counts are not a cost.** Copilot is billed per seat or by
  premium requests, not per token, and its model ids have no published rate,
  so a Copilot session shows its tokens and `n/a` for cost.

Clicking a Copilot chat focuses the VS Code window (VS Code has no link to a
single chat). See [../troubleshooting.md](../troubleshooting.md).

## Check it yourself

From the cloned repo:

```sh
make probe
```

Or ask the installed app, filtered to VS Code:

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --query --agent vsCode
```
