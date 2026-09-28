# Cursor

Vibra reads Cursor's state database and shows working and idle live, with your turn and needs approval read from Cursor's own per-session flags.

### Cursor

Cursor's agent and chat sessions (the Agents window and the editor's chat) are
read from its state database. Cursor 3.18 writes less than earlier versions:
it never marks a reply as "generating", and instead writes status `aborted`
while a turn runs and `completed` when it ends. Vibra reads `aborted` as
working. A turn you stopped is left `aborted` too, so a Cursor turn that goes
quiet for five minutes is shown as idle rather than 🟡 stalled. A reply you
have read is idle; 🟠 your turn relies on Cursor's own unread flag. The same
"editor not running" rule as VS Code applies. Clicking a Cursor session brings
Cursor forward; Cursor has no link to a single chat.

*Visual Studio*, the Windows IDE, is not supported: Vibra is macOS-only, and
Microsoft retired Visual Studio for Mac in August 2024.

## What Vibra reads

`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (Cursor agents and chats)

Vibra opens the database read-only and runs one hard-coded `SELECT`
(`CursorAdapter.sessionSelectSQL`): `composerHeaders`, left-joined to the
`cursorDiskKV` row keyed `composerData:<id>`, for non-subagent sessions. It
reads this metadata allowlist: session id, created / last-updated and
checkpoint timestamps, the chat's name, the workspace folder path, the
archived, draft, unread (`hasUnreadMessages`) and pending-approval
(`hasBlockingPendingActions`) flags, the reply `status`, and a count of
generating replies. It never reads message text and never references
`ItemTable`, which holds Cursor's auth tokens — see
[../privacy.md](../privacy.md).

## States shown

- 🔵 **working** — can show, from a reply in flight: `status: "generating"`, a
  non-empty `generatingBubbleIds`, or a `composerData` record newer than its
  header (`.producing`).
- 🟠 **your turn** — can show, from Cursor's unread flag `hasUnreadMessages`
  (`.turnComplete`).
- 🔴 **needs approval** — can show, from `hasBlockingPendingActions`
  (`.permissionPrompt`).
- 🟡 **stalled** — never (shown idle), because `Session.settlingOrphaned` turns a
  stalled Cursor session into idle.
- ⚪️ **idle** — can show, from `status: "completed"` (`.settled`), a stalled turn
  you stopped, or an unrecognised event.

## Verified vs. unverified

| State | Status | Evidence |
|---|---|---|
| working | observed live | [README@d40c4fb:542](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L542) ("Working and idle were verified on Cursor 3.18"); `CursorAdapterTests.readsSessionsWithCursorsOwnStateSignals` (`.producing`) |
| your turn | fixture-tested | `CursorAdapterTests.readsSessionsWithCursorsOwnStateSignals` (`hasUnread` → `.turnComplete`); unverified live ([README@d40c4fb:539-542](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L539-L542)) |
| needs approval | fixture-tested | `CursorAdapterTests.readsSessionsWithCursorsOwnStateSignals` (`hasBlockingActions` → `.permissionPrompt`); unverified live ([README@d40c4fb:539-542](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L539-L542)) |
| stalled | never shown | `Session.settlingOrphaned` maps Cursor `.stalled` → idle; `EditorOrphanTests.aStalledCursorTurnIsOneYouStopped` (`VSCodeAdapterTests.swift`) |
| idle | observed live | [README@d40c4fb:542](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L542); `CursorAdapterTests.aSeenReplyIsIdleNotYourTurn` (`.settled`) |

## Limits

- **Cursor's "your turn" and "needs approval" are unverified live.** In
  testing, Cursor ran terminal commands without asking, and left its unread
  flag off for the chat selected in its window even with another app in front,
  so neither state was observed. Working and idle were verified on Cursor 3.18.
- **Cursor reports no token usage**, so its sessions show 0 tokens.

Clicking a Cursor session brings Cursor forward; Cursor has no link to a single
chat (see [../troubleshooting.md](../troubleshooting.md)).

## Check it yourself

From the cloned repo:

```sh
make probe
```

Or ask the installed app, filtered to Cursor:

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --query --agent cursor
```
