# vibra — current status

Last verified **2026-09-20** on a Mac mini (M4, macOS 26.6.2) against a
488-file, 339 MB session corpus, from a full clean rebuild — `.build`,
`build/` and `/Applications/Vibra.app` all deleted first.

## Verdict

**Usable day to day.** Phases 0, 0b, 1 and P2.1 are closed: vibra runs
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
| 2 | P2.2 More adapters | ⛔ Blocked — no viable target found |
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

## Verified on the current install

- `--agents` — three agents detected, with source counts and last write.
- `--probe` — 5 live sessions, states correct.
- `--bench` — unchanged refresh reads **0 bytes**.
- `--test-notification` — authorization granted, notification posted.
- `--report` — per-day figures matched an **independent** recomputation
  straight from the raw transcripts, on every day in the window.
- Menu bar item and the `Usage Report…` window — **confirmed by the user**.

## What works, verified against real data

- **Three adapters** — Claude Code and Codex JSONL transcripts, OpenCode SQLite.
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
- **vibra installs nothing into your agents.** No hooks, no plugins, no
  statusline, no wrapper binaries. It only reads files the agents already
  write. This matters: the commercial tool this project was written against
  installed 14 hooks into `~/.claude/settings.json`, 10 into
  `~/.codex/hooks.json`, a Copilot hook, an OpenCode plugin, and replaced the
  Claude Code status line — all of which survived uninstalling its app, and
  kept executing on every tool call. vibra is a passive reader by design, so
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
| Jump-back unavailable inside multiplexers | tmux, screen and herdr own their panes' ptys, so the emulator never sees them. vibra refuses to guess. | Inherent; documented |
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
