# vibra — current status

Last verified 2026-09-20 against a clean clone of `main`, installed and run on
a Mac mini (M4, macOS 26) with a 488-file, 339 MB session corpus.

## Verdict

Usable. Phases 0 and 0b are closed; the app runs all day at 0.0% idle CPU and
reports live agent state correctly. The largest missing feature is terminal
jump-back (P1.1).

## Measured

| Metric | Value | Target | |
|---|---|---|---|
| Idle CPU | 0.0% | < 2% | ✅ |
| RSS (running app) | 68.1 MB | < 60 MB | ⚠️ missed |
| Cold start | 0.36s, 7.3 MB read | — | ✅ |
| Unchanged refresh | 0.02s, **0 bytes** | 0 bytes | ✅ |
| Tests | 39 in 9 suites | — | ✅ |
| Bundle | 632 KB, ad-hoc signed | Developer ID | ⚠️ |

Reproduce with `make bench` and `make test`.

Brief CPU spikes (5–12%) are correct: FSEvents firing a refresh when an agent
writes to disk. Idle returns to 0.0% immediately.

## What works, verified against real data

- **Three adapters** — Claude Code and Codex JSONL transcripts, OpenCode SQLite.
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
| **Menu bar rendering never seen** | Unknown. No Screen Recording permission on the dev machine. | User confirmation |
| OpenCode `ev=unknown` | DeepSeek sessions rarely report `needs approval`. Column is read and tested; the live transition has never been observed. | Observe a real approval prompt |
| Ad-hoc signed | macOS refuses notification authorization until enabled by hand. | P3.1, needs a paid Apple account |
| No terminal jump-back | Largest missing feature. | P1.1 |
| Repo is private | Not publicly installable. | One command, user's call |

## Honest note on the cost figures

Costs are token counts times published per-model rates: an **API-equivalent
value**, not a bill. On a subscription you pay a flat fee and these numbers
say what the same usage would have cost at list price. A model with no known
published rate reports `n/a`.
