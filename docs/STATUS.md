# Vibra — current status

**0.2.0.** Last verified **2026-09-21** on macOS 15.7.3 / Swift 6.1.2 from a
clean clone and a full clean rebuild; before that, **2026-09-20** on a Mac mini
(M4, macOS 26.6.2) against a 488-file, 339 MB session corpus, with `.build`,
`build/` and `/Applications/Vibra.app` all deleted first.

Changes in 0.2.0 are in the next section; older measurements below it still
refer to the 2026-09-20 run.

## Verdict

**Usable day to day.** Phases 0, 0b, 1 and P2.1 are closed: Vibra runs
continuously at 0.0% idle CPU, reports live agent state, alerts when a session
wants you, focuses the terminal a session runs in, and produces a rolling
usage report.

Everything achievable without the user's involvement is done. What remains is
either blocked on a paid Apple Developer account (P3.x) or has no viable
target on this machine (P2.2).

| Phase | Step | State |
|---|---|---|
| 0 | P0.1 Stop re-parsing the world | ✅ Done |
| 0 | P0.2 Bounded-memory parsing | ✅ Done |
| 0 | P0.3 OpenCode permission column | ⊘ Cut — already implemented |
| 0b | P0b.1 Make the notifier testable | ✅ Done |
| 1 | P1.1 Terminal jump-back | ✅ Done (v1) |
| 1 | P1.2 Usage figures stay local | ✅ Decided — no network, ever |
| 1 | P1.3 Weekly report card | ✅ Done |
| 2 | P2.1 Auto-detect installed agents | ✅ Done |
| 2 | P2.2 More adapters | ✅ Done — Cursor, VS Code Copilot Chat |
| 3 | P3.1 Developer ID signing | ⛔ Blocked on a user decision |
| 3 | P3.2 Sparkle auto-update | Behind P3.1 |
| 3 | P3.3 Homebrew cask | Behind P3.1 |

## Measured

| Metric | Value | Target | |
|---|---|---|---|
| Idle CPU | 0.0% | < 2% | ✅ |
| RSS (running app) | **43–76 MB**, varies between runs | < 60 MB | ⚠️ borderline |
| Cold start | 0.64s, 13 MB read | — | ✅ |
| Unchanged refresh | 0.03s, **0 bytes** | 0 bytes | ✅ |
| Tests | 66 in 13 suites | — | ✅ |
| Bundle | 632 KB, ad-hoc signed | Developer ID | ⚠️ |

Reproduce with `make bench` and `make test`.

Two honest notes on these numbers. **RSS is a range, not a figure** — measured
at 43, 68, 70, 75 and 76 MB across runs; quoting any single value overstates
the precision, and the <60 MB target is met on some runs and missed on others.
Brief **CPU spikes of 5–12%** are correct behaviour: FSEvents firing a refresh
when an agent writes to disk. Idle returns to 0.0% immediately.

## 0.2.0 — 2026-09-21, macOS 15.7.3 / Swift 6.1.2

A clean clone, `make build`, `make test`, `make probe`, `make install`. Build is
warning-free, **76 tests** pass (66 before), adapters read live sessions, the
app idles at 0.0–0.1% CPU and 42–46 MB RSS. Four bugs, all found on macOS 15
where the macOS 26 pass could not have shown them, and all fixed.

### 1. `--test-notification` trapped instead of reporting

`dispatch_assert_queue_fail`, SIGTRAP, exit 133, and **no output at all** —
it died before the first `print` could flush. Top-level code in `main.swift`
is `@MainActor` under Swift 6, so the UserNotifications callbacks inherited
that isolation while being invoked on a background dispatch queue. Both
handlers are `@Sendable` now. This mattered beyond itself: the README points
at this command as *the* way to find out whether notifications work, so while
it crashed there was no way to answer that question. (`c788703`)

### 2. Delivered notifications were never withdrawn

`NotificationSink` had only `deliver`; `removeDeliveredNotifications` was
called nowhere. A "your turn" banner for a session you had already answered
stayed in Notification Center for the whole login. It could not have been
fixed by adding the call alone — `deliver` used `UUID().uuidString` per post,
so there was no stable handle to withdraw by, and repeat alerts for one
session stacked as separate entries.

