<h1 align="center">📳 Vibra</h1>

<p align="center">
  <strong>当你的编码 Agent 需要你时，第一时间知道。</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=for-the-badge" alt="License: Apache 2.0"></a>
  <a href="#安装"><img src="https://img.shields.io/badge/macOS-14%2B-black.svg?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 14+"></a>
  <a href="docs/development.md"><img src="https://img.shields.io/badge/Swift-6-F05138.svg?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6"></a>
  <a href="#隐私"><img src="https://img.shields.io/badge/Network-none-2ea44f.svg?style=for-the-badge" alt="Network: none"></a>
  <a href="https://github.com/silex-ai-lab/silex_vibra/stargazers"><img src="https://img.shields.io/github/stars/silex-ai-lab/silex_vibra?style=for-the-badge" alt="GitHub stars"></a>
</p>

<p align="center">
  <a href="#快速开始">快速开始</a> · <a href="#支持的-agent">支持的 Agent</a> · <a href="#隐私">隐私</a> · <a href="#设计原则">设计原则</a>
  <br>
  <a href="README.md">English</a> · 简体中文 · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a>
</p>

---

英文版 README 为权威版本，本译文可能滞后。

一款 macOS 菜单栏应用，显示你的 Claude Code、Codex、Cursor、
VS Code（Copilot Chat）、OpenCode 和 Hermes 会话中有哪些正在工作、等待你的
回合，或需要批准——前提是该 Agent 能上报这些状态；见
[支持的 Agent](#支持的-agent)。开源（Apache 2.0）。仅本地：无
账号、无遥测、无网络。

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

> ⭐ **Star 这个项目**，新 Agent 和修复不会错过。Agent 改了会话文件，我来改 Vibra，你不用自己盯。[为什么值得 Star →](#-为什么值得-star)

## 为什么选择 Vibra

Agent 往往要连续工作好几分钟。代价最高的失败不是崩溃——而是
一个 Agent 四分钟前就完成了，却一直等着你，
而你根本没有看那个终端标签页。Vibra 监视这些
Agent 本来就会写入的会话文件，把需要你的那一个呈现出来。

- 🟠 **某个 Agent 完成了它的回合** → 对能上报该状态的 Agent，该行变为 🟠 轮到你，你会收到通知；一旦不再成立，通知即撤回。
- 🔴 **某个 Agent 正停在权限提示上** → 对能上报该状态的 Agent，该行变为 🔴 需要批准；Vibra 只显示它，绝不替你批准。
- 🖱️ **你想回到它那里** → 在 Agent 允许的情况下，点一下即可跳转过去；见 [功能](#功能)。
- 🧾 **你想知道这些工作用了多少** → **Usage Report…**（⌘U）显示 7 天的 token 和等值 API 费用。

### ✅ 安装前须知

| | |
|---|---|
| 💰 **免费且开源** | Apache License 2.0。 |
| 🔒 **仅本地** | 完全没有网络出口。无账号、无遥测、无更新 ping。 |
| 🧩 **不向你的 Agent 安装任何东西** | 没有 hook、没有插件、没有 statusline、没有包装二进制文件。 |
| 🤖 **六个 Agent** | 并非每个 Agent 都能上报每一种状态；见 [支持的 Agent](#支持的-agent)。 |
| 🩺 **自检** | 在克隆下来的仓库里运行 `make probe`，会打印会话和状态，绝不打印消息内容。 |
| ⚠️ **从源码构建** | 目前还没有可下载的应用：Vibra 采用 ad-hoc 签名，未做公证，因此通知需要手动完成一步“系统设置”操作。 |

## 支持的 Agent

| Agent guide | Covers | 🔵 | 🟠 | 🔴 | 🟡 | ⚪️ |
|---|---|---|---|---|---|---|
| <img src="docs/assets/agents/claudecode.svg" width="16" height="16" alt="Claude Code"> [Claude Code](docs/agents/claude-code.md) | CLI、Claude 桌面应用、VS Code / Cursor 扩展 | ✓ | ✓ | ✓ | ✓ | ✓ |
| <img src="docs/assets/agents/codex.svg" width="16" height="16" alt="Codex"> [Codex](docs/agents/codex.md) | CLI、`codex exec`、桌面应用、IDE 扩展 | live | live | — | ✓ | ✓ |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/cursor-for-dark.svg"><img src="docs/assets/agents/cursor-for-light.svg" width="16" height="16" alt="Cursor"></picture> [Cursor](docs/agents/cursor.md) | Agents 窗口和编辑器对话 | live | ✓ | ✓ | — | live |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/githubcopilot-for-dark.svg"><img src="docs/assets/agents/githubcopilot-for-light.svg" width="16" height="16" alt="GitHub Copilot"></picture> [VS Code](docs/agents/vscode.md) | GitHub Copilot Chat（Ask、Edit、Agent 模式），也支持 Insiders | live | live | live | ✓ | live |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/opencode-for-dark.svg"><img src="docs/assets/agents/opencode-for-light.svg" width="16" height="16" alt="OpenCode"></picture> [OpenCode](docs/agents/opencode.md) | 包含 DeepSeek | ✓ | — | ✓ | — | ✓ |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/hermesagent-for-dark.svg"><img src="docs/assets/agents/hermesagent-for-light.svg" width="16" height="16" alt="Hermes Agent"></picture> [Hermes](docs/agents/hermes.md) | CLI 和聊天网关 | ✓ | ✓ | — | ✓ | ✓ |

**live**：已在有记录的实时会话中观察到。**✓**：可以显示，但还没有实时记录（指南
会说明是否有夹具测试覆盖）。**—**：从不显示（例如 Codex/Hermes 没有批准状态）。

### 会话状态

| 状态 | 含义 |
|---|---|
| 🔵 工作中 (working) | 正在产生输出。别打扰它。 |
| 🟠 轮到你 (your turn) | 回合已结束；在等你。 |
| 🔴 需要批准 (needs approval) | 停在权限提示上。 |
| 🟡 停滞 (stalled) | 声称进行到一半，然后没了动静。 |
| ⚪️ 空闲 (idle) | 已安定，没有待处理事项。 |

## 功能

- **在菜单栏显示每个会话的状态**，以及它的项目和 token。
- **当某个会话需要你时发出通知**（🟠 或 🔴），一旦不再成立即撤回。
  点击即可跳转过去：Claude Code 和 Codex 会跳到终端标签页（iTerm2、Terminal、herdr）或宿主应用，
  VS Code 会聚焦窗口，Cursor 会被带到前台。
  OpenCode 和 Hermes 会话无法跳转。
- **这些工作用了什么、问了什么。** **Usage Report…**（⌘U）：7 天的 token 和
  等值 API 费用，只有 Claude Code 和 Codex 带日期。**History…**（⌘Y）：
  你问过的问题。`--query`：以 JSON 输出菜单。见 [功能说明](docs/features.md)。

## 快速开始

### 安装

需要 **macOS 14+** 和 Swift 6 工具链。**不需要 Xcode** ——
有 Command Line Tools 就够了：

```sh
xcode-select --install     # skip if `swift --version` already works
```

然后：

```sh
git clone https://github.com/silex-ai-lab/silex_vibra.git
cd silex_vibra
make install               # builds, then copies to /Applications
open /Applications/Vibra.app
```

`make install` 会先退出正在运行的副本，因此在拉取更新后
可以放心重跑。

没有 Dock 图标，也没有窗口 —— 已设置 `LSUIElement`，所以**菜单栏项目
就是整个应用**。看着菜单栏右侧找
`Vibra`，或会话活跃时像 `2▶ 1!` 这样的计数。

完整删除：

```sh
make uninstall
```

### 首次启动

macOS 可能警告该应用来自未识别的开发者：它采用 ad-hoc 签名，
而不是 Developer ID 签名。在 Finder 中右键点按该应用并选择
**打开** 一次，或运行：

```sh
xattr -dr com.apple.quarantine /Applications/Vibra.app
```

目前还没有可下载的应用：Vibra 采用 ad-hoc 签名，未做公证，因此
通知需要手动完成一步“系统设置”操作 —— 见
[疑难解答](docs/troubleshooting.md#troubleshooting)。

### 你的最初两分钟

1. 打开 Vibra。如果 12 小时内什么都没运行，它会显示 `No active sessions`：这是正常的。
2. 在终端里启动一个交互式 **Claude Code** 或 **Codex** 会话并
   给它一个任务。它的行会显示 🔵 工作中。
3. 让这一回合结束：该行会变为 🟠 轮到你，菜单栏显示 `1!`。

不用菜单时：在克隆下来的仓库里运行 `make probe` 会打印会话和状态，
绝不打印消息内容；如果没找到会话，退出码为 `2`。

## 设计原则

- **被动的读取者。** Vibra 从不要求这些工具改变它们写入的内容。它是
  对已存在文件的被动读取者。
- **只显示，从不代替操作。** 它绝不替你批准 Agent 的权限提示；它只是显示。
- **只陈述它见到的。** 上表把在有记录的实时会话中观察到的状态（**live**）
  与代码能显示但尚无实时记录的状态（**✓**）区分开。

## 隐私

Vibra 读取本地文件，不向任何地方发送 —— 它被动读取
这些 Agent 本来就会写入的会话文件和数据库（路径见各指南）。

- **完全没有网络出口。** 无账号、无遥测、无更新 ping。
- **它不向你的 Agent 安装任何东西** —— 没有 hook、没有插件、没有
  statusline、没有包装二进制文件。
- OpenCode 和 Cursor 的数据库保存着认证 token；两者都以只读方式打开，
  只执行一条硬编码的 `SELECT`，绝不查询 token 表。
- `--query`、`--probe` 及其他机器可读输出绝不包含
  消息文本。History 是唯一会显示你输入内容的特性，它只在
  窗口打开期间把内容留在内存中，不写入任何东西。
- 它绝不替你批准 Agent 的权限提示；它只是显示。

**Canary 测试** 会在夹具中植入哨兵密钥和消息文本，并断言它们不出现在
返回的会话、其 JSON、`--query` 输出或错误中（按适配器）；如果
OpenCode token canary 没有运行，`make test` 会失败。详情：[docs/privacy.md](docs/privacy.md)。

## ⭐ 为什么值得 Star

这个项目我自己每天都在用，用它盯着我自己的那几个 Agent，所以我会一直维护它。

- 大家想要接入新的 Agent，或者给已支持的 Agent 加新状态，我会陆续加上
- 每个 Agent 我都会尽量保证**能用、免费、全本地**：不用注册账号，没有付费版，任何数据都不发出去
- Agent 升级后经常会改它写的会话文件。哪次升级让 Vibra 读不了了，我来修适配器，你不用自己盯着

还有更多理由：

- 🔒 **隐私靠测试保证，不只是口头承诺**：canary 测试会埋入假的密钥和消息内容，只要有任何一条出现在 Vibra 的输出里，构建就会失败
- 🧾 **能做到什么就说什么**：兼容性表把真实会话里见过的状态（**live**）和代码能显示但还没人实际见过的状态（**✓**）分开标；每多见到一种状态就更新这张表
- 🧩 **不动你的 Agent 配置**：不往 Agent 里装 hook、插件或包装程序，`make uninstall` 一条命令就能删掉 App
- 🌏 **四种语言的说明**：English、简体中文、日本語、한국어
- 📣 **让更多人找到它**：每个 Star 都能让同时跑好几个 Agent 的人更容易发现 Vibra

Star 一下，下次 Agent 已经等了你半天你却没发现的时候，就能找到它。⭐

## 更多与贡献

[功能](docs/features.md) · [疑难解答与限制](docs/troubleshooting.md) ·
[开发](docs/development.md) · [更新日志](CHANGELOG.md) · [路线图](docs/ROADMAP.md)

欢迎提交 Issue 和 Pull Request。用 `make test` 运行测试 —— 不要用
`swift test`，在没有 Xcode 的机器上它不会运行任何测试。

## 许可证

[Apache License 2.0](LICENSE)

兼容性表中的 Agent 标识见 [docs/assets/agents/ATTRIBUTION.md](docs/assets/agents/ATTRIBUTION.md)。
