# Troubleshooting

**Nothing appears in the menu bar.** Confirm the process is alive:

```sh
pgrep -lf "Vibra.app/Contents/MacOS/Vibra"
```

If it is running but invisible, your menu bar may be full — macOS silently drops
status items when there is no room, especially on a laptop with a notch. Quit
another menu bar app, or test on a wider display, then `make restart`.

**`open -a Vibra` launches the wrong copy.** If you built in the repo *and*
installed to `/Applications`, LaunchServices may prefer the build copy. Always
launch by full path:

```sh
pkill -f "Vibra.app/Contents/MacOS/Vibra"
open /Applications/Vibra.app
```

**Clicking a session says Vibra isn't allowed to control iTerm2/Terminal.**
That is macOS refusing the Apple Event. Grant it under System Settings →
Privacy & Security → Automation → Vibra. To see what Vibra thinks it is dealing
with before clicking anything:

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --locate
```

The `tty owner:` line reads `emulator iTerm2 - jumpable` for a normal tab and
`multiplexer tmux - not jumpable` for a pane the emulator cannot see. It comes
from walking the process ancestry, so it is a fact about your machine rather
than a guess.

**An OpenCode or Hermes row is grayed out and does nothing when clicked.**
Neither agent publishes a link between its session and its process, and a
directory does not identify a session — so there is no exact jump to make, and
Vibra will not guess at one. The row still reports the session's state and
tokens, and its tooltip says why there is no jump. Clicking a "waiting for
you" notification for such a session just clears the notification.

**Codex sessions used to say "That session has no terminal," even while open.**
Newer Codex terminal clients can share a managed background server. That server
holds the thread-writer locks but has no terminal; its PID cannot identify the
client's tab. Vibra now opens the exact thread through the Codex desktop app's
`codex://threads/<session-id>` link. This opens the conversation in the desktop
app, rather than focusing its original CLI tab. If the desktop app is unavailable,
Vibra shows that session's history instead. Missing-process and missing-window
clicks also show history without a modal alert. `--locate` reports shared-server
ownership, and `--jump` accepts a session ID to distinguish same-project sessions.

**herdr panes are jumpable.** A session in a herdr pane is traced up its
process ancestry to the herdr server; the ancestor directly below the server is
the pane's shell, which herdr reports per pane as `shell_pid`, so the pane
match is exact. Vibra then runs `herdr agent focus` (or `tab focus`) against
that same herdr session and focuses the iTerm2/Terminal tab where a herdr
client for it is attached. With no client attached anywhere there is nothing
to look at, and the jump is reported as failed. To try it on any process:

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --herdr-jump <pid>
```

**`make probe` says `total sessions: 0`.** Nothing has run in the last 12 hours.
The window is `activityWindow` in `Sources/VibraApp/SessionStore.swift`.

**`swift test` says everything passed but nothing ran.** Use `make test`. See
the [testing note](development.md#testing-note) — this is expected on a machine without Xcode.

**Old notifications pile up, or one won't go away.** Vibra removes any of its
notifications it is not currently tracking on every refresh, so leftovers from
an earlier run (a `pkill`, a crash, a reinstall) clear themselves once Vibra is
running again. A clicked notification is always removed, whether or not the
jump worked. To see what macOS still holds for Vibra (ids only, never bodies):

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --notifications
```

**Notifications never arrive.** Test it directly:

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --test-notification
```

On a fresh ad-hoc signed install this reports:

```
authorization granted: false
authorization error: Notifications are not allowed for this application
```

That is macOS refusing an unsigned bundle, not a bug in vibra. The app does
register its bundle id, so you can enable it manually:

**System Settings → Notifications → Vibra → Allow Notifications**

Then re-run the command above; it should print `RESULT: notification posted`
and show a banner. If Vibra is missing from that list, launch it once
(`open /Applications/Vibra.app`) and look again.

Everything else works without this — notifications are an optional convenience
layered on the menu bar, which is the real interface.

## Known limitations

- **Notifications are refused by default.** Confirmed on macOS 26 and macOS
  15.7.3: an ad-hoc signed bundle gets `authorization granted: false` with
  `"Notifications are not allowed for this application"`. The app still
  registers its bundle id with Notification Center, so you can enable it by
  hand — see below. The durable fix is a Developer ID signature, not a code
  change. The menu bar shows everything a notification would have said, so
  `Notifier` treats refusal as normal and never fails.
- **Terminal jump-back needs Automation permission.** Clicking a session focuses
  the iTerm2 or Terminal tab it runs in, which means asking that app which tab
  owns the session's tty — an Apple Event, so macOS gates it behind
  **System Settings → Privacy & Security → Automation → Vibra**. The first
  click prompts for it. Vibra is ad-hoc signed, so rebuilding changes its
  identity and macOS may ask again.
- **History covers Claude Code, Codex and Hermes only.** A Codex version that
  wrote prompts only as `event_msg` records would show no history; the current
  one writes them as `response_item` messages, which is what Vibra reads.
- **Not signed or notarized**, so this is build-from-source only. There is no
  release download and no Homebrew cask.
- **Per-agent limits** — which states each agent can and cannot show, and
  what has been observed live — are in the agent guides:
  [Claude Code](agents/claude-code.md), [Codex](agents/codex.md),
  [OpenCode](agents/opencode.md), [Cursor](agents/cursor.md),
  [VS Code](agents/vscode.md), [Hermes](agents/hermes.md).
