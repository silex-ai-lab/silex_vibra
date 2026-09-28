# Execution plan — OSS growth, Day 1 + per-agent guides (2026-09-28)

Executes the text-only items of [OSS-GROWTH-PLAN.md](OSS-GROWTH-PLAN.md)
(#3, #4, #5, #6, #7, #8, and the #10 example text). Docs only: **no change
under `Sources/`, `Tests/`, `Makefile` or `Package.swift`.**

**Status:** v3, plan gate passed (round 3, unanimous).
**BASE:** `d40c4fb3a99815bd38338c750a601dd1781ff148` (branch `oss-growth-day1`).

**Plan-gate verdicts on v3:** coder-deepseek `PLAN-APPROVED` · reviewer-codex `PLAN-APPROVED` · PLANNER (claude): PLAN-APPROVED

## Roster

Run with the `herdr-agent-fleet` workflow. Both gates unanimous.

| Seat | Agent | Pane |
|---|---|---|
| planner | Claude Code (Opus 5.5) | `wN:p1` |
| coder-deepseek | OpenCode, `deepseek/deepseek-reasoner` | `wN:p2` |
| reviewer-codex (third judge) | Codex CLI 0.157.1 | `wN:p3` |

## Out of scope (and why)

| Item | Why not in this run |
|---|---|
| #1 Signing / distribution | Owner decision (Developer ID, USD 99/yr). Install stays source-only; README says so plainly. |
| #2 Demo recording | Needs a real screen recording by the owner. No placeholder image or GIF is added; the ASCII sketch stays as the first-screen visual. |
| #9 Topics / homepage | Repository settings, not repo content. Proposed as a post-gate action that runs only with the owner's explicit go-ahead. Homepage stays empty until a download page exists. |
| #7 Release-notes edit | Editing the published GitHub Release is outward-facing. Proposed text is below; applied only with the owner's go-ahead. STATUS records #7 as partly done with this piece pending. |
| #10 skill-directory submission, #11 CONTRIBUTING + templates | The growth plan sequences both after #1. |
| Push to `origin/main` | Work lands on local branch `oss-growth-day1`. Merge/push only after the code gate **and** the owner's go-ahead (plan/STATUS.md: "show the README diff to the owner before pushing"). |

## Additional facts found while planning (checked at `d40c4fb`)

These extend the growth plan's "Facts verified" section (task P7).

1. **A second stale report-card claim.** README line 659: "Not yet done: weekly
   report cards, and Developer ID signing." The report card is done (ROADMAP
   P1.3).
2. **The usage report is undocumented in the README.** The menu has
   `Usage Report…` (⌘U, `Sources/VibraApp/MenuBarController.swift:121`); the
   README mentions "the usage report" only in passing (line 115).
3. **The 2026-09-27 Release body links two files that do not exist in the
   repo** (`docs/DESIGN-PLAN-agent-monitor-reuse-v2.md`,
   `docs/PLAN-2026-09-26-ui-ideas-from-agent-monitor.md`; `git log --all` finds
   neither). The existing record is `docs/PLAN-2026-09-27-history-ui.md`.
4. **An empty menu reads "No active sessions"** (`MenuBarController.swift:99`).
5. Nothing outside the README links into its anchors; its own changelog uses
   `#visual-studio-code` and `#stable-signing-for-development`.
6. **Not every agent can show every state** (from code, not docs):
   `CodexAdapter` never emits `.permissionPrompt`; `OpenCodeAdapter` emits only
   `.permissionPrompt` or `.unknown`, so OpenCode can show working (recent
   activity), needs approval and idle, but never your turn or stalled
   (`StateEngine.classify`); `Session.settlingOrphaned` turns a stalled Cursor
   session into idle; Hermes never emits `.permissionPrompt`. Claude Code also
   gets `busy`/`waiting` from its live status (`Session.enriched`).
7. **Click-to-jump differs per agent** (`ProcessLocator.canJump`): Claude Code
   and Codex jump to the terminal tab (iTerm2, Terminal, herdr pane) or bring
   the hosting app forward; Cursor and VS Code focus the editor app/window, not
   a single chat; OpenCode and Hermes cannot jump.
8. **Current docs contradict each other on VS Code and on jump-back.**
   `docs/ROADMAP.md:370` says VS Code is "fixture-tested only; a live session
   has not been watched end to end", but README line 74 says "Tested live
   against VS Code 1.135: working, needs approval, your turn, a reply stopped
   by quitting, and click-to-focus" (commit `2164fa6`). `docs/STATUS.md:86-87`
   says remaining work has "no viable target on this machine (P2.2)" while its
   own table marks P2.2 done; `docs/STATUS.md:300` lists jump-back as
   unavailable in herdr, which HEAD implements (`HerdrLocator`, README
   Troubleshooting).
