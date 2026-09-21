# vibra — current status

Last verified 2026-09-20 on a Mac mini (M4, macOS 26.6.2) with a 488-file,
339 MB session corpus, from a clean rebuild (`.build`, `build/` and
`/Applications/Vibra.app` all deleted first).

## Verdict

Usable. Phases 0 and 0b are closed; the app runs all day at 0.0% idle CPU and
reports live agent state correctly. The largest missing feature is terminal
jump-back (P1.1).

## Measured

| Metric | Value | Target | |
|---|---|---|---|
| Idle CPU | 0.0% | < 2% | ✅ |
| RSS (running app) | 43–76 MB (varies by run) | < 60 MB | ⚠️ borderline |
| Cold start | 0.64s, 13 MB read | — | ✅ |
| Unchanged refresh | 0.02s, **0 bytes** | 0 bytes | ✅ |
| Tests | 66 in 13 suites | — | ✅ |
| Bundle | 632 KB, ad-hoc signed | Developer ID | ⚠️ |

Reproduce with `make bench` and `make test`.

Brief CPU spikes (5–12%) are correct: FSEvents firing a refresh when an agent
writes to disk. Idle returns to 0.0% immediately.

## Verified on this install

- `--agents` — all three agents detected with source counts and last write.
- `--probe` — 5 live sessions, states correct.
- `--bench` — unchanged refresh reads **0 bytes**.
- `--test-notification` — authorization granted, notification posted.
- Menu bar item and `Usage Report…` window — **confirmed by the user**.

## What works, verified against real data

- **Three adapters** — Claude Code and Codex JSONL transcripts, OpenCode SQLite.
- **Agents are detected, not assumed** — an agent with no state on disk is
  never polled.
- **Live state classification.** Verified by driving a real Codex session:
  `working` at t+2s → `awaitingInput` at t+4s.
- **Notifications.** Delivered after the user enables them in System Settings
  (see caveat below).
- **Usage and cost**, per model, with `n/a` rather than a guess for unpriced
  models.
- **Robustness.** Torn final lines, binary garbage, empty files, a corrupt
  SQLite file and a fully absent agent all degrade cleanly, each covered by a
  test.
- **Security.** The OpenCode database holds auth tokens beside session data;
  the adapter opens it read-only, emits one hard-coded `SELECT` with an
  explicit column list, and a canary test asserts a sentinel token never
  reaches any output. `make test` fails if that canary did not run.

## Known gaps

| Gap | Impact | Fix |
|---|---|---|
| RSS 68 MB vs 60 MB target | Minor. Flat, not leaking. | AppKit + cold-parse high water |
| **Notch overlay never executed** | Unknown. `makeIfSupported()` returns nil on this hardware, so the code path has never run. | Needs a notched Mac |
| ~~Menu bar rendering never seen~~ | **Confirmed by the user 2026-09-20**: the status item renders, and `Usage Report…` opens and renders correctly. | — |
| OpenCode `ev=unknown` | DeepSeek sessions rarely report `needs approval`. Column is read and tested; the live transition has never been observed. | Observe a real approval prompt |
| Ad-hoc signed | macOS refuses notification authorization until enabled by hand. | P3.1, needs a paid Apple account |
| Terminal jump-back only outside multiplexers | tmux/screen/herdr panes cannot be focused; the emulator never sees their ptys. | Inherent; documented |
| Terminal.app jump path unexercised | Unknown. Terminal.app was not running during testing. | Run it and retest |
| OpenCode not locatable | Its sessions cannot be jumped to at all. | Needs a published pid link |
| Repo is private | Not publicly installable. | One command, user's call |

## Honest note on the cost figures

Costs are token counts times published per-model rates: an **API-equivalent
value**, not a bill. On a subscription you pay a flat fee and these numbers
say what the same usage would have cost at list price. A model with no known
published rate reports `n/a`.