Notifications are keyed by session id now, and pulled when the session leaves
the attention state, disappears, or Vibra quits. The debounce is deliberately
**not** cleared on withdrawal: it exists for state flicker, and clearing it
would let a flickering session re-alert. Seven new tests, including the two
that would silently undo the feature (still-waiting must not withdraw, flicker
must not re-alert). (`801b6d8`, `cb12a97`)

Verified live against the Notification Center database, not by eye: a real
alert carried a Claude Code session id as its identifier; re-posting replaced
the entry instead of stacking; a session still in `awaitingInput` kept its
notification; quitting removed it; three `--test-notification` runs left one
notification instead of three.

### 3. Terminal jump-back never worked, and blamed tmux for it

Clicking a session reported *"No terminal owns ttysNNN — the session is
probably inside a multiplexer such as tmux, screen or herdr"*. On a plain
iTerm2 tab that is false, and it sent the user looking for a problem they did
not have.

The real chain: `Info.plist` had no `NSAppleEventsUsageDescription`, so macOS
refused the Apple Event outright and **never prompted**, which meant Vibra
could never be granted Automation permission at all. `NSAppleScript` returned
-1743, `runAppleScript` collapsed every error into `false`, and the caller read
that as "no terminal owns this tty".

Three fixes: the Info.plist declares why it sends Apple Events, so the first
click prompts; `errAEEventNotPermitted` is distinguished from an ordinary miss
and surfaces with the settings path; and when no tab really does own the tty,
the explanation comes from **walking the process ancestry** rather than being
assumed. `--locate` prints the verdict too, so the question a failed jump turns
on can be answered without clicking anything:

```
   pid=5957 tty=ttys000 cwd=/Users/…/workplace
   tty owner: emulator iTerm2 - jumpable
```

(`b45f0ad`)

### 4. TCC grants did not survive a rebuild, and a failed signature was silent

An ad-hoc bundle has no identity, so macOS pins its TCC grants to the exact
code hash. Measured: the Automation grant's `csreq` was 40 bytes — `fade0c00…`
followed directly by the cdhash. Every rebuild that changes a byte of the
binary revokes it. Reverting the source does not undo that either: change a
string literal, rebuild, cdhash changes; revert it, rebuild, and **the cdhash
does not come back**. A release build stops being byte-reproducible once the
build cache has been disturbed.

`SIGN_IDENTITY` signs with a named certificate instead — a self-signed
code-signing certificate in the login keychain is enough, no Apple account and
no network. The designated requirement then names the certificate, and the
re-issued grant's `csreq` is 76 bytes containing `ai.silexlab.vibra` plus the
certificate hash, **with no cdhash in it**. Unset, the build is ad-hoc exactly
as before, so a fresh clone and CI are unaffected.

Signing failure is also fatal now, and its stderr is no longer hidden. An
unsigned bundle still launches, so a swallowed error there does not look like a
build problem — it looks like notifications and jump-back being mysteriously
broken, days later. That is not hypothetical: it happened during this work and
cost a full round of debugging the wrong layer. The recipe additionally checks
what it *produced*, because asking for an identity and silently getting ad-hoc
is the failure that hides best. (`6bd5131`, `6e7adee`)

### Measured on the rebuild test

| | before rebuild | after rebuild |
|---|---|---|
| cdhash | `050f3998…` | `cba7f543…` (changed, as ad-hoc would need) |
| TCC grant row | `fade0c00…f067ca2a…` | **byte-identical, not re-issued** |
| `codesign --verify` | satisfies its DR | satisfies its DR |

### Two traps worth carrying forward

- **Notification Center's `record` table retains rows after a notification is
  removed.** `delivered` is the live list (one row per app, a blob of raw
  16-byte UUIDs). Reading `record` said a withdrawal had failed when it had
  succeeded, and that misreading produced a whole `.terminateLater` barrier for
  a race that does not exist — reverted before it was committed. Full account
  in `docs/FIX-PLAN-notifications.md`.
- **Two bundles with the same id means LaunchServices picks one, and not
  necessarily the installed one.** A permission check was run against the
  `build/` copy without anyone noticing and read as "the permission does not
  work"; the two copies have different code hashes and do not share TCC grants.
  `make install` now deletes the build copy.

