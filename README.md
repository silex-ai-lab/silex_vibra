# Vibra

A status companion for AI coding agents on macOS. It tells you which of your
agent sessions are working, which are waiting on *you*, and what they have cost
so far — from the menu bar, without switching to a terminal to find out.

Open source (MIT), local-only, no account, no telemetry, no network egress.

```
Vibra 2▶ 1!
─────────────────────────
Claude Code
  🔵 vibra · working · 41k tok
  🟠 jayskills · your turn · 12k tok
Codex
  🔵 silex_poc · working · 8k tok
OpenCode
  ⚪️ scratchpad · idle · 10k tok
VS Code
  🔴 Fix the login flow · needs approval · 3k tok
```

## Why

Agents work for minutes at a time. The expensive failure isn't a crash — it's an
agent that finished four minutes ago and has been waiting for you ever since,
in a terminal tab you aren't looking at. Vibra watches the session files the
agents already write and surfaces the one that needs you.

## Supported agents

| Agent | Source it reads |
|---|---|
| Claude Code (CLI, Claude desktop app, VS Code / Cursor extension) | `~/.claude/projects/<slug>/<uuid>.jsonl` |
| Codex (CLI, `codex exec`, desktop app, IDE extension) | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` |
| OpenCode (incl. DeepSeek) | `~/.local/share/opencode/opencode.db` |
| Cursor agents and chats | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` |
| Visual Studio Code — GitHub Copilot Chat (Ask, Edit, Agent mode) | `~/Library/Application Support/Code/User/workspaceStorage/<id>/chatSessions/*.jsonl` and `…/globalStorage/emptyWindowChatSessions/*.jsonl` (also `Code - Insiders`) |

Vibra never asks these tools to change what they write. It is a passive reader
of files that already exist.

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

**It installs nothing into your agents** — no hooks, no plugins, no statusline,
no wrapper binaries. Uninstalling Vibra is deleting one `.app`.

## Session states

| State | Meaning |
|---|---|
| 🔵 working | Producing output. Leave it alone. |
| 🟠 your turn | Finished its turn; waiting on you. |
| 🔴 needs approval | Sitting on a permission prompt. |
| 🟡 stalled | Claimed to be mid-turn, then went silent. |
| ⚪️ idle | Settled, nothing pending. |

`stalled` exists because an agent that died mid-turn looks identical to a busy
one if you only ask "is it running?".

### Notification lifecycle

A "your turn" notification is only posted on the *transition* into 🟠 or 🔴,
debounced per session so state flicker cannot produce a burst — and it is
**withdrawn as soon as it stops being true**: when you answer the session and it
goes back to work, when the session disappears, and when Vibra quits. Each
session's notification is keyed by its session id, so one session that keeps
wanting you replaces its own entry rather than stacking new ones.

That matters because the alternative is what Vibra used to do: banners
accumulated in Notification Center for the whole login session, all of them
about prompts that had long since been answered.

## Install

Requires **macOS 14+** and a Swift 6 toolchain. **Xcode is not required** —
Command Line Tools is enough:

```sh
xcode-select --install     # skip if `swift --version` already works
```

Then:

```sh
git clone https://github.com/silex-ai-lab/silex_vibra.git
cd silex_vibra
make install               # builds, then copies to /Applications
open /Applications/Vibra.app
```

`make install` quits any running copy first, so it is safe to re-run after
pulling changes.

There is no Dock icon and no window — `LSUIElement` is set, so **the menu bar
item is the entire app**. Look at the right-hand side of your menu bar for
`Vibra`, or a count like `2▶ 1!` when sessions are live.

To remove it completely:

```sh
make uninstall
```

### First launch

macOS may warn that the app is from an unidentified developer: it is ad-hoc
signed, not Developer ID signed. Right-click the app in Finder and choose
**Open** once, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Vibra.app
```

## Test run

The fastest way to confirm it works, without touching the menu bar at all:

```sh
make probe
```

That runs every adapter once against your real session files and prints what it
found, then exits. Expect something like:

```
Claude Code: available=true sessions=2
  - my-project [working] ev=producing 35067076 tok $83.8576 model=claude-opus-5
  - other-repo [awaitingInput] ev=turnComplete 59601496 tok $125.9708 model=claude-opus-5
