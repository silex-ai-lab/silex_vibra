<h1 align="center">📳 Vibra</h1>

<p align="center">
  <strong>コーディングエージェントがあなたを必要とする瞬間に気づける。</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=for-the-badge" alt="License: Apache 2.0"></a>
  <a href="#インストール"><img src="https://img.shields.io/badge/macOS-14%2B-black.svg?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 14+"></a>
  <a href="docs/development.md"><img src="https://img.shields.io/badge/Swift-6-F05138.svg?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6"></a>
  <a href="#プライバシー"><img src="https://img.shields.io/badge/Network-none-2ea44f.svg?style=for-the-badge" alt="Network: none"></a>
  <a href="https://github.com/silex-ai-lab/silex_vibra/stargazers"><img src="https://img.shields.io/github/stars/silex-ai-lab/silex_vibra?style=for-the-badge" alt="GitHub stars"></a>
</p>

<p align="center">
  <a href="#クイックスタート">クイックスタート</a> · <a href="#対応エージェント">対応エージェント</a> · <a href="#プライバシー">プライバシー</a> · <a href="#設計原則">設計原則</a>
  <br>
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · 日本語 · <a href="README.ko.md">한국어</a>
</p>

---

英語版 README が正式な内容です。この翻訳は遅れる場合があります。

