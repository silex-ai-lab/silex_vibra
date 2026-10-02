# Plan — README restyle on the Agent Reach template + translated READMEs (2026-10-01)

**Owner request (verbatim):** "以 https://github.com/Panniantong/Agent-Reach README
为模版改写一下 vibra 的README，可以网络搜索一些图标嫁过来，加上多语言README，etc。"
(Rewrite Vibra's README using the Agent Reach README as the template; search the
web for icons to graft in; add multi-language READMEs.)

**Status:** v3, plan gate passed (round 3, unanimous).

**Plan-gate verdicts on v3:** coder-deepseek `PLAN-APPROVED` · reviewer-codex `PLAN-APPROVED` · PLANNER (claude): PLAN-APPROVED
**Branch:** `readme-agent-reach-style` (local). **BASE:** `6840769bed96092e2b36e57d856397e554939282` (= `origin/main`).

## Roster

Run with the `herdr-agent-fleet` workflow. Both gates unanimous.

| Seat | Agent |
|---|---|
| planner | Claude Code (Opus 5.5) |
| coder-deepseek | OpenCode, `deepseek/deepseek-flash` (DeepSeek V4.1 Flash) |
| reviewer-codex (third judge) | Codex CLI 0.159.3 |

## Decisions this plan makes (reviewers: object if wrong)

1. **The owner's request overrides one line of the growth plan.**
   `plan/OSS-GROWTH-PLAN.md` "Sequence 4. Not doing: … translated READMEs".
   The owner now asks for them. P5 records the reversal in the growth plan and
   `plan/STATUS.md`; nothing else in the growth plan changes.
2. **English stays the primary `README.md`.** Agent Reach is Chinese-first with
   `docs/README_en.md`; Vibra's audience and every linked doc are English, so
   only the *shape* of the template is copied, not its language order.
3. **Translations: Simplified Chinese, Japanese, Korean** — the same three
   extra languages Agent Reach ships (`README_en/ja/ko`). Files at the repo root:
   `README.zh-CN.md`, `README.ja.md`, `README.ko.md` (GitHub convention, same
   relative links as `README.md`, so no link rewriting). Each starts with one
   line saying the English README is authoritative and this copy may lag.
   Linked docs (`docs/*.md`) stay English-only; translations link to them as-is.
4. **No hero image or GIF.** Growth-plan #2 still requires a real recording; no
   placeholder. The ASCII menu sketch stays as the first visual.
5. **Icons:** vendored into the repo (`docs/assets/agents/`), never hot-linked,
   so the README does not depend on a third-party CDN.
   - Source: **Lobe Icons** (`@lobehub/icons-static-svg` 1.95.1, MIT) — the
     only checked set that has all needed marks. Simple Icons (CC0) has no
     OpenAI/Codex and no VS Code mark (both 404 on `cdn.simpleicons.org`,
     checked 2026-10-01). Lobe has `codex`, `claudecode`, `cursor`,
     `githubcopilot`, `opencode`, `hermesagent`; it has no `vscode`.
   - **VS Code row uses the GitHub Copilot mark**, because the thing Vibra
     watches there is Copilot Chat (the row already says so). No Microsoft
     VS Code logo is copied.
   - Mono icons use `fill="currentColor"`, which renders black inside `<img>`
     and vanishes in GitHub dark mode. So each mono icon is vendored as a
     `-light.svg` / `-dark.svg` pair with a fixed fill (`#1f2328` / `#e6edf3`)
     and shown with `<picture><source media="(prefers-color-scheme: dark)">`.
     Colour icons (`codex-color`, `claudecode-color`) ship once.
   - **Pair naming (pinned):** `<name>-for-light.svg` has `fill="#1f2328"`
     (shown on light backgrounds), `<name>-for-dark.svg` has `fill="#e6edf3"`.
     Colour icons are `<name>.svg`. Recolouring = replacing the root
     `fill="currentColor"` only; paths are untouched.
   - **Licence:** the full upstream `LICENSE` of `lobehub/lobe-icons` (MIT,
     "Copyright (c) 2023 LobeHub", fetched from the GitHub repo — the npm
     package ships none) is vendored verbatim as
     `docs/assets/agents/LICENSE-lobe-icons.txt`.
     `docs/assets/agents/ATTRIBUTION.md` lists, per vendored SVG: upstream
     file URL (unpkg, pinned `@1.95.1`), sha256 of the upstream file, and
     whether/how it was recoloured; points to the licence file; and carries
     the trademark note: marks belong to their owners, are used only to
     identify which agent a table row describes, and imply no endorsement;
     the GitHub Copilot mark identifies GitHub Copilot Chat, not VS Code;
     and these marks and `LICENSE-lobe-icons.txt` are **not** covered by the
     repository's Apache-2.0 licence.
   - `alt` text names the product the mark belongs to (`alt="GitHub Copilot"`
     on the VS Code row). Size cap: each SVG ≤ 25 KB (hermesagent ~19.8 KB).
   - The README does not link ATTRIBUTION from the front page; the License
     section gains one line: "Agent marks in the compatibility table: see
     [docs/assets/agents/ATTRIBUTION.md](docs/assets/agents/ATTRIBUTION.md)."
