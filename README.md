<h1 align="center">📳 Vibra</h1>

<p align="center">
  <strong>Know when your coding agents need you.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=for-the-badge" alt="License: Apache 2.0"></a>
  <a href="#install"><img src="https://img.shields.io/badge/macOS-14%2B-black.svg?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 14+"></a>
  <a href="docs/development.md"><img src="https://img.shields.io/badge/Swift-6-F05138.svg?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6"></a>
  <a href="#privacy"><img src="https://img.shields.io/badge/Network-none-2ea44f.svg?style=for-the-badge" alt="Network: none"></a>
  <a href="https://github.com/silex-ai-lab/silex_vibra/stargazers"><img src="https://img.shields.io/github/stars/silex-ai-lab/silex_vibra?style=for-the-badge" alt="GitHub stars"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> · <a href="#supported-agents">Supported agents</a> · <a href="#privacy">Privacy</a> · <a href="#design-principles">Design principles</a>
  <br>
  English · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a>
</p>

---

A macOS menu-bar app that shows which of your Claude Code, Codex, Cursor,
VS Code (Copilot Chat), OpenCode and Hermes sessions are working, waiting for
your turn, or need an approval — for the agents that can report it; see
[Supported agents](#supported-agents). Open source (Apache 2.0). Local-only: no
account, no telemetry, no network.

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

## Why Vibra?

Agents work for minutes at a time. The expensive failure isn't a crash — it's an
agent that finished four minutes ago and has been waiting for you ever since,
in a terminal tab you aren't looking at. Vibra watches the session files the
agents already write and surfaces the one that needs you.

- 🟠 **An agent finished its turn** → for the agents that can report it, the row turns 🟠 your turn and you get a notification, withdrawn once no longer true.
- 🔴 **An agent is sitting on a permission prompt** → for the agents that can report it, the row turns 🔴 needs approval; Vibra only shows it and never approves it for you.
- 🖱️ **You want to get back to it** → a click jumps to it, where the agent allows; see [What it does](#what-it-does).
- 🧾 **You want to know what the work used** → **Usage Report…** (⌘U) shows 7 days of tokens and API-equivalent value.

### ✅ Before you install

| | |
|---|---|
| 💰 **Free and open source** | Apache License 2.0. |
| 🔒 **Local-only** | No network egress at all. No account, no telemetry, no update ping. |
| 🧩 **Installs nothing into your agents** | No hooks, no plugins, no statusline, no wrapper binaries. |
| 🤖 **Six agents** | Not every agent can report every state; see [Supported agents](#supported-agents). |
| 🩺 **Self-check** | `make probe` in the cloned repo prints sessions and states, never message content. |
| ⚠️ **Build from source** | There is no downloadable app yet: Vibra is ad-hoc signed and not notarized, so notifications need one manual System Settings step. |

## Supported agents

| Agent guide | Covers | 🔵 | 🟠 | 🔴 | 🟡 | ⚪️ |
|---|---|---|---|---|---|---|
| <img src="docs/assets/agents/claudecode.svg" width="16" height="16" alt="Claude Code"> [Claude Code](docs/agents/claude-code.md) | CLI, Claude desktop app, VS Code / Cursor extension | ✓ | ✓ | ✓ | ✓ | ✓ |
| <img src="docs/assets/agents/codex.svg" width="16" height="16" alt="Codex"> [Codex](docs/agents/codex.md) | CLI, `codex exec`, desktop app, IDE extension | live | live | — | ✓ | ✓ |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/cursor-for-dark.svg"><img src="docs/assets/agents/cursor-for-light.svg" width="16" height="16" alt="Cursor"></picture> [Cursor](docs/agents/cursor.md) | Agents window and editor chat | live | ✓ | ✓ | — | live |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/githubcopilot-for-dark.svg"><img src="docs/assets/agents/githubcopilot-for-light.svg" width="16" height="16" alt="GitHub Copilot"></picture> [VS Code](docs/agents/vscode.md) | GitHub Copilot Chat (Ask, Edit, Agent mode), also Insiders | live | live | live | ✓ | live |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/opencode-for-dark.svg"><img src="docs/assets/agents/opencode-for-light.svg" width="16" height="16" alt="OpenCode"></picture> [OpenCode](docs/agents/opencode.md) | incl. DeepSeek | ✓ | — | ✓ | — | ✓ |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/hermesagent-for-dark.svg"><img src="docs/assets/agents/hermesagent-for-light.svg" width="16" height="16" alt="Hermes Agent"></picture> [Hermes](docs/agents/hermes.md) | CLI and chat gateways | ✓ | ✓ | — | ✓ | ✓ |

**live**: observed in a recorded live session. **✓**: can show; no live record yet (the guide
says if a fixture test covers it). **—**: never shown (e.g. no approval state from Codex/Hermes).

### Session states

| State | Meaning |
|---|---|
| 🔵 working | Producing output. Leave it alone. |
| 🟠 your turn | Finished its turn; waiting on you. |
| 🔴 needs approval | Sitting on a permission prompt. |
| 🟡 stalled | Claimed to be mid-turn, then went silent. |
| ⚪️ idle | Settled, nothing pending. |

## What it does

- **Every session's state in the menu bar**, with its project and tokens.
- **A notification when one needs you** (🟠 or 🔴), withdrawn once no longer true.
  A click jumps to it: the terminal tab (iTerm2, Terminal, herdr) or hosting app
  for Claude Code and Codex, the VS Code window, or Cursor brought forward.
  OpenCode and Hermes sessions cannot be jumped to.
- **What the work used and asked.** **Usage Report…** (⌘U): 7 days of tokens and
  API-equivalent value, dated for Claude Code and Codex. **History…** (⌘Y): the
  questions you asked. `--query`: the menu as JSON. See [features](docs/features.md).

## Quick start

### Install

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

### Your first two minutes

1. Open Vibra. With nothing run in 12 hours it reads `No active sessions`: expected.
2. In a terminal, start an interactive **Claude Code** or **Codex** session and
   give it a task. Its row shows 🔵 working.
3. Let the turn finish: the row turns 🟠 your turn and the menu bar shows `1!`.

Without the menu: `make probe` in the cloned repo prints sessions and states,
never message content; it exits `2` if it finds none.

## Design principles

- **A passive reader.** Vibra never asks these tools to change what they write. It is a passive reader
  of files that already exist.
- **Shows, never acts.** It never approves an agent's permission prompt for you; it only shows it.
- **Says what it has seen.** The table above keeps states observed in a recorded live session (**live**)
  apart from states the code can show with no live record yet (**✓**).

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

Agent marks in the compatibility table: see [docs/assets/agents/ATTRIBUTION.md](docs/assets/agents/ATTRIBUTION.md).
