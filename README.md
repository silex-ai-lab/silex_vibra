# Vibra

**Know when your coding agents need you.** A macOS menu-bar app that shows
which of your Claude Code, Codex, Cursor, VS Code (Copilot Chat), OpenCode and
Hermes sessions are working, waiting for your turn, or need an approval — for
the agents that can report it; see [Compatibility](#compatibility). Open
source (Apache 2.0). Local-only: no account, no telemetry, no network.

```
Vibra 2▶ 1!
─────────────────────────
Claude Code · 2
  🔵 vibra · working · 41k tok
  🟠 jayskills · your turn · 12k tok
Codex · 1
  🔵 silex_poc · working · 8k tok
OpenCode · 1
  ⚪️ scratchpad · idle · 10k tok
VS Code · 1
  🔴 Fix the login flow · needs approval · 3k tok
```

## Who it is for

Agents work for minutes at a time. The expensive failure isn't a crash — it's an
agent that finished four minutes ago and has been waiting for you ever since,
in a terminal tab you aren't looking at. Vibra watches the session files the
agents already write and surfaces the one that needs you.

## What it does

- **Every session's state in the menu bar**, with its project and tokens.
- **A notification when one needs you** (🟠 or 🔴), withdrawn once no longer true.
  A click jumps to it: the terminal tab (iTerm2, Terminal, herdr) or hosting app
  for Claude Code and Codex, the VS Code window, or Cursor brought forward.
  OpenCode and Hermes sessions cannot be jumped to.
- **What the work used and asked.** **Usage Report…** (⌘U): 7 days of tokens and
  API-equivalent value, dated for Claude Code and Codex. **History…** (⌘Y): the
  questions you asked. `--query`: the menu as JSON. See [features](docs/features.md).

### Session states

| State | Meaning |
|---|---|
| 🔵 working | Producing output. Leave it alone. |
| 🟠 your turn | Finished its turn; waiting on you. |
| 🔴 needs approval | Sitting on a permission prompt. |
| 🟡 stalled | Claimed to be mid-turn, then went silent. |
| ⚪️ idle | Settled, nothing pending. |

## Compatibility

| Agent guide | Covers | 🔵 | 🟠 | 🔴 | 🟡 | ⚪️ |
|---|---|---|---|---|---|---|
| [Claude Code](docs/agents/claude-code.md) | CLI, Claude desktop app, VS Code / Cursor extension | ✓ | ✓ | ✓ | ✓ | ✓ |
| [Codex](docs/agents/codex.md) | CLI, `codex exec`, desktop app, IDE extension | live | live | — | ✓ | ✓ |
| [Cursor](docs/agents/cursor.md) | Agents window and editor chat | live | ✓ | ✓ | — | live |
| [VS Code](docs/agents/vscode.md) | GitHub Copilot Chat (Ask, Edit, Agent mode), also Insiders | live | live | live | ✓ | live |
| [OpenCode](docs/agents/opencode.md) | incl. DeepSeek | ✓ | — | ✓ | — | ✓ |
| [Hermes](docs/agents/hermes.md) | CLI and chat gateways | ✓ | ✓ | — | ✓ | ✓ |

**live**: observed in a recorded live session. **✓**: can show; no live record yet (the guide
says if a fixture test covers it). **—**: never shown (e.g. no approval state from Codex/Hermes).

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

There is no downloadable app yet: Vibra is ad-hoc signed and not notarized, so
notifications need one manual System Settings step — see
[Troubleshooting](docs/troubleshooting.md#troubleshooting).

## Your first two minutes

1. Open Vibra. With nothing run in 12 hours it reads `No active sessions`: expected.
2. In a terminal, start an interactive **Claude Code** or **Codex** session and
   give it a task. Its row shows 🔵 working.
3. Let the turn finish: the row turns 🟠 your turn and the menu bar shows `1!`.

Without the menu: `make probe` in the cloned repo prints sessions and states,
never message content; it exits `2` if it finds none.

## Privacy

Vibra reads local files and sends nothing anywhere — a passive reader of the
session files and databases the agents already write (paths in each guide).

- **No network egress at all.** No account, no telemetry, no update ping.
- **It installs nothing into your agents** — no hooks, no plugins, no
  statusline, no wrapper binaries.
- OpenCode's and Cursor's databases hold auth tokens; each is opened read-only
  with one hard-coded `SELECT`, and the token tables are never queried.
- `--query`, `--probe` and the other machine-readable outputs never contain
  message text. History, the one feature that shows what you typed, keeps it in
  memory only while its window is open and writes nothing.
- It never approves an agent's permission prompt for you; it only shows it.

**Canary tests** plant sentinel secrets and message text in fixtures and assert they are absent
from returned sessions, their JSON, `--query` output or errors (per adapter); `make test` fails if
the OpenCode token canary did not run. Detail: [docs/privacy.md](docs/privacy.md).

## More and contributing

[Features](docs/features.md) · [Troubleshooting & limitations](docs/troubleshooting.md) ·
[Development](docs/development.md) · [Changelog](CHANGELOG.md) · [Roadmap](docs/ROADMAP.md)

Issues and pull requests are welcome. Run the tests with `make test` — not
`swift test`, which runs zero tests on a machine without Xcode.

## License

[Apache License 2.0](LICENSE)