6. **Badges** (shields.io, `for-the-badge` like the template), pinned:
   - `https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=for-the-badge` → `LICENSE`
   - `https://img.shields.io/badge/macOS-14%2B-black.svg?style=for-the-badge&logo=apple&logoColor=white` → `#install`
   - `https://img.shields.io/badge/Swift-6-F05138.svg?style=for-the-badge&logo=swift&logoColor=white` → `docs/development.md`
   - `https://img.shields.io/badge/Network-none-2ea44f.svg?style=for-the-badge` → `#privacy` (the claim is the base README's "no network")
   - `https://img.shields.io/github/stars/silex-ai-lab/silex_vibra?style=for-the-badge` → `https://github.com/silex-ai-lab/silex_vibra/stargazers` No Trendshift / star-history badges (not
   earned; they would be claims). No sponsor section (there are none).
7. **Line budget:** the Day-1 "< 150 lines" target is relaxed to **< 220
   lines** for `README.md`, because centred HTML blocks and the icon table cost
   lines. Content moved to `docs/` on Day 1 stays there; nothing moves back.

## Target structure of `README.md` (mirrors Agent Reach section by section)

| # | Agent Reach section | Vibra section | Content source |
|---|---|---|---|
| 1 | Centred `<h1>` + bold tagline + subtitle | `📳 Vibra`; **Know when your coding agents need you.**; subtitle = current README lines 3–7 (agents list + "for the agents that can report it" + Apache 2.0 / local-only line) | base README |
| 2 | Badge row | Badges per decision 6 | — |
| 3 | Nav line + language links | Quick start · Supported agents · Privacy · Design principles · **English · 简体中文 · 日本語 · 한국어** | — |
| 4 | — (template has sponsor block) | ASCII menu sketch, verbatim | base README 9–21 |
| 5 | "Why do you need it?" pain list (`📺 "…" → can't`) | **Why Vibra?** 4–5 emoji bullets of the form *situation → what happens without Vibra*, each restating a sentence of base "Who it is for" (lines 23–28) or "What it does" — no new facts | base README |
| 6 | "Before you use it" 2-col table (💰 🔒 🔄 🤖 🩺) | **Before you install** table: 💰 free/Apache 2.0 · 🔒 no network, no account, no telemetry · 🧩 installs nothing into your agents · 🤖 six agents, see table · 🩺 `make probe` self-check · ⚠️ source build only, ad-hoc signed, one manual notification step | base README Install/Privacy, docs/troubleshooting.md |
| 7 | "Supported platforms" table | **Supported agents**: the base compatibility table **cells verbatim**, plus an icon `<picture>` in the first column; legend lines verbatim | base README 51–63 |
| 8 | — | **Session states** table verbatim | base README 41–49 |
| 9 | "Ready to use" bullets | **What it does**: the three base bullets verbatim | base README 30–39 |
| 10 | "Quick start" | **Quick start** (`## Quick start`) with subsections `### Install`, `### First launch`, `### Your first two minutes` (headings pinned; the macOS badge targets `#install`) — commands and sentences verbatim | base README 65–118 |
| 11 | "Design philosophy" | **Design principles**: 3–4 bullets, each sourced: passive reader / installs nothing (docs/privacy.md); never approves for you (base README Privacy); "live" vs "✓" claim discipline (base legend); local-only (privacy) | as listed |
| 12 | — | **Privacy**: bullets + canary paragraph verbatim | base README 120–137 |
| 13 | Footer | **More and contributing** verbatim; **License** verbatim plus the one ATTRIBUTION line from decision 5 (listed in the Claim table) | base README 139–149 |

**Claim rule.** Every factual sentence in the new README is either verbatim
from the base README / `docs/privacy.md`, or a strictly narrower restatement
of one. P1 (done **inside F1**, while the README is written) appends a
"new sentence → source (file:line)" table to this plan's **Claim table**
section; C8 enforces it. **Section 5 "Why Vibra?"** is the highest overreach
risk, so each of its bullets must restate one specific sentence of base
"Who it is for" (23–28) or "What it does" (30–39), cited in the claim table,
and may not name an agent capability beyond that sentence (e.g. no jump for
OpenCode/Hermes, no 🔴 for Codex/Hermes). Tables and fenced code blocks from the
base README appear byte-identical (after whitespace normalisation), except the
compatibility table's first column, which gains the icon.

## Translation contract (D1)

- Translate the **frozen** `README.md` from the foundation commit (F1). Same
  section order, same heading count, same table rows and columns, same badges,
  same icon `<picture>` blocks (paths unchanged), same link targets. Fragment-
  only links (`#…`) that target a README heading are rewritten to the
  translated heading's GitHub slug; fragments into English-only docs
  (e.g. `docs/troubleshooting.md#troubleshooting`) stay unchanged.
- Compatibility table: agent order, header row (state emoji) and every cell
  in columns 3–7 byte-identical to English; column 2 ("Covers") translated.
- **Untranslated, byte-identical:** fenced code blocks, commands, paths, file
  names, menu items as they appear in the app (`Usage Report…`, `History…`,
  `No active sessions`), keyboard shortcuts, product and agent names, emoji,
  table cells `✓` / `live` / `—`. The legend explains `live` in the target
  language but keeps the token `live`.
- State names: translated, with the English app label in parentheses on first
  use in the states table (e.g. `🟠 轮到你 (your turn)`), because the app UI is
  English.
- No added or dropped claims. No marketing adjectives not in the English.
- Language-link line in each file marks its own language as current (plain
  text, not a link) and links the other three.
- Line 1 under the title: the "English is authoritative, may lag" note in the
  target language.

## Tasks and file ownership

Exclusive ownership; report a needed change to the owner instead of making it.

| # | Owner | Task | Files | Acceptance |
|---|---|---|---|---|
| F1 | planner | **Foundation, first, alone:** vendor icons + licence + ATTRIBUTION; write the new `README.md` and the claim table (P1); checkpoint-commit on the branch | `docs/assets/agents/*`, `README.md`, this file | foundation set **F-set** = C1(README part), C2, C3 (README.md only, links to the three translation files exempt until D1), C4, C8 |
| D1 | deepseek | Three translations of the F1 `README.md` per the contract | `README.zh-CN.md`, `README.ja.md`, `README.ko.md` | C3–C7 |
| X1 | reviewer-codex | **Build slice:** write the probe runner `$SCRATCH/probes/readme_probes.py` (outside the repo) implementing C1–C8 with a `--foundation` mode (F-set) and a full mode; run it; report failures. Delivered **before F1 is checked**, so it gates F1 too | scratch only | negative controls N1–N4 each make it fail |
| P5 | planner | Record the "translated READMEs" reversal + this run: growth plan, STATUS, CHANGELOG `Unreleased` entry | `plan/OSS-GROWTH-PLAN.md`, `plan/STATUS.md`, `CHANGELOG.md` | in reviewed diff |

Sequence: plan gate → X1 (Codex) and F1 (planner) in parallel → F-set green
(`--foundation`) → F1 checkpoint commit → D1 (DeepSeek) translates the frozen
README, P5 by planner → full C1–C8 green → headless render check (planner: GitHub-flavoured render via
`gh api markdown` of each README, screenshot light + dark) → code gate on
`git diff $BASE` → local commit.
**Probe independence:** X1 implements the probe *spec in this plan*, which all
three seats approve; the runner source is part of the code-gate package, and
the planner and DeepSeek review it there. **Semantic translation review:**
probes cannot prove "no claim added or dropped". At the code gate, Codex and
the planner each read every translation against English for: the live/✓/—
legend, source-only install + ad-hoc signing + the manual notification step,
every Privacy promise, and the jump restrictions (none for OpenCode/Hermes). **Push to `origin/main` only with the
owner's go-ahead** (plan/STATUS.md: show the README diff to the owner first).

## Probes (C1–C8, implemented by X1)

- **C1** `README.md` < 220 lines; each translation within ±25% of its line count.
  Translations keep English's line structure: one translated line per English
  line in prose (no re-wrapping, no joining).
- **C2 verbatim blocks.** Every fenced code block, the session-states table,
  the compatibility table (columns 2–7) and the legend lines of the base
  README (`git show $BASE:README.md`) appear, whitespace-normalised, in the
  new `README.md`. Every Privacy bullet and the canary paragraph appear verbatim.
- **C3 links & assets.** In all four READMEs, Markdown links and HTML
  `href`/`src`/`srcset`: absolute `http(s)` URLs are allowed (not fetched);
  every relative path resolves to a file in the tree; a fragment-only link
  resolves against a heading slug of the *same* file; `path#frag` resolves
  against a heading slug of the *destination* file. Slugs follow GitHub's
  rules (lower-case, drop punctuation except `-`/`_`, spaces → `-`, keep
  CJK/Hangul/kana, emoji dropped, de-duplicate with `-1`, `-2`). In `--foundation` mode,
  links to the three translation files are exempt.
- **C4 icons.** Scope `docs/assets/agents/*.svg`: each is referenced by
  `README.md`, ≤ 25 KB, parses as XML, has no `<script>`, no `on*=`
  attribute, no external `href`/`xlink:href`; every `-for-light`/`-for-dark`
  pair exists together, root fill `#1f2328` / `#e6edf3` respectively.
  Separately: `LICENSE-lobe-icons.txt` contains "Copyright (c) 2023 LobeHub"
  and "Permission is hereby granted"; `ATTRIBUTION.md` names every SVG and
  links the licence file.
- **C5 language links.** Each of the four files links the other three and
  not itself.
- **C6 structural parity.** The translations have the same number of `##`
  headings, tables, table rows per table, fenced code blocks, `<picture>`
  blocks and badges as `README.md`; fenced code blocks byte-identical.
- **C7 cell parity.** In each translation, the compatibility table's row
  order (by icon path), header row, and every cell of columns 3–7 equal
  English cell by cell; the session-states table's emoji column equals
  English row by row. Every fenced code block and every backticked token
  from the contract's untranslated list (commands, paths, menu items
  `Usage Report…`, `History…`, `No active sessions`, `--query`, `make probe`,
  `make test`, `swift test`, `2▶ 1!`, `1!`, ⌘U, ⌘Y) appears in each translation.
