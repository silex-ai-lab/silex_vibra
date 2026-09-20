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

## Build

Requires macOS 14+ and a Swift 6 toolchain. **Xcode is not required** — Command
Line Tools is enough.

```sh
make app     # assembles build/Vibra.app
make run     # build and launch
make test    # run the test suite
```

`make app` hand-assembles the bundle (`LSUIElement`, so no Dock icon) and
ad-hoc signs it. Ad-hoc signing is *not* a substitute for Developer ID signing
and notarization if you distribute builds.

Diagnostics, printing session counts and states but never message content:

```sh
swift run VibraApp --probe
```

## Testing note

Run tests with `make test` or `swift run VibraTests` — **not** `swift test`.

On a machine without Xcode, SwiftPM builds the suite as a loadable `.xctest`
bundle it has no harness to execute. `swift test` then prints `Build complete!`,
runs **zero** tests, and exits `0`. That silent false green is worse than having
no tests, so the suite is an ordinary executable that invokes swift-testing's
entry point and returns a real exit code. `make test` additionally asserts that
a non-zero number of tests ran and that the security canary was among them.

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

## Status

Early. The menu bar, the three adapters, state classification, and usage/cost
accounting work against real data. Not yet done: terminal jump-back, weekly
report cards, and Developer ID signing.

## License

MIT
