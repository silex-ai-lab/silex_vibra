# vibra

A status companion for AI coding agents on macOS. It tells you which of your
agent sessions are working, which are waiting on *you*, and what they have cost
so far — from the menu bar, without switching to a terminal to find out.

Open source (MIT), local-only, no account, no telemetry, no network egress.

```
vibra 2▶ 1!
─────────────────────────
Claude Code
  🔵 vibra · working · 41k tok
  🟠 jayskills · your turn · 12k tok
Codex
  🔵 silex_poc · working · 8k tok
OpenCode
  ⚪️ scratchpad · idle · 10k tok
```

## Why

Agents work for minutes at a time. The expensive failure isn't a crash — it's an
agent that finished four minutes ago and has been waiting for you ever since,
in a terminal tab you aren't looking at. vibra watches the session files the
agents already write and surfaces the one that needs you.

## Supported agents

| Agent | Source it reads |
|---|---|
| Claude Code | `~/.claude/projects/<slug>/<uuid>.jsonl` |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` |
| OpenCode (incl. DeepSeek) | `~/.local/share/opencode/opencode.db` |

vibra never asks these tools to change what they write. It is a passive reader
of files that already exist.

**It installs nothing into your agents** — no hooks, no plugins, no statusline,
no wrapper binaries. Uninstalling vibra is deleting one `.app`.

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
goes back to work, when the session disappears, and when vibra quits. Each
session's notification is keyed by its session id, so one session that keeps
wanting you replaces its own entry rather than stacking new ones.

That matters because the alternative is what vibra used to do: banners
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
git clone https://github.com/silex-ai-lab/vibra.git
cd vibra
make install               # builds, then copies to /Applications
open /Applications/Vibra.app
```

`make install` quits any running copy first, so it is safe to re-run after
pulling changes.

There is no Dock icon and no window — `LSUIElement` is set, so **the menu bar
item is the entire app**. Look at the right-hand side of your menu bar for
`vibra`, or a count like `2▶ 1!` when sessions are live.

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
total sessions: 4
```

`probe` prints counts, project names and states. It never prints message
content. It exits `2` if it found no sessions at all, which usually means you
have not used any of the three agents in the last 12 hours.

**To see it change live:** start a Claude Code or Codex session in another
terminal, give it a task, and run `make probe` again — that session should
appear as `working`. When it finishes and waits for you, it flips to
`awaitingInput` and the menu bar count shows `1!`.

### Run the tests

```sh
make test
```

Expect `Test run with 20 tests in 6 suites passed` followed by
`OK: tests executed, canary present`.

### Development loop

```sh
make restart    # rebuild and relaunch the running copy
make probe      # check adapter output without the UI

# check whether macOS will actually deliver notifications here
/Applications/Vibra.app/Contents/MacOS/Vibra --test-notification
```

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

vibra reads local files and sends nothing anywhere. Specifically:

- **No network egress at all.** No account, no telemetry, no update ping.
- `opencode.db` also contains `access_token`, `refresh_token` and a `credential`
  table. The adapter opens the database **read-only** (`mode=ro`), emits a
  single hard-coded `SELECT` against the `session` table with an explicit column
  list, never `SELECT *`, and verifies the schema before querying.
- A **canary test** builds a fixture database containing a sentinel token and
  asserts that string appears nowhere in the returned sessions, their JSON
  encoding, or any error description. `make test` fails if that test did not run.
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

**Clicking a session says vibra isn't allowed to control iTerm2/Terminal.**
That is macOS refusing the Apple Event. Grant it under System Settings →
Privacy & Security → Automation → Vibra. To see what vibra thinks it is dealing
with before clicking anything:

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --locate
```

The `tty owner:` line reads `emulator iTerm2 - jumpable` for a normal tab and
`multiplexer tmux - not jumpable` for a pane the emulator cannot see. It comes
from walking the process ancestry, so it is a fact about your machine rather
than a guess.

**`make probe` says `total sessions: 0`.** Nothing has run in the last 12 hours.
The window is `activityWindow` in `Sources/VibraApp/SessionStore.swift`.

**`swift test` says everything passed but nothing ran.** Use `make test`. See
the testing note above — this is expected on a machine without Xcode.

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
  click prompts for it. vibra is ad-hoc signed, so rebuilding changes its
  identity and macOS may ask again.
- **No weekly report card.**
- **OpenCode blocked-state detection is unverified.** The adapter does read the
  `permission` column and maps a non-empty value to `needs approval`, but that
  transition has not yet been observed live against a real approval prompt.
- **Not signed or notarized**, so this is build-from-source only. There is no
  release download and no Homebrew cask.

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

Working against real data: the menu bar, all three adapters, state
classification, usage/cost accounting, and terminal jump-back. Not yet done:
weekly report cards, and Developer ID signing.

## License

MIT