- **C8 claim discipline (English).** Every README.md sentence outside fenced
  code — **including** table cells of new tables (e.g. "Before you install"),
  badge labels/alt text, and the text of the centred HTML header — that is not found verbatim (whitespace-normalised)
  in the base README or `docs/privacy.md` must appear in the plan's Claim
  table; and the README must not contain a jump promise for OpenCode or
  Hermes nor a 🔴/needs-approval claim for Codex or Hermes outside the table.
- **Negative controls (prove the runner can fail):** N1 swap Codex's 🔴 `—`
  with its 🟡 `✓` in one translation → C7 fails; N2 break one
  `docs/troubleshooting.md#…` fragment → C3 fails; N3 delete a `-for-dark`
  SVG → C4 fails; N4 add an unsourced sentence to README.md → C8 fails;
  N5 delete one base fenced code block → C2 fails; N6 point a relative link
  at a missing file → C3 fails.

## Claim table

(filled in during F1: new sentence → source file:line)

## Round objections → changes

### Round 2 (v2 → v3): both seats PLAN-APPROVED v2; non-blocking notes folded in, so v3 needs a confirmation round

| Note (who) | Change |
|---|---|
| Probe heading says C1–C7 (deepseek) | Renamed C1–C8 |
| C8 exempts new tables/HTML (deepseek) | C8 now covers new table cells, badge text, centred header |
| License row says verbatim but gains a line (deepseek) | Row 13 reworded; line goes in Claim table |
| `#install` anchor assumed (deepseek) | Headings pinned: `## Quick start` / `### Install` / … |
| ±25% line budget vs re-wrapping (deepseek) | C1 states translations keep English line structure |
| Emoji in slugs (deepseek) | C3 slug rule: emoji dropped |
| No negative control for C2 / C3 relative path (deepseek) | N5, N6 added |
| Third-party licence scope (deepseek) | ATTRIBUTION states marks + licence file are outside Apache-2.0 |