Codex: available=true sessions=1
  - my-project [stalled] ev=producing 567852 tok $0.4327 model=gpt-5.6-sol
OpenCode: available=true sessions=1
  - my-project [idle] ev=unknown 13365036 tok $0.4847 model=deepseek-v4-pro
Cursor: available=false sessions=0
VS Code: available=true sessions=1
  - my-project [blocked] ev=permissionPrompt 1840 tok n/a model=copilot/gpt-5 via=vscode
total sessions: 5
```

`probe` prints counts, project names and states. It never prints message
content. It exits `2` if it found no sessions at all, which usually means you
have not used any of the supported agents in the last 12 hours.

**To see it change live:** start a Claude Code or Codex session in another
terminal, give it a task, and run `make probe` again — that session should
appear as `working`. When it finishes and waits for you, it flips to
`awaitingInput` and the menu bar count shows `1!`. The same works for a
Copilot Chat in VS Code: send a message in Agent mode, and while it waits on
**Allow** for a terminal command, `make probe` shows it as `blocked`.

### Run the tests

```sh
make test
```

Expect `Test run with N tests in M suites passed` followed by
`OK: tests executed, canary present`.

### Development loop

```sh
make restart    # rebuild and relaunch the running copy
make probe      # check adapter output without the UI

# check whether macOS will actually deliver notifications here
/Applications/Vibra.app/Contents/MacOS/Vibra --test-notification
```

### Stable signing for development

`make install` ad-hoc signs by default, which is fine for running Vibra and not
fine for *granting it permissions*. macOS pins a TCC grant to whatever identity
the bundle has, and an ad-hoc bundle has none — so the grant is pinned to the
exact code hash instead. Measured on 2026-09-21, the Automation grant's stored
requirement was literally `fade0c00...` followed by the cdhash:

```sh
codesign -d -r- /Applications/Vibra.app
# designated => cdhash H"83ed91aa1d4e9f84a698e8731fe64c37f5410d63"
```

Any rebuild that changes a byte of the binary invalidates that, and you get
"Vibra wants to control iTerm" again. Reverting the source does **not** undo it:
a release build is not byte-reproducible once the build cache has been
disturbed, so the old hash does not come back.

Signing with a stable certificate fixes it, and does not need an Apple account
or a network connection — a self-signed code-signing certificate in your login
keychain is enough:

1. **Keychain Access → Certificate Assistant → Create a Certificate…**
   Name it `vibra local signing`, Identity Type **Self Signed Root**, Certificate
   Type **Code Signing**. (Or generate one with `openssl` and
   `security import ... -T /usr/bin/codesign`.)
2. Build with it:
   ```sh
   make install SIGN_IDENTITY="vibra local signing"
   ```
   The first build prompts for keychain access. Choose **Always Allow**, or every
   later build stops and waits for the same dialog.

The designated requirement then names the certificate rather than the binary:

```sh
codesign -d -r- /Applications/Vibra.app
# designated => identifier "ai.silexlab.vibra" and certificate root = H"f067ca2a..."
```

and permissions survive rebuilds.

#### What this costs you

**The certificate is local to one machine, and deliberately not in this repo.**
It is a private key; committing one would hand anyone who clones the repo the
ability to sign as you. So:

- `SIGN_IDENTITY` is **opt-in and per machine**. A fresh clone, a second Mac and
  CI all get ad-hoc signing and behave exactly as before — nothing in the repo
  changes because you created a certificate.
- On a second machine, either **create another certificate** with the same steps
  (its own hash, its own one-time permission approvals over there), or export
  the first as a `.p12` and import it — which moves a private key between
  machines, so only do that if you are comfortable with that trade.
- Deleting it is the whole uninstall: remove `vibra local signing` from Keychain
  Access and build without `SIGN_IDENTITY`. You are back to ad-hoc, and back to
  re-approving after rebuilds. Nothing else to undo.

**Watch the expiry.** Certificate Assistant defaults to **365 days**. When it
lapses, signing fails and — because failure is fatal — your build stops, which
is at least loud. Set a longer validity when you create it; the `openssl` route
takes `-days 3650`.

**Signing failure fails the build.** It used to be a warning, which meant a
denied keychain prompt produced a quietly ad-hoc bundle that ran fine and then
mysteriously could not hold a permission. If the identity is missing or
unusable you now get:

```
error: codesign failed. The bundle would run but could not hold any
       permission: no notifications, no terminal jump-back.
       Check that SIGN_IDENTITY=... names a code-signing
       identity: security find-identity -p codesigning