9. Tests and fixtures live in `Tests/VibraCoreTests/` and
   `Tests/VibraCoreTests/Fixtures/`.

## State support matrix (from code; D1 re-verifies and reports any difference)

"Can show" is what the code can produce. "Live" is whether a live observation
is recorded in the base README or `docs/STATUS.md`; D1 fills the evidence
column per state in each guide. The README compatibility table is built from
this matrix plus D1's evidence, and keeps the two ideas apart.

| Agent | working | your turn | needs approval | stalled | idle | Click |
|---|---|---|---|---|---|---|
| Claude Code | yes | yes | yes | yes | yes | terminal tab / host app |
| Codex | yes | yes | **never** | yes | yes | terminal tab / host app |
| OpenCode | yes | **never** | yes, not observed live | **never** | yes | none |
| Cursor | yes | yes, not observed live | yes, not observed live | **never** (shown idle) | yes | brings Cursor forward |
| VS Code (Copilot Chat) | yes | yes | yes | yes (while VS Code runs) | yes | focuses the window |
| Hermes | yes, fixture only | yes, fixture only | **never** | yes, fixture only | yes | none |

## Target structure

**Front page `README.md`, < 150 lines**, in this order (growth plan #4):

1. `# Vibra` + outcome headline (#3): **"Know when your coding agents need
   you."** Subtitle: a macOS menu-bar app that shows working / your turn /
   needs approval for Claude Code, Codex, Cursor, VS Code (Copilot Chat),
   OpenCode and Hermes sessions — "for the agents that can report it; see the
   table". One line: Apache 2.0, local-only, no network.
2. The existing ASCII menu sketch, verbatim (demo placeholder until #2 exists —
   no image placeholder).
3. **Who it is for** — the existing "Why" paragraph (lines 25–28), verbatim.
4. **What it does** — three abilities, one or two lines each, each linking to
   detail: (a) every session's state in the menu bar, with the five-row states
   table (lines 152–158) — **the table lives on the front page only**; (b) a notification when a session needs
   you, and a click that jumps to it — **qualified**: terminal tab for Claude
   Code and Codex, the editor window for Cursor and VS Code, no jump for
   OpenCode and Hermes; (c) usage report (⌘U) and History (⌘Y), with
   `--query` for scripts.
5. **Compatibility table** — one row per agent: surfaces; the states it can
   show; which of those are observed live; link to `docs/agents/<agent>.md`.
   States it can never show are written as "—". Not-observed-live states get
   numbered footnotes (#7). Built from the matrix above and D1's evidence.
6. **Install** — lines 176–215 verbatim (requirements, four-command source
   build, `make uninstall`, first-launch Gatekeeper step), plus one added
   sentence: "There is no downloadable app yet: Vibra is ad-hoc signed and not
   notarized, so notifications need one manual System Settings step — see
   [Troubleshooting](docs/troubleshooting.md#troubleshooting)."
7. **First two minutes** (#5) — scoped to an **interactive Claude Code or Codex
   session in a terminal**: open the app → from the cloned repo, run
   `make probe` → give the agent a task → it shows 🔵 working → when the turn
   ends it shows 🟠 your turn and the menu bar shows `1!`. States that the menu
   reading `No active sessions` when nothing has run in the last 12 hours is
   expected, and that `make probe` exits `2` in that case. Other agents: "see
   their guide for what they can show".
8. **Privacy** (#6) — "What Vibra reads" / "What it never does", 6–8 bullets.
   Each bullet is a verbatim or strictly narrower restatement of a sentence in
   `docs/privacy.md` (which holds lines 392–426 verbatim, so the growth plan's
   "match exactly" requirement is met there), except "never approves actions
   for you", sourced from ROADMAP "Explicitly not doing". Names the canary
   tests and links `docs/privacy.md`.
9. **More** — links: features, troubleshooting, development, agent guides,
   CHANGELOG, ROADMAP.
10. **Contributing** — 3 lines: issues welcome, run `make test` (not
    `swift test`), link to `docs/development.md`.
11. **License** (lines 661–663 verbatim).

**Moved, not deleted** (content conservation, #4). Moved blocks keep their
wording; the only permitted edits are listed in the three classes under
"Conservation rules".

| New file | Takes from README (line ranges at `d40c4fb`) |
|---|---|
| `docs/features.md` | 98–148 History / Settings / `--query` (the 136–141 code block per rule R); 150–151 and 160–174 (Session states heading, the `stalled` explanation, notification lifecycle — the 152–158 table stays on the front page and is linked); 382–390 cost figures; **new** Usage Report section (fact 2); **new** #10 example |
| `docs/development.md` | 217–370 Test run, run the tests, development loop, stable signing, what it costs; 371–380 testing note; 639–659 Status / performance table |
| `docs/troubleshooting.md` | 428–521 Troubleshooting; 523–561 Known limitations, general items in full; per-agent items (539–556) move to the agent guides and are linked from here |
| `docs/privacy.md` | 41–42 "Vibra never asks these tools…" and 95–96 "It installs nothing…", then 392–426 Privacy and safety, all verbatim |
| `docs/agents/*.md` (deepseek) | 44–93 VS Code and Cursor sections; 539–556 per-agent limitations; each agent's row of the source table at 32–39 (the path, verbatim) |
| `CHANGELOG.md` (repo root) | 563–637 Changelog, verbatim |

### Conservation rules (define probe C2)

Every base-README block (paragraph, list item, table row, fenced code block;
heading lines excluded) falls in exactly one class:

- **V — verbatim.** Must appear, whitespace-normalised, in the new README or a
  moved file after applying the **link-rewrite map** (fixed list, below).
  This is the default class.
- **R — replaced.** Listed here, and nowhere else: line 3–5 intro paragraph
  and line 7 "Open source…" line (→ headline, subtitle and one-liner, item 1);
  the table header and rows 30–39 (→ compatibility table + each guide's
  "What Vibra reads", where the path appears verbatim); lines 657–659 Status
  paragraph (→ new text: "Working against real data: the menu bar, all six
  adapters, state classification, usage/cost accounting, and terminal
  jump-back. Not yet done: Developer ID signing."); lines 136–141, the
  `--query` code block (→ in `docs/features.md`, exactly:
  ```sh
  /Applications/Vibra.app/Contents/MacOS/Vibra --query                                # after make install
  make query                                                                          # from a build
  /Applications/Vibra.app/Contents/MacOS/Vibra --query --attention                    # only sessions that need you
  /Applications/Vibra.app/Contents/MacOS/Vibra --query --agent codex                  # one agent
  ```
  ); line 485–486 "**`swift
  test` says everything passed but nothing ran.** … See the testing note
  above …" (→ same sentence with "the [testing note](development.md#testing-note)"),
  and any other cross-file "above"/"below" wording, each listed with old and
  new text in the Outcome section's appendix before the code gate.
- **D — deleted.** Exactly one block: line 538 "**No weekly report card.**"

Link-rewrite map (applied to moved text only): `docs/X` → `X` inside `docs/`;
`docs/skills/…` → `skills/…` inside `docs/`; `#visual-studio-code` →
`docs/agents/vscode.md`; `#stable-signing-for-development` →
`docs/development.md#stable-signing-for-development`; `LICENSE` →
`../LICENSE` inside `docs/`.
C2 fails if a block is missing without being in R or D, if an R entry has no
recorded new text, or if an R entry's new text does not appear (whitespace-
normalised) in its stated destination file.

## Tasks

File ownership is exclusive. Do not edit files outside your list; report a
needed change to its owner instead.

| # | Owner | Task | Files | Acceptance check |
|---|---|---|---|---|
| P1 | planner | Branch `oss-growth-day1` from base; record `BASE` here | this file | recorded |
| P2 | planner | Create the moved docs and CHANGELOG | `docs/features.md`, `docs/development.md`, `docs/troubleshooting.md`, `docs/privacy.md`, `CHANGELOG.md` | C2 |
| P3 | planner | Rewrite the README front page per "Target structure" | `README.md` | C1, C3, C4, C8 |
| P4 | planner | Usage Report section; #10 example: a coding agent runs `/Applications/Vibra.app/Contents/MacOS/Vibra --query --attention` to answer "which session needs me?"; the JSON carries state, never message text; links `skills/vibra-query/SKILL.md` | `docs/features.md` | C7 |
| P5 | planner | Privacy block (#6) | `README.md` | C5 |
| P6 | planner | Consistency (#7) across current docs: ROADMAP P2.2 VS Code line gets a dated note that live testing followed (README line 74, `2164fa6`), the original sentence kept; `docs/STATUS.md:86-87` and the gap row at `:300` (herdr) corrected or marked historical — rows 299 and 301 are still true and stay, dated entries untouched; README Status paragraph per rule R | `docs/ROADMAP.md`, `docs/STATUS.md` | C4 |
| P7 | planner | Growth plan facts + STATUS progress (#7 partly done: release notes pending; #9 pending owner); CHANGELOG Unreleased "Docs:" entry. **Done before the probes and the code gate**, so the reviewed diff is the committed diff | `plan/OSS-GROWTH-PLAN.md`, `plan/STATUS.md`, `CHANGELOG.md` | in reviewed diff |
| D1 | deepseek | Six agent guides (#8) | `docs/agents/claude-code.md`, `codex.md`, `opencode.md`, `cursor.md`, `vscode.md`, `hermes.md` | C6, C7 |

**Agent-guide contract (D1).** Each file has exactly these sections:
`## What Vibra reads` (path(s) verbatim from README 32–39; read-only
contract) · `## States shown` (each of the five states — working, your turn,
needs approval, stalled, idle — as "can show, from <signal>" or "never, because
<code reason>") · `## Verified vs. unverified` (table: state → *observed live*
/ *fixture-tested* / *not observed* / *never shown*, with evidence) ·
`## Limits` · `## Check it yourself`.

Evidence rules: *observed live* cites a sentence in the base README or
`docs/STATUS.md` (file:line). *fixture-tested* names the test file **and the
test function or assertion** under `Tests/VibraCoreTests/` that produces that
state. Anything without such evidence is *not observed*. Ground "from
<signal>" and "never" in the adapter (`Sources/VibraCore/Adapters/`) **and**
`Sources/VibraCore/State/StateEngine.swift`, `LivePipeline.swift`,
`Sources/VibraCore/Models/Session.swift` (`enriched`, `settlingOrphaned`) and
`Sources/VibraCore/Locate/ProcessLocator.swift` (`canJump`). If the code
disagrees with the matrix above, follow the code and report the difference in
the reply.

"Check it yourself" commands: `make probe` (stated as run from the cloned
repo) and `/Applications/Vibra.app/Contents/MacOS/Vibra --query --agent <kind>`
(full path; kind spelled as in `SKILL.md`: `claudeCode`, `codex`, `openCode`,
`cursor`, `vsCode`, `hermes`).

Data rules: never read `~/.claude`, `~/.codex`, `~/.local/share/opencode`,
`~/.hermes`, or editor storage. The README, `docs/STATUS.md`, source and
`Tests/VibraCoreTests/Fixtures/` are the sources. The VS Code and Cursor guides
carry README lines 44–93 verbatim; each guide carries its per-agent Known
limitations item(s) (539–556) verbatim under `## Limits`. Link to
`../troubleshooting.md` and `../privacy.md` where relevant.

## Sequence

1. Plan gate (all three seats `PLAN-APPROVED`).
2. P1 (branch + BASE). Link targets D1 needs are fixed by this plan.
3. D1 prompted to DeepSeek; P2–P7 by the planner in parallel.
4. Probes C1–C9 green → code gate on `git diff $BASE` (all three
   `IMPL-APPROVED`) → local commit on `oss-growth-day1`. Any edit after a
   verdict re-runs the probes and goes back to both reviewers.
5. Ask the owner: merge + push to `main`; apply topics (#9); edit the Release
   notes (#7). Nothing outward-facing happens without that answer.

## Probes (acceptance, run before the code gate)

- **C1** `wc -l README.md` < 150.
- **C2 content conservation** per "Conservation rules": script classifies
  every base block as V / R / D; prints missing blocks; must print none.
- **C3 links.** Every relative link and `#anchor` in every changed or new
  `*.md` resolves (file exists; anchor matches a GitHub-slugged heading).
- **C4 consistency.** No `No weekly report card` / `weekly report cards` in any
  current doc (`README.md`, `CHANGELOG.md`, `docs/*.md` except dated
  `docs/PLAN-*` / `docs/FIX-PLAN-*` records, `docs/agents/*`); `Usage Report`
  appears in README and `docs/features.md`; the ROADMAP VS Code line and
  `docs/STATUS.md` gap rows no longer contradict README (manual check, listed
  in Outcome).
- **C5 privacy traceability.** Outcome table: README privacy bullet → source
  sentence (file:line).
- **C6 agent guides.** Six files, the five required `##` headings each; every
  *observed live* row cites file:line that exists and contains the claim;
  every *fixture-tested* row names an existing test function (`grep`).
- **C7 commands** (run by the planner only). Every `--query` / `--agent` /
  `make` command shown in new or changed docs is checked: flags exist in
  `Sources/VibraApp/main.swift`; kinds match `AgentKind` raw values; `make`
  targets exist in `Makefile`. The documented path
  `/Applications/Vibra.app/Contents/MacOS/Vibra` is checked statically against
  the Makefile (`install` copies `build/Vibra.app` to `/Applications`,
  `CFBundleExecutable` = `Vibra`), then that same executable at
  `build/Vibra.app/Contents/MacOS/Vibra` runs every documented `--query` form
  (`--query`, `--attention`, `--agent <each of the six kinds>`) exiting 0 with
  JSON on stdout. **Every executable probe runs with `VIBRA_HOME` set to a
  fresh empty temp directory** (override in
  `Sources/VibraCore/Adapters/AgentAdapter.swift:107`), so no probe reads the
  user's real agent or editor stores; `make probe` / `make query` are checked
  as targets only, never run. These isolated validation commands are not the
  user-facing examples.
- **C8 claim discipline (semantic).** Script + manual check that README and
  guides never assign an agent a state the matrix marks **never** (e.g. no
  "needs approval" for Codex/Hermes, no "your turn"/"stalled" for OpenCode),
  never promise a jump for OpenCode/Hermes, and the first-success walkthrough
  names only Claude Code / Codex.
- **C9 no code change.** `git diff --stat $BASE -- Sources Tests Makefile
  Package.swift` is empty; `make test` passes.

## Proposed outward-facing text (applied only with the owner's go-ahead)

- **Topics (#9):** `claude-code codex cursor opencode github-copilot macos
  menubar ai-agents developer-tools`.
- **Release 2026-09-27 body:** prepend "Source-only release — there is no app
  download yet; build from source (see README → Install)." and replace the two
  dead links with `docs/PLAN-2026-09-27-history-ui.md`.

## Round-1 objections → changes

| # | Objection (who) | Change |
|---|---|---|
| 1 | Wrong test path `Tests/VibraTests`; file existence can't prove a state (Codex, DeepSeek) | All paths → `Tests/VibraCoreTests/`; *fixture-tested* must name the test function/assertion; C6 greps for it |
| 2 | Unsupported states (Codex no approval, OpenCode no your-turn/stalled, Cursor stalled→idle); first-success over-promises; jump not uniform (Codex) | Fact 6–7; new **State support matrix**; table separates "can show" from "observed live" with "—" for never; first-success scoped to interactive Claude Code / Codex; jump qualified per agent; D1 grounds in StateEngine / LivePipeline / Session / ProcessLocator; new probe **C8** |
| 3 | C2 contradicts P3 rewrites; partial paragraph deletion; relocated links (Codex) | New **Conservation rules**: V/R/D classes with an explicit R list and fixed link-rewrite map; line 659 becomes an R entry with its exact new text; D now holds one block |
| 4 | `Vibra` is not on PATH after install; `make probe` runs from the repo (Codex) | All commands use `/Applications/Vibra.app/Contents/MacOS/Vibra`; `make probe` stated as run from the cloned repo; new probe **C7** runs each `--query` form |
| 5 | STATUS.md contradictions (P2.2 "no viable target", herdr jump gap row) (Codex); ROADMAP:370 VS Code "fixture-tested only" vs README "tested live" (DeepSeek) | Fact 8; P6 scope now names both files and those lines; historical entries annotated, not rewritten; C4 adds the manual check |
| 6 | P7 edits after the code gate (Codex) | P7 moved before the probes; any post-verdict edit re-runs probes and both reviews; STATUS marks #7 partly done, #9 pending |
| N1 | "four live states" vs five (DeepSeek) | Five states throughout |
| N2 | Privacy "exact match" now lives in docs/privacy.md (DeepSeek) | Stated explicitly in item 8 |
| N3 | Lines 41–42 unaccounted for (DeepSeek) | 41–42 and 95–96 move verbatim to `docs/privacy.md` |

## Round-2 objections → changes

| # | Objection (who) | Change |
|---|---|---|
| 1 | Bare `Vibra --query` block (136–141) is class V, so the full-path fix was not authorised; C7 ran a substitute binary; C2 didn't check R text lands (Codex) | 136–141 added to R with its exact new text; C2 now asserts each R replacement appears in its destination; C7 checks the documented path against the Makefile and runs the bundle executable itself |
| 2 | Executable probes would read the real agent stores (Codex) | Every executable probe runs with `VIBRA_HOME` = empty temp dir; D1 runs no executable probe; `make probe`/`make query` never run |
| 3 | States table 152–158 claimed by both front page and features.md (DeepSeek) | Table stays on the front page only; features.md takes 150–151 and 160–174 and links to it |
| N1 | `#cursor` anchor doesn't exist (DeepSeek) | Dropped from the map |
| N2 | Status paragraph is 657–659 (DeepSeek) | Relabelled; table rows relabelled 30–39 to include the heading block |
| N3 | Only STATUS row 300 is contradicted (DeepSeek) | P6 scoped to row 300; 299 and 301 stay |

## Outcome

_(filled after the code gate)_
