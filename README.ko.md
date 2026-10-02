<h1 align="center">📳 Vibra</h1>

<p align="center">
  <strong>코딩 에이전트가 당신을 필요로 할 때 바로 알 수 있습니다.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=for-the-badge" alt="License: Apache 2.0"></a>
  <a href="#설치"><img src="https://img.shields.io/badge/macOS-14%2B-black.svg?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 14+"></a>
  <a href="docs/development.md"><img src="https://img.shields.io/badge/Swift-6-F05138.svg?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6"></a>
  <a href="#프라이버시"><img src="https://img.shields.io/badge/Network-none-2ea44f.svg?style=for-the-badge" alt="Network: none"></a>
  <a href="https://github.com/silex-ai-lab/silex_vibra/stargazers"><img src="https://img.shields.io/github/stars/silex-ai-lab/silex_vibra?style=for-the-badge" alt="GitHub stars"></a>
</p>

<p align="center">
  <a href="#빠른-시작">빠른 시작</a> · <a href="#지원하는-에이전트">지원하는 에이전트</a> · <a href="#프라이버시">프라이버시</a> · <a href="#설계-원칙">설계 원칙</a>
  <br>
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · 한국어
</p>

---

영어 README가 기준 문서이며, 이 번역은 최신 내용보다 늦을 수 있습니다.

