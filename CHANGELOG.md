# Changelog

## 0.4.2

- **Fix: a finished job no longer asks for you.** A Codex app scheduled task's
  run, and a Codex or Claude Code fleet seat that finished a `Dispatch <id>:`
  prompt, showed under Needs You as "your turn", though no one was expected to
  reply. Vibra now reads who started the turn and lists these as idle. A turn
  you started still shows as your turn.
- **A "your turn" you have dealt with clears.** Clicking a Needs You row or
  its notification, and landing in the session, marks that turn handled: it
  drops to idle at once, stays idle across a relaunch, and comes back only
  when the session has new activity. An approval prompt is not cleared this
  way; it stays until it is answered.
- **"Your turn" fades after 2 h, not 8 h.** An unanswered turn still shows
  until then. The Settings window keeps the 1 h to 48 h range.

## 0.4.1

- **Fix: Vibra builds with Swift 6.1.** 0.4.0 compiled with Swift 6.4 but not
  with Swift 6.1.2, the compiler on GitHub's macOS 15 runners, where the
  Homebrew tap's CI build failed. Seven sites in the incident monitor, the
  menu controller, the incidents window and the notification code now keep
  main-actor and non-Sendable values where Swift 6.1 requires, and the
  notification handlers are `@Sendable` so they cannot trap when the system
  calls them on its own queue. Behaviour is unchanged. The `v0.4.0` tag was
  never released for this reason.
- **CI.** Every push builds the app, runs the tests and launches the app on
  the macOS 15 runners (Swift 6.1.2), Apple Silicon and Intel. Tests that exceeded Swift 6.1's
  type-check limit are rewritten with the same assertions, and the test runner
  now launches on a machine with Xcode.

## 0.4.0

- **Fix: a vendor usage file with usage after today is refused.** A day after
  the current UTC day used to be compared with this Mac's usage, which is zero
  for that day, and could be flagged as usage this Mac cannot explain. The file
  is now refused. An empty day after today, which a usage page lists as
  padding, is ignored.

- **Docs: removal instructions say what stays.** `make uninstall` and
  `brew uninstall` remove the installed files, not Vibra's saved data. The READMEs, the privacy page and
  STATUS now name the saved data left behind and the two commands that remove
  it: `rm -rf ~/Library/Application\ Support/Vibra` and
  `defaults delete ai.silexlab.vibra`. The translated READMEs gain Review Agent
  Activity, Code checks and Orca.

- **Review Agent Activity.** Vibra now watches Claude Code and Codex transcripts
  for denied calls that ran later, credential reads, writes outside the workspace,
  force pushes, unrestricted sessions and authentication failures. You answer each
  finding, or draft a report to the vendor and send it yourself. A usage file you
  fetch with your own key can be imported to flag days this Mac cannot explain.
  No network requests. The feature adds the first file Vibra persists beyond
  preferences, `~/Library/Application Support/Vibra/incidents.json`, holding hashed
  ids and your answers. See [docs/features.md](docs/features.md) and
  [docs/privacy.md](docs/privacy.md).

- **Return to Session works in Orca.** Clicking a Claude Code or Codex session
  running in an Orca terminal now switches Orca to that terminal. Before, it
  showed "No terminal owns ttysNNN", or wrongly blamed Terminal.app, because an
  ancestor named `terminal-host-<hash>` matched the word "terminal". Vibra now
  matches terminal names exactly. It reads one variable,
  `ORCA_TERMINAL_HANDLE`, from the agent's environment when you click.

- **Code checks in Session Details.** For Claude Code and Codex, the window now
  says whether a test, build or lint command ran after the session's last code
  change, and what it returned. It reports only what the transcript shows. A
  check whose exit status was hidden by a pipe reads as unknown unless the
  runner's own summary line settles it. It never says a task is done. Vibra
  reads command text and the end of check output for this, in memory, when the
  window opens, and keeps none of it.

- **A first-use loop.** The menu now leads with **Needs You** across all agents,
  then **Running**, with idle sessions in a **Recent** submenu; each row shows
  the agent, and a waiting row how long it has waited. **Session Details** opens
  a window for any session with the project, branch, state and the evidence
  behind it, its data source's health, tokens, and buttons for Return to
  Session, View History, Open Project Folder and Copy Path. A first-run
  **Setup** window (reopened by **Setup…**) shows what was found for each agent,
  the notification state with Enable and Send Test, and Launch at login. A
  source that cannot be read now shows a `Couldn't read <Agent> data` notice and
  keeps that agent's sessions listed. Agents and watched roots that appear after
  launch are discovered without a relaunch.
- **Changed: notification text uses the project name**, or a scheduled task name
  plus the project, never a title derived from a prompt.
- **Removed: the per-row token count.** Tokens are in the row's tooltip and in
  the detail window, where an unpublished count reads `None reported`.

## 0.3.0 — 2026-11-07

- **Homebrew installation.** The official `silex-ai-lab/tap` provides a source
  formula for `brew install silex-ai-lab/tap/vibra`. It installs the app in the
  Homebrew Cellar and adds `vibra --query`. It does not replace manual app
  installations or change signing and permission requirements.

- **Usage Report: performance suggestions for Claude Code.** Below the totals,
  the report (⌘U and `Vibra --report`) lists up to three patterns that cost
  your sessions the most in the last 7 days (context carried above 200k tokens, cache
  rewritten after a break or a model switch, long Read/Grep/Glob bursts), each
  with the command to try and the evidence. Figures are estimates of what the
  pattern cost at Vibra's table rates, not savings. New `Vibra --report --json`
  and `VIBRA_NOW`. See [docs/features.md](docs/features.md#performance-suggestions).
- **Fix: Claude Code tokens were counted about twice.** Claude Code writes one
  response as several records with the same ID and usage; Vibra now counts each
  response once (its records are adjacent, as in every case measured). Claude Code totals in the Usage Report and the menu drop; on
  the machine measured they halved (ratio 2.13), and yours depends on how many
  content blocks your responses have. Also fixed: the full-parse path read only the first 2,000 lines of
  a transcript, and Codex tokens after line 2,000 were reported as unpriced.
  Record: [docs/PLAN-2026-11-03-perf-suggestions.md](docs/PLAN-2026-11-03-perf-suggestions.md).

- **Docs: README restyled and translated.** The front page follows the
  layout of the Agent Reach README: centred header with badges, "Why
  Vibra?", a "Before you install" summary, agent icons in the compatibility
  table (from [Lobe Icons](https://github.com/lobehub/lobe-icons), MIT; see
  [docs/assets/agents/ATTRIBUTION.md](docs/assets/agents/ATTRIBUTION.md)) and
  design principles. The compatibility, session-state, install and privacy
  text is unchanged. New translations:
  [简体中文](README.zh-CN.md), [日本語](README.ja.md), [한국어](README.ko.md);
  the English README stays authoritative. Record:
  [plan/PLAN-2026-10-01-readme-restyle-i18n.md](plan/PLAN-2026-10-01-readme-restyle-i18n.md).

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