### Round 1 (v1 → v2)

| Objection (who) | Change |
|---|---|
| Licence evidence incomplete; scratch LICENSE.txt was a 404 body (codex 1, deepseek 3) | Vendor upstream `lobehub/lobe-icons` LICENSE verbatim from GitHub; ATTRIBUTION lists URL, sha256, recolouring; C4 checks licence text |
| F1 gate depends on translation files that don't exist yet (codex 2) | F-set (`--foundation`) defined; X1 delivered before F1 is checked; full suite after D1 |
| C4 unsatisfiable with a Markdown file in the dir (codex 3, deepseek 1) | C4 scoped to `*.svg`; licence/attribution checked separately |
| Token multisets miss swapped cells; need semantic review (codex 4) | C7 compares cell by cell with row order; N1 negative control; explicit semantic translation review at code gate |
| Cross-file fragments resolved against wrong file (codex 5) | C3 resolves `path#frag` against destination; doc fragments untranslated |
| External badges false-fail C3 (deepseek 2) | C3 allows absolute http(s); badge URLs pinned in decision 6 |
| Non-blocking, folded in (deepseek): claim probe; "Why" overreach; probe independence; pinned light/dark naming+fills; Copilot alt/attribution; badge URLs; C7 allowlist; CJK slugs | C8 + claim table in F1; section-5 rule; independence paragraph; `-for-light/-for-dark` + fills asserted; alt + ATTRIBUTION note; decision 6; C7 list; C3 slug rules |

## Outcome

(filled in after the code gate)