macOS のメニューバーアプリです。Claude Code、Codex、Cursor、
VS Code（Copilot Chat）、OpenCode、Hermes のセッションのうち、どれが作業中で、
どれがあなたの番を待っているか、どれが承認を必要としているかを表示します——それらの状態を
報告できるエージェントに限ります。詳細は [対応エージェント](#対応エージェント)。オープンソース（Apache 2.0）。
ローカル専用：アカウントなし、テレメトリなし、ネットワークなし。

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

## なぜ Vibra なのか

エージェントは何分もかけて作業します。コストの高い失敗はクラッシュではなく、
4 分前に作業を終えたエージェントが、あなたが見ていない
ターミナルタブであなたを待ち続けていることです。Vibra は
エージェントがすでに書き出しているセッションファイルを監視し、あなたを必要とするものを浮かび上がらせます。

- 🟠 **エージェントがターンを終えた** → その状態を報告できるエージェントでは、行が 🟠 あなたの番になり、通知が届きます。当てはまらなくなると通知は取り下げられます。
- 🔴 **エージェントが許可プロンプトで止まっている** → その状態を報告できるエージェントでは、行が 🔴 承認が必要になり、Vibra はそれを表示するだけで、あなたに代わって承認することはありません。
- 🖱️ **そこに戻りたい** → エージェントが許す範囲で、クリックするとジャンプします。詳細は [できること](#できること)。
- 🧾 **作業が何を使ったか知りたい** → **Usage Report…**（⌘U）が 7 日分のトークンと API 換算値を表示します。

### ✅ インストール前に

| | |
|---|---|
| 💰 **無料でオープンソース** | Apache License 2.0。 |
| 🔒 **ローカル専用** | ネットワーク送信は一切ありません。アカウントなし、テレメトリなし、更新確認なし。 |
| 🧩 **エージェントに何もインストールしない** | フック、プラグイン、ステータスライン、ラッパーバイナリはありません。 |
| 🤖 **6 つのエージェント** | すべてのエージェントがすべての状態を報告できるわけではありません。詳細は [対応エージェント](#対応エージェント)。 |
| 🩺 **セルフチェック** | クローンしたリポジトリで `make probe` を実行すると、セッションと状態が表示され、メッセージ内容は表示されません。 |
| ⚠️ **ソースからビルド** | ダウンロードできるアプリはまだありません。Vibra は ad-hoc 署名で、公証されていないため、通知には「システム設定」での手動操作が 1 回必要です。 |

## 対応エージェント

| Agent guide | Covers | 🔵 | 🟠 | 🔴 | 🟡 | ⚪️ |
|---|---|---|---|---|---|---|
| <img src="docs/assets/agents/claudecode.svg" width="16" height="16" alt="Claude Code"> [Claude Code](docs/agents/claude-code.md) | CLI、Claude デスクトップアプリ、VS Code / Cursor 拡張機能 | ✓ | ✓ | ✓ | ✓ | ✓ |
| <img src="docs/assets/agents/codex.svg" width="16" height="16" alt="Codex"> [Codex](docs/agents/codex.md) | CLI、`codex exec`、デスクトップアプリ、IDE 拡張機能 | live | live | — | ✓ | ✓ |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/cursor-for-dark.svg"><img src="docs/assets/agents/cursor-for-light.svg" width="16" height="16" alt="Cursor"></picture> [Cursor](docs/agents/cursor.md) | Agents ウィンドウとエディターのチャット | live | ✓ | ✓ | — | live |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/githubcopilot-for-dark.svg"><img src="docs/assets/agents/githubcopilot-for-light.svg" width="16" height="16" alt="GitHub Copilot"></picture> [VS Code](docs/agents/vscode.md) | GitHub Copilot Chat（Ask、Edit、Agent モード）、Insiders にも対応 | live | live | live | ✓ | live |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/opencode-for-dark.svg"><img src="docs/assets/agents/opencode-for-light.svg" width="16" height="16" alt="OpenCode"></picture> [OpenCode](docs/agents/opencode.md) | DeepSeek を含む | ✓ | — | ✓ | — | ✓ |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/agents/hermesagent-for-dark.svg"><img src="docs/assets/agents/hermesagent-for-light.svg" width="16" height="16" alt="Hermes Agent"></picture> [Hermes](docs/agents/hermes.md) | CLI とチャットゲートウェイ | ✓ | ✓ | — | ✓ | ✓ |

**live**：記録されたライブセッションで確認済み。**✓**：表示可能だがライブ記録はまだない（ガイドに
フィクスチャテストでカバーしているか記載）。**—**：表示されない（例：Codex/Hermes に承認状態なし）。

### セッションの状態

| 状態 | 意味 |
|---|---|
| 🔵 作業中 (working) | 出力を生成しています。そのままにしてください。 |
| 🟠 あなたの番 (your turn) | ターンが終わり、あなたを待っています。 |
| 🔴 承認が必要 (needs approval) | 許可プロンプトで止まっています。 |
| 🟡 停滞 (stalled) | ターン中のはずが、その後音信不通です。 |
| ⚪️ アイドル (idle) | 落ち着いており、保留はありません。 |

## できること

- **メニューバーに各セッションの状態を表示**、プロジェクトとトークン付き。
- **必要なときに通知**（🟠 または 🔴）。当てはまらなくなると取り下げられます。
  クリックするとジャンプします。Claude Code と Codex はターミナルタブ（iTerm2、Terminal、herdr）またはホストアプリ、
  VS Code はウィンドウ、Cursor は前面に表示されます。
  OpenCode と Hermes のセッションにはジャンプできません。
- **作業が何を使い、何を尋ねたか。** **Usage Report…**（⌘U）：7 日分のトークンと
  API 換算値。日付は Claude Code と Codex のみ。**History…**（⌘Y）：
  あなたが尋ねた質問。`--query`：メニューを JSON で出力。詳細は [機能](docs/features.md)。

## クイックスタート

### インストール

**macOS 14+** と Swift 6 ツールチェーンが必要です。**Xcode は不要** ——
Command Line Tools で十分です：

```sh
xcode-select --install     # skip if `swift --version` already works
```

次に：

```sh
git clone https://github.com/silex-ai-lab/silex_vibra.git
cd silex_vibra
make install               # builds, then copies to /Applications
open /Applications/Vibra.app
```

`make install` は実行中のコピーを先に終了するので、変更を取り込んだ後に
再実行しても安全です。

Dock アイコンもウィンドウもありません —— `LSUIElement` が設定されているため、**メニューバーの
項目がアプリのすべて**です。メニューバーの右側で
`Vibra`、またはセッションが動いているときは `2▶ 1!` のようなカウントを探してください。

完全に削除するには：

```sh
make uninstall
```

### 初回起動

macOS が「開発元を確認できません」と警告する場合があります。これは ad-hoc
署名で、Developer ID 署名ではないためです。Finder でアプリを右クリックし、
**開く** を一度選ぶか、次を実行します：

```sh
xattr -dr com.apple.quarantine /Applications/Vibra.app
```

ダウンロードできるアプリはまだありません。Vibra は ad-hoc 署名で公証されていないため、
通知には「システム設定」での手動操作が 1 回必要です —— 詳しくは
[トラブルシューティング](docs/troubleshooting.md#troubleshooting)。

### 最初の 2 分

1. Vibra を開きます。12 時間何も実行していなければ `No active sessions` と表示されます。これは想定どおりです。
2. ターミナルで対話型の **Claude Code** または **Codex** セッションを開始し、
   タスクを与えます。その行に 🔵 作業中と表示されます。
3. ターンを終えさせます。行が 🟠 あなたの番になり、メニューバーに `1!` と表示されます。

メニューを使わない場合：クローンしたリポジトリで `make probe` を実行すると、セッションと状態を表示し、
メッセージ内容は表示しません。何も見つからなければ `2` で終了します。

## 設計原則

- **受動的な読み取り手。** Vibra はこれらのツールに書き込み内容の変更を求めません。
  すでに存在するファイルの受動的な読み取り手です。
- **表示するだけで、行動しない。** エージェントの許可プロンプトをあなたに代わって承認することはありません。表示するだけです。
- **見たことをそのまま示す。** 上の表は、記録されたライブセッションで観察された状態（**live**）と、
  コードが表示できてもライブ記録がまだない状態（**✓**）を区別します。

## プライバシー

Vibra はローカルファイルを読み取り、どこにも送信しません —— エージェントがすでに書き出している
セッションファイルとデータベースの受動的な読み取り手です（パスは各ガイドに記載）。

- **ネットワーク送信は一切ありません。** アカウントなし、テレメトリなし、更新確認なし。
- **エージェントには何もインストールしません** —— フック、プラグイン、
  ステータスライン、ラッパーバイナリはありません。
- OpenCode と Cursor のデータベースには認証トークンが含まれます。いずれも読み取り専用で開き、
  ハードコードされた `SELECT` を 1 つだけ実行し、トークンテーブルは決して参照しません。
- `--query`、`--probe` などの機械可読出力には
  メッセージ本文が含まれません。入力内容を表示する唯一の機能である History は、
  ウィンドウを開いている間だけメモリに保持し、何も書き込みません。
- エージェントの許可プロンプトをあなたに代わって承認することはありません。表示するだけです。

**カナリアテスト** はフィクスチャに番兵のシークレットとメッセージ本文を仕込み、返される
セッション、その JSON、`--query` 出力、エラーに含まれないことを検証します（アダプターごと）。OpenCode の
トークンカナリアが実行されなければ `make test` は失敗します。詳細：[docs/privacy.md](docs/privacy.md)。

## ⭐ Star する価値

私自身、毎日 Vibra で自分のエージェントを見張っています。だからメンテナンスを続けます。

- 新しいエージェントや、対応済みエージェントの新しい状態を求める声があれば、順次追加します
- どのエージェントも**無料・ローカル完結・確実に動く**状態を保ちます。アカウント不要、有料版なし、外部への送信なし
- エージェントは、Vibra が読むセッションファイルの形式をよく変えます。アップデートで読めなくなったらアダプターを直すので、あなたが追いかける必要はありません

さらに：

- 🔒 **プライバシーは約束ではなくテストで守る**：カナリアテストが偽の秘密情報とメッセージ本文を仕込み、そのどれかが Vibra の出力に出ればビルドが失敗します
- 🧾 **できることを正直に書く**：互換性テーブルでは、実際のセッションで確認した状態（**live**）と、コード上は表示できるがまだ誰も確認していない状態（**✓**）を分けています。確認できる状態が増えるたびに表を更新します
- 🧩 **あなたの環境に手を加えない**：エージェントに hook・プラグイン・ラッパーを追加せず、`make uninstall` でアプリを削除できます
- 🌏 **4 言語の README**：English・简体中文・日本語・한국어
- 📣 **ほかの人が見つけやすくなる**：Star があると、複数のエージェントを同時に動かしている人が Vibra を見つけやすくなります

エージェントがずっと待っているのに気づかなかった——次にそうなったとき見つけられるよう、Star しておいてください。⭐

## 詳細とコントリビュート

[機能](docs/features.md) · [トラブルシューティングと制限](docs/troubleshooting.md) ·
[開発](docs/development.md) · [変更履歴](CHANGELOG.md) · [ロードマップ](docs/ROADMAP.md)

Issue と Pull Request を歓迎します。テストは `make test` で実行してください ——
`swift test` は不可です。Xcode のないマシンではテストが 1 つも実行されません。

## ライセンス

[Apache License 2.0](LICENSE)

互換性テーブルのエージェントマークについては [docs/assets/agents/ATTRIBUTION.md](docs/assets/agents/ATTRIBUTION.md) を参照してください。