### Still not verified

Notification *authorization* had to be enabled by hand (System Settings →
Notifications → Vibra) — ad-hoc signing refuses it by default, and that
remains true for a fresh clone. Automation permission likewise needs one
approval; the certificate is what makes that approval outlive rebuilds.

## Verified on the current install

- `--agents` — three agents detected, with source counts and last write.
- `--probe` — 5 live sessions, states correct.
- `--bench` — unchanged refresh reads **0 bytes**.
- `--test-notification` — authorization granted, notification posted.
- `--report` — per-day figures matched an **independent** recomputation
  straight from the raw transcripts, on every day in the window.
- Menu bar item and the `Usage Report…` window — **confirmed by the user**.

## What works, verified against real data

- **Five adapters** — Claude Code, Codex and VS Code Copilot Chat JSONL logs; OpenCode and Cursor SQLite.
- **Agents are detected, not assumed.** An agent with no state on disk is never
  polled, so supporting one nobody installed costs nothing.
- **Live state classification.** Verified by driving a real Codex session:
  `working` at t+2s → `awaitingInput` at t+4s.
- **Terminal jump-back**, via an exact chain — session id → pid → tty → tab —
  with no working-directory guessing. Verified on the hard case: two Claude
  sessions sharing one directory resolved to *different* ttys.
- **Rolling 7-day usage report**, attributing tokens to the day they were
  incurred rather than to the day a session happened to end.
- **Notifications**, after the user enables them in System Settings.
- **Usage and cost** per model, reporting `n/a` rather than a guess for
  unpriced models.
- **Robustness.** Torn final lines, binary garbage, empty files, a corrupt
  SQLite file and a fully absent agent all degrade cleanly, each under test.

## Safety properties

- **No network egress at all.** No account, no telemetry, no update ping.
- **Vibra installs nothing into your agents.** No hooks, no plugins, no
  statusline, no wrapper binaries. It only reads files the agents already
  write. This matters: the commercial tool this project was written against
  installed 14 hooks into `~/.claude/settings.json`, 10 into
  `~/.codex/hooks.json`, a Copilot hook, an OpenCode plugin, and replaced the
  Claude Code status line — all of which survived uninstalling its app, and
  kept executing on every tool call. Vibra is a passive reader by design, so
  removing it is deleting one `.app`.
- **Secrets are never read.** `opencode.db` holds auth tokens beside session
  data, and `~/.claude/sessions/` holds `.key` files beside the JSON. The
  adapters use read-only access and explicit allowlists, and **canary tests**
  assert sentinel secrets reach no output. `make test` fails if a canary did
  not run. Both checks are mutation-tested.

## Known gaps

| Gap | Impact | Fix |
|---|---|---|
| RSS sometimes exceeds the 60 MB target | Minor. Flat within a run, not leaking. | AppKit + cold-parse high water |
| **Notch overlay has never executed** | Unknown. `makeIfSupported()` returns nil on this hardware, so the code path has never run once. | Needs a notched Mac |
| **Terminal.app jump path unexercised** | Unknown. It was not running during testing; only iTerm2 was verified. | Run Terminal.app and retest |
| Jump-back unavailable inside multiplexers | tmux, screen and herdr own their panes' ptys, so the emulator never sees them. Vibra refuses to guess. | Inherent; documented |
| OpenCode not locatable | Its sessions cannot be jumped to at all. | Needs a published pid link |
| OpenCode usage cannot be dated | Its tokens appear on a separate "undated" line in the report. | Needs per-record timestamps |
| OpenCode `ev=unknown` | Rarely reports `needs approval`. The column is read and tested; the live transition has never been observed. | Observe a real approval prompt |
| Ad-hoc signed | macOS refuses notification authorization until enabled by hand. | P3.1 — needs a paid Apple account |
| Repo is private | Not publicly installable. | One command, user's call |

## Honest note on the cost figures

Dollar figures are token counts times published per-model rates: an
**estimated API-equivalent value**, not a bill. On a subscription you pay a
flat fee, and these numbers say what the same usage would have cost at list
price. A model with no published rate is reported as unpriced, never as $0 —
free and unknown must not look alike.
