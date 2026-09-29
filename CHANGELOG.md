# Changelog

## 2026-09-28.1 — Codex session navigation

- **Codex shared-server navigation.** A managed Codex background server can
  hold several session locks without owning any terminal. Those sessions now
  open their exact thread in the Codex desktop app instead of reporting
  "That session has no terminal." If the desktop link cannot be opened, or
  a session's process or controlling terminal cannot be found, the menu shows
  the selected session's history without a blocking alert. History navigation
  failures no longer overwrite the clipboard or claim the session has exited.

  Release notes: [2026-09-28.1](docs/releases/2026-09-28.1.md).

## 2026-09-28 — Documentation update

- **Docs: README restructured** around an outcome headline, a per-state
  compatibility table (observed live / can show / never) and a two-minute
  first run; under 150 lines. Detail moved, not deleted, to
  [docs/features.md](docs/features.md) (now also documenting **Usage
  Report…**, ⌘U), [docs/troubleshooting.md](docs/troubleshooting.md),
  [docs/development.md](docs/development.md), [docs/privacy.md](docs/privacy.md)
  and this file. New per-agent guides under [docs/agents/](docs/agents/).
  Removed the stale limitation that said the weekly report card was missing; reconciled
  `docs/ROADMAP.md` (VS Code live-tested) and `docs/STATUS.md` (herdr jump,
  public repo). Record:
  [plan/PLAN-2026-09-28-oss-growth-day1.md](plan/PLAN-2026-09-28-oss-growth-day1.md).

## 2026-09-27 — History and editor support

- **History window** (⌘Y): the questions you asked in Claude Code, Codex and
  Hermes, by day, searchable, with a detail pane to read a question in place
  and tab-separated copy of the visible rows, read on demand and never stored.
  The agent filter and the menu's section headers show their counts.
- **History detail, wave 2:** each question's transcript file with **Copy
  Path** / **Open** and its session id; on-demand **Tasks** and **Timeline**
  sections for Claude Code (read on selection, bounded, released on close);
  and ⌘F / ⌘⇧C / ⌘J / Esc in the window. Record:
  [PLAN-2026-09-27-history-ui.md](docs/PLAN-2026-09-27-history-ui.md).
- **Settings window** (⌘,): stall threshold, "your turn" decay and the menu's
  activity window, applied without a relaunch.
- **`--query`**: the menu's live sessions as JSON, for scripts and agents; no
  message content. Also `--history-stats` (counts only) and `--dump-sessions`
  (the menu pipeline's own rows, for diagnostics).
- **Hermes Agent** sessions from `~/.hermes/state.db`, read-only.
- **Fixed:** a write that landed only in an SQLite `-wal` file (OpenCode,
  Hermes) could go unnoticed until the 60 s safety rescan.
- Plan and review record:
  [docs/PLAN-2026-09-26-history-query-settings-hermes.md](docs/PLAN-2026-09-26-history-query-settings-hermes.md).

- **Visual Studio Code.** GitHub Copilot Chat sessions (Ask, Edit and Agent
  mode) from VS Code and VS Code Insiders, with working / needs approval / your
  turn read from VS Code's own per-reply state. Clicking one focuses the VS
  Code window with the chat's folder open. See
  [Visual Studio Code](docs/agents/vscode.md).
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

## 0.2.0 — 2026-09-21

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
  [Stable signing for development](docs/development.md#stable-signing-for-development). Signing
  failure is now fatal rather than a warning that leaves a quietly unsigned
  bundle behind.
- `make install` removes the build copy, so `open -a Vibra` can no longer
  launch a different bundle than the one you installed.

## 0.1.0

Initial: menu bar, three adapters, state classification, usage and cost
accounting, terminal jump-back (v1), usage report.