Claude Code, Codex, Cursor, VS Code(Copilot Chat), OpenCode, Hermes
세션 중 어떤 것이 작업 중인지, 어느 것이 당신 차례를 기다리는지, 어느 것이
승인이 필요한지를 보여 주는 macOS 메뉴 막대 앱입니다. 상태를 보고할 수 있는
에이전트에 한합니다. 자세한 내용은 [지원하는 에이전트](#지원하는-에이전트). 오픈 소스(Apache 2.0).
로컬 전용: 계정 없음, 원격 측정 없음, 네트워크 없음.

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

## 왜 Vibra인가

에이전트는 한 번에 몇 분씩 작업합니다. 비싼 실패는 충돌이 아니라,
4분 전에 끝난 에이전트가 당신이 보고 있지 않은 터미널 탭에서
계속 당신을 기다리는 상황입니다. Vibra는
에이전트가 이미 기록하는 세션 파일을 지켜보고, 당신이 필요한 세션을 찾아 보여 줍니다.

- 🟠 **에이전트가 턴을 마쳤다** → 그 상태를 보고할 수 있는 에이전트라면 해당 행이 🟠 당신 차례로 바뀌고 알림이 옵니다. 더 이상 사실이 아니면 알림은 철회됩니다.
- 🔴 **에이전트가 권한 프롬프트에 멈춰 있다** → 그 상태를 보고할 수 있는 에이전트라면 해당 행이 🔴 승인 필요로 바뀝니다. Vibra는 그것을 보여 주기만 하고 결코 대신 승인하지 않습니다.
- 🖱️ **거기로 돌아가고 싶다** → 에이전트가 허용하는 범위에서 클릭하면 해당 세션으로 이동합니다. 자세한 내용은 [기능](#기능).
- 🧾 **작업이 무엇을 사용했는지 알고 싶다** → **Usage Report…**(⌘U)가 7일간의 토큰과 API 환산 가치를 보여 줍니다.

### ✅ 설치하기 전에

| | |
|---|---|
| 💰 **무료 오픈 소스** | Apache License 2.0. |
| 🔒 **로컬 전용** | 네트워크 전송이 전혀 없습니다. 계정 없음, 원격 측정 없음, 업데이트 확인 없음. |
| 🧩 **에이전트에 아무것도 설치하지 않음** | 훅, 플러그인, 상태 표시줄, 래퍼 바이너리가 없습니다. |
| 🤖 **6개 에이전트** | 모든 에이전트가 모든 상태를 보고할 수 있는 것은 아닙니다. 자세한 내용은 [지원하는 에이전트](#지원하는-에이전트). |
| 🩺 **자가 점검** | 클론한 저장소에서 `make probe`를 실행하면 세션과 상태를 출력하며, 메시지 내용은 절대 출력하지 않습니다. |
| ⚠️ **소스에서 빌드** | 아직 내려받을 수 있는 앱이 없습니다. Vibra는 ad-hoc 서명이며 공증되지 않아, 알림에는 '시스템 설정'에서 한 번 수동으로 설정해야 합니다. |

## 지원하는 에이전트

| Agent guide | Covers | 🔵 | 🟠 | 🔴 | 🟡 | ⚪️ |
|---|---|---|---|---|---|---|
| <img src="docs/assets/agents/claudecode.svg" width="16" height="16" alt="Claude Code"> [Claude Code](docs/agents/claude-code.md) | CLI, Claude 데스크톱 앱, VS Code / Cursor 확장 | ✓ | ✓ | ✓ | ✓ | ✓ |
| <img src="docs/assets/agents/codex.svg" width="16" height="16" alt="Codex"> [Codex](docs/agents/codex.md) | CLI, `codex exec`, 데스크톱 앱, IDE 확장 | live | live | — | ✓ | ✓ |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/cursor-for-dark.svg"><img src="docs/assets/agents/cursor-for-light.svg" width="16" height="16" alt="Cursor"></picture> [Cursor](docs/agents/cursor.md) | Agents 창과 편집기 채팅 | live | ✓ | ✓ | — | live |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/githubcopilot-for-dark.svg"><img src="docs/assets/agents/githubcopilot-for-light.svg" width="16" height="16" alt="GitHub Copilot"></picture> [VS Code](docs/agents/vscode.md) | GitHub Copilot Chat(Ask, Edit, Agent 모드), Insiders 포함 | live | live | live | ✓ | live |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/opencode-for-dark.svg"><img src="docs/assets/agents/opencode-for-light.svg" width="16" height="16" alt="OpenCode"></picture> [OpenCode](docs/agents/opencode.md) | DeepSeek 포함 | ✓ | — | ✓ | — | ✓ |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/hermesagent-for-dark.svg"><img src="docs/assets/agents/hermesagent-for-light.svg" width="16" height="16" alt="Hermes Agent"></picture> [Hermes](docs/agents/hermes.md) | CLI 및 채팅 게이트웨이 | ✓ | ✓ | — | ✓ | ✓ |

**live**: 기록된 라이브 세션에서 관찰됨. **✓**: 표시할 수 있지만 라이브 기록은 아직 없음(가이드에
픽스처 테스트가 다루는지 설명). **—**: 표시되지 않음(예: Codex/Hermes에는 승인 상태 없음).

### 세션 상태

| 상태 | 의미 |
|---|---|
| 🔵 작업 중 (working) | 출력을 생성 중입니다. 그대로 두세요. |
| 🟠 당신 차례 (your turn) | 턴이 끝나 당신을 기다립니다. |
| 🔴 승인 필요 (needs approval) | 권한 프롬프트에 멈춰 있습니다. |
| 🟡 정체됨 (stalled) | 턴 중이라고 했다가 조용해졌습니다. |
| ⚪️ 유휴 (idle) | 정리되었고 대기 중인 것이 없습니다. |

## 기능

- **메뉴 막대에서 모든 세션의 상태 표시**, 프로젝트와 토큰 포함.
- **필요할 때 알림**(🟠 또는 🔴), 더 이상 사실이 아니면 철회됩니다.
  클릭하면 해당 세션으로 이동합니다. Claude Code와 Codex는 터미널 탭(iTerm2, Terminal, herdr) 또는 호스트 앱,
  VS Code는 창, Cursor는 앞으로 가져옵니다.
  OpenCode와 Hermes 세션은 이동할 수 없습니다.
- **작업이 무엇을 사용하고 무엇을 물었는지.** **Usage Report…**(⌘U): 7일간의 토큰과
  API 환산 가치, 날짜는 Claude Code와 Codex만 제공. **History…**(⌘Y):
  당신이 물은 질문. `--query`: 메뉴를 JSON으로 출력. 자세한 내용은 [기능](docs/features.md).

## 빠른 시작

### 설치

**macOS 14+**와 Swift 6 툴체인이 필요합니다. **Xcode는 필요하지 않습니다** —
Command Line Tools로 충분합니다:

```sh
xcode-select --install     # skip if `swift --version` already works
```

그다음:

```sh
git clone https://github.com/silex-ai-lab/silex_vibra.git
cd silex_vibra
make install               # builds, then copies to /Applications
open /Applications/Vibra.app
```

`make install`은 실행 중인 복사본을 먼저 종료하므로, 변경 사항을 가져온 뒤
다시 실행해도 안전합니다.

Dock 아이콘도 창도 없습니다 — `LSUIElement`가 설정되어 있어 **메뉴 막대
항목이 앱의 전부**입니다. 메뉴 막대 오른쪽에서
`Vibra` 또는 세션이 살아 있을 때 `2▶ 1!` 같은 숫자를 찾으세요.

완전히 제거하려면:

```sh
make uninstall
```

### 첫 실행

macOS가 앱이 확인되지 않은 개발자로부터 왔다고 경고할 수 있습니다. 이것은 ad-hoc
서명이며 Developer ID 서명이 아닙니다. Finder에서 앱을 오른쪽 클릭하고
**열기**를 한 번 선택하거나 다음을 실행하세요:

```sh
xattr -dr com.apple.quarantine /Applications/Vibra.app
```

아직 내려받을 수 있는 앱이 없습니다. Vibra는 ad-hoc 서명이며 공증되지 않아
알림에는 '시스템 설정'에서 한 번 수동으로 설정해야 합니다 — 자세한 내용은
[문제 해결](docs/troubleshooting.md#troubleshooting).

### 첫 2분

1. Vibra를 엽니다. 12시간 동안 아무것도 실행하지 않았다면 `No active sessions`로 표시됩니다. 정상입니다.
2. 터미널에서 대화형 **Claude Code** 또는 **Codex** 세션을 시작하고
   작업을 부여하세요. 해당 행에 🔵 작업 중이 표시됩니다.
3. 턴이 끝나게 두세요. 행이 🟠 당신 차례로 바뀌고 메뉴 막대에 `1!`가 표시됩니다.

메뉴 없이: 클론한 저장소에서 `make probe`를 실행하면 세션과 상태를 출력하고,
메시지 내용은 출력하지 않습니다. 아무것도 찾지 못하면 `2`로 종료합니다.

## 설계 원칙

- **수동적 읽기 도구.** Vibra는 이 도구들에게 기록 내용을 바꾸라고 요구하지 않습니다.
  이미 존재하는 파일을 수동적으로 읽습니다.
- **보여 주기만 하고 행동하지 않음.** 에이전트의 권한 프롬프트를 대신 승인하지 않습니다. 보여 주기만 합니다.
- **본 것을 그대로 말함.** 위 표는 기록된 라이브 세션에서 관찰한 상태(**live**)와
  코드가 표시할 수 있지만 라이브 기록이 아직 없는 상태(**✓**)를 구분합니다.

## 프라이버시

Vibra는 로컬 파일을 읽고 아무 데도 전송하지 않습니다 — 에이전트가 이미 기록하는
세션 파일과 데이터베이스를 수동적으로 읽습니다(경로는 각 가이드 참조).

- **네트워크 전송이 전혀 없습니다.** 계정 없음, 원격 측정 없음, 업데이트 확인 없음.
- **에이전트에 아무것도 설치하지 않습니다** — 훅, 플러그인,
  상태 표시줄, 래퍼 바이너리가 없습니다.
- OpenCode와 Cursor의 데이터베이스에는 인증 토큰이 있습니다. 각각 읽기 전용으로 열고
  하드코딩된 `SELECT` 하나만 실행하며, 토큰 테이블은 조회하지 않습니다.
- `--query`, `--probe` 및 기타 기계 판독 출력에는
  메시지 텍스트가 포함되지 않습니다. 입력한 내용을 보여 주는 유일한 기능인 History는
  창이 열려 있는 동안에만 메모리에 보관하고 아무것도 기록하지 않습니다.
- 에이전트의 권한 프롬프트를 대신 승인하지 않습니다. 보여 주기만 합니다.

**카나리 테스트**는 픽스처에 감시용 비밀과 메시지 텍스트를 심고, 반환되는
세션, JSON, `--query` 출력 또는 오류에 나타나지 않음을 검증합니다(어댑터별). OpenCode
토큰 카나리가 실행되지 않으면 `make test`가 실패합니다. 자세한 내용: [docs/privacy.md](docs/privacy.md).

## ⭐ Star할 이유

저도 매일 Vibra로 제 에이전트들을 지켜보고 있어서 계속 유지보수합니다.

- 새 에이전트나, 이미 지원하는 에이전트의 새 상태를 원하는 분이 있으면 차례로 추가합니다
- 모든 에이전트를 **무료로, 로컬에서만, 제대로 동작하게** 유지합니다. 계정도 유료 버전도 없고 아무것도 외부로 보내지 않습니다
- 에이전트는 Vibra가 읽는 세션 파일의 형식을 자주 바꿉니다. 업데이트로 읽지 못하게 되면 제가 어댑터를 고치니, 직접 챙기지 않아도 됩니다

이유가 더 있습니다:

- 🔒 **프라이버시는 약속이 아니라 테스트로 지킵니다**: 카나리 테스트가 가짜 비밀 정보와 메시지 본문을 심어 두고, 그중 하나라도 Vibra의 출력에 나오면 빌드가 실패합니다
- 🧾 **되는 것만 정직하게 표시합니다**: 호환성 표에서 실제 세션에서 확인한 상태(**live**)와, 코드로는 표시할 수 있지만 아직 아무도 확인하지 못한 상태(**✓**)를 구분합니다. 확인된 상태가 늘어날 때마다 표를 업데이트합니다
- 🧩 **기존 설정을 건드리지 않습니다**: 에이전트에 hook·플러그인·래퍼를 추가하지 않고, `make uninstall`로 앱을 삭제할 수 있습니다
- 🌏 **4개 언어 README**: English·简体中文·日本語·한국어
- 📣 **다른 사람이 찾기 쉬워집니다**: Star가 있으면 여러 에이전트를 동시에 돌리는 사람이 Vibra를 더 쉽게 찾을 수 있습니다

에이전트가 한참 기다리고 있는데 몰랐던 순간, 다음에 Vibra를 바로 찾을 수 있도록 Star해 두세요. ⭐

## 더 보기 및 기여

[기능](docs/features.md) · [문제 해결 및 제한 사항](docs/troubleshooting.md) ·
[개발](docs/development.md) · [변경 내역](CHANGELOG.md) · [로드맵](docs/ROADMAP.md)

이슈와 풀 리퀘스트를 환영합니다. 테스트는 `make test`로 실행하세요 —
`swift test`는 안 됩니다. Xcode가 없는 머신에서는 테스트가 하나도 실행되지 않습니다.

## 라이선스

[Apache License 2.0](LICENSE)

호환성 표의 에이전트 마크는 [docs/assets/agents/ATTRIBUTION.md](docs/assets/agents/ATTRIBUTION.md)를 참조하세요.