make: *** [app] Error 1
```

The build also checks what it *produced*, not just codesign's exit code: asking
for an identity and silently getting ad-hoc back is the failure that hides best,
so that fails too.

**Permissions still need approving once**, on each machine, per target app
(iTerm2 and Terminal are separate grants). The certificate does not grant
anything — it makes the approval you give outlive rebuilds.

To clear the grant and be prompted again from scratch:

```sh
tccutil reset AppleEvents ai.silexlab.vibra
```

Only useful when you want to re-test the prompt, or when a grant is stuck
against a bundle you no longer have. It removes a working permission, so it
costs you one re-approval.

This is **not** a substitute for Developer ID signing and notarization, which is
what distributing a download would need — a fresh clone is still ad-hoc, so its
notifications are refused by default and its jump-back needs a manual grant.

## Testing note

Run tests with `make test` or `swift run VibraTests` — **not** `swift test`.

On a machine without Xcode, SwiftPM builds the suite as a loadable `.xctest`
bundle it has no harness to execute. `swift test` then prints `Build complete!`,
runs **zero** tests, and exits `0`. That silent false green is worse than having
no tests, so the suite is an ordinary executable that invokes swift-testing's
entry point and returns a real exit code. `make test` additionally asserts that
a non-zero number of tests ran and that the security canary was among them.

## What the cost figures mean

Costs are computed from token counts times published per-model rates. They are
an **API-equivalent value**, not your actual bill. If you are on a subscription
(Claude Max, ChatGPT Plus/Pro) you are not charged per token and the real spend
is your flat fee — the figure tells you what that usage would have cost at API
list price, which is useful for comparison and useless as an invoice.

A model with no known published rate reports `n/a` rather than a guess.

## Privacy and safety

Vibra reads local files and sends nothing anywhere. Specifically:

- **No network egress at all.** No account, no telemetry, no update ping.
- `opencode.db` also contains `access_token`, `refresh_token` and a `credential`
  table. The adapter opens the database **read-only** (`mode=ro`), emits a
  single hard-coded `SELECT` against the `session` table with an explicit column
  list, never `SELECT *`, and verifies the schema before querying.
- A **canary test** builds a fixture database containing a sentinel token and
  asserts that string appears nowhere in the returned sessions, their JSON
  encoding, or any error description. `make test` fails if that test did not run.
- Cursor's `state.vscdb` holds its auth tokens too, so the Cursor adapter gets
  the same contract: read-only, one hard-coded `SELECT`, and the token table is
  never referenced.
- VS Code's chat logs contain the whole conversation. The adapter replays each
  log onto a reduced state (title, folder, and per request its timestamps,
  model, token counts and reply state) and discards every message and response
  body as it parses. A canary test plants a sentinel in the prompt, the response
  and the input box and asserts it appears nowhere in the returned sessions.
- Adapters never log or print raw rows.

## Troubleshooting

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
the testing note above — this is expected on a machine without Xcode.

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
- **No weekly report card.**
- **Cursor's "your turn" and "needs approval" are unverified live.** In
  testing, Cursor ran terminal commands without asking, and left its unread
  flag off for the chat selected in its window even with another app in front,
  so neither state was observed. Working and idle were verified on Cursor 3.18.
- **Cursor reports no token usage**, so its sessions show 0 tokens.
- **VS Code token counts are not a cost.** Copilot is billed per seat or by
  premium requests, not per token, and its model ids have no published rate,
  so a Copilot session shows its tokens and `n/a` for cost.
- **OpenCode blocked-state detection is unverified.** The adapter does read the
  `permission` column and maps a non-empty value to `needs approval`, but that
  transition has not yet been observed live against a real approval prompt.
- **Not signed or notarized**, so this is build-from-source only. There is no
  release download and no Homebrew cask.

## Changelog

### Unreleased

- **Visual Studio Code.** GitHub Copilot Chat sessions (Ask, Edit and Agent
  mode) from VS Code and VS Code Insiders, with working / needs approval / your
  turn read from VS Code's own per-reply state. Clicking one focuses the VS
  Code window with the chat's folder open. See
  [Visual Studio Code](#visual-studio-code).
- **Cursor.** Cursor agent and chat sessions, read from Cursor's state database
  under the same read-only contract as OpenCode's. Clicking one brings Cursor
  forward. Reads Cursor 3.18's in-flight status (`aborted`), which is the only
  sign it writes that a turn is running.
- **Editor chats stopped by quitting settle to idle.** VS Code and Cursor leave a
  stopped reply marked as pending; Vibra no longer shows it as working or
  needing approval once the editor has quit or relaunched.
- **Fixed:** clicking a VS Code chat said it had focused VS Code without doing
  so; a chat with no folder was labelled with whatever folder Vibra ran in; a
  finished Cursor reply or cancelled Copilot reply read as working for 30s.
- **Codex app and IDE sessions.** `codex exec` runs count as unattended, and a
  Codex (or Claude Code) session hosted in an app rather than a terminal — the
  Codex desktop app, or an extension in VS Code or Cursor — jumps by bringing
  that app forward.

### 0.2.0 — 2026-09-21

Four bugs, all in the parts of Vibra that talk to macOS rather than to your
agents, all found on macOS 15.7.3 and fixed. Full diagnosis and measurements in
[docs/STATUS.md](docs/STATUS.md).

- **`--test-notification` crashed** (SIGTRAP, no output) instead of reporting.
  Top-level code in `main.swift` is `@MainActor` under Swift 6 and the
  UserNotifications callbacks inherited that isolation while being invoked on a
  background queue.
- **Notifications are withdrawn when they stop being true.** They used to
  accumulate in Notification Center for the whole login, including alerts for
  prompts you had already answered. They are keyed by session id now, so one
  session replaces its own entry instead of stacking, and the alert is pulled
  when the session stops needing you, disappears, or Vibra quits.
- **Terminal jump-back works.** It never had Automation permission, because the
  bundle did not declare `NSAppleEventsUsageDescription` and so macOS never
  prompted for it. Every failure was also reported as "probably a multiplexer",
  which on a plain iTerm2 tab is wrong; the diagnosis now comes from walking the
  process ancestry, and `--locate` prints it.
- **`SIGN_IDENTITY` keeps permissions across rebuilds.** See
  [Stable signing for development](#stable-signing-for-development). Signing
  failure is now fatal rather than a warning that leaves a quietly unsigned
  bundle behind.
- `make install` removes the build copy, so `open -a Vibra` can no longer
  launch a different bundle than the one you installed.

### 0.1.0

Initial: menu bar, three adapters, state classification, usage and cost
accounting, terminal jump-back (v1), usage report.

## Status

Early, but no longer expensive. Phase 0 of [the roadmap](docs/ROADMAP.md) is
done: idle CPU went from ~97% to 0.0% and resident memory from 626 MB to
~61 MB, measured on a 488-file, 339 MB corpus.

| | before | after |
|---|---|---|
| idle CPU | ~97% | **0.0%** |
| RSS | 626 MB | **~61 MB** |
| cold start | 12.4s | **0.37s** |
| unchanged refresh | full re-parse | **0 bytes read** |

Run `make bench` to reproduce those numbers on your own corpus.

Current state is tracked in [docs/STATUS.md](docs/STATUS.md); planned work,
with the reasoning behind each decision, in [docs/ROADMAP.md](docs/ROADMAP.md).

Working against real data: the menu bar, all five adapters, state
classification, usage/cost accounting, and terminal jump-back. Not yet done:
weekly report cards, and Developer ID signing.

## License

MIT
