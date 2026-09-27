# Plan — History window UI improvements (2026-09-27)

## Why

The user runs both tools over the same agent sources. `the reference dashboard` is a
local web dashboard (React + FastAPI + SQLite) with a rich filtering and
detail UI; Vibra is a native macOS menu-bar app whose design rule is *glance,
don't browse*. The ask: compare the two UIs, take what genuinely improves
Vibra, and leave the rest. This plan is the diff between "nice in a
dashboard" and "right in a menu-bar app".

## Roster and gates

| Seat | Role |
|---|---|
| **mimo** (`opencode/mimo-v2.6-flash-free`, this agent) | Owns the plan, implements, casts a written vote |
| **reviewer-nemotron** (`opencode/nemotron-3-ultra-free`) | Reviews plan and diff |
| **reviewer-ling** (`opencode/ling-3.0-flash-fin-free`) | Reviews plan and diff |

DeepSeek was the user's first choice for the third seat but is unavailable on
this machine (no `DEEPSEEK_API_KEY`, not in `opencode models`); the user
authorized this replacement roster. **Both gates are unanimous across all
three seats.** Mid-work questions that split go to the user (no tiebreak).

Reviewers read **this plan and the silex_vibra repo only** (public:
github.com/silex-ai-lab/silex_vibra). They do not read `the reference dashboard` — it
is an internal repo whose screenshots contain the user's own session content,
and free-tier seats get no images. Section B below is the text fixture that
stands in for it.

## B. the reference dashboard UI inventory (fixture; not readable by reviewers)

1. **Hero header** — eyebrow + title + subtitle; primary "立即重扫" (rescan)
   and secondary "刷新视图" (refresh) buttons.
2. **KPI strip** — 4 cards: questions in range, attention count, running
   tasks, failed tasks (red).
3. **Controls** — start/end date inputs, sort select, keyword search; quick
   range chips 今天 / 近3天 / 近7天 / 近30天 with active state; filter chip
   groups for source (each chip carries a **count**: "Claude Code 93"),
   status (运行中/成功/失败/超时/警告), and workspace.
4. **Three panes** — (a) question list with card⇄table toggle, "显示更多"
   pagination, **复制表格** (copy table) and **导出 Excel** (export); (b)
   question **detail pane**: source pill, full title, meta grid, source file
   path + copy button, task status section, timeline; (c) sidebar with a
   **"需要你处理" attention panel** (severity-bordered cards: source pill,
   kind, reason, origin file, time) and a **local config panel** (scan roots,
   poll interval, timezone, archived toggle, four attention-rule checkboxes).
5. **Visual language** — dark glassmorphism, warm-orange accent, one tinted
   pill color per source, status chips, dashed empty-state boxes, responsive
   breakpoints. Fully persisted data (SQLite) and Excel export.

## A. Vibra inventory (reviewers: verify against code)

- **Menu bar item** `Vibra 2▶ 1!` — working count, attention count
  (`MenuBarController.swift:85-93`). Terse by design (`:6-8`).
- **Menu** — attention-first ordering inside each agent group
  (`:105-117`); section headers show the agent name only (`:136-147`); rows
  are `dot name · state · tokens` (`:149-161`) with cwd/model tooltips; click
  jumps to the session's terminal (`TerminalJumper`).
- **History window** (`HistoryWindowController.swift`) — search field, agent
  popup ("All agents" + 3 covered), days popup (allowedDays `1, 3, 7, 14,
  30`); plain NSTableView with bold day group rows and one-line question rows
  `HH:mm agent · project first line`; **full text only in a tooltip**; double
  click jumps to a live session else copies the question; status line
  `N questions · read X MB · covers … · nothing is saved`; data lives in
  memory while open and is released on close (`:181-186`); `renderedText`
  deliberately excludes question text (`:49-59`).
- **Settings** — three numeric attention rules, saved as changed.
- **Report / notch overlay / notifications** — out of scope here.
- **Design rules in force**: native Aqua, system fonts/colors, English, zero
  storage beyond the three settings, every surface terse.

## C. Principles for this work (the bar every task must clear)

- **P1 native first.** No custom drawing, themes, gradients, or tinted pills.
  System appearance, system controls.
- **P2 the menu bar is the glance surface.** No dashboard window that
  duplicates it.
- **P3 zero new persistence.** Clipboard only, user-initiated. Even window
  state (split divider) is not saved.
- **P4 claim discipline.** `renderedText` and any diagnostic stay
  content-free; status text states only what was observed.
- **P5 terse.** Each added word or pixel earns its place.

## D. Candidate evaluation

### Adopted → tasks

| # | Borrowed idea | Task |
|---|---|---|
| C1 | Per-source counts ("Claude Code 93") | **T1** menu section headers carry the group's live session count; **T4** history agent popup carries per-agent question counts |
| C2 | List + detail panes | **T2** history detail pane: read the full question in place |
| C3 | 复制表格 (copy table) | **T3** copy visible history rows as TSV |
| C4 | Dashed empty states | **T5** "No questions match" label when filters empty the list |

### Rejected

| # | Candidate | Why not |
|---|---|---|
| R1 | Dark glassmorphism theme, tinted source pills | Violates P1; a menu-bar app follows the system theme; its color signal is already the emoji state dots |
| R2 | SQLite persistence, Excel export | Violates P3; Vibra's "nothing is saved" is the product. Clipboard copy (T3) covers the export need |
| R3 | Config panel (scan roots, poll interval, timezone, archived toggle) | Scan locations are fixed by design (each adapter knows its app's paths); attention rules already exist in Settings; timezone follows the system |
| R4 | KPI dashboard / summary window | Violates P2; the status item `2▶ 1!` is the KPI |
| R5 | Quick-range chips (今天/近7天/…) | Redundant: the days popup already offers 1/3/7/14/30 days |
| R6 | Status taxonomy 运行中/成功/失败/超时/警告 | Different data model: those are task *outcomes*; Vibra classifies *live session* states (working/your turn/needs approval/stalled/idle), which the menu already shows |
| R7 | Workspace filter group | Search already matches project names; rows already show the project |
| R8 | Attention sidebar panel | The menu already floats attention rows first, prefixes `N!` in the status item, and notifies with click-to-jump; a panel would duplicate it (P2) |

## E0. Round-1 → r2 (objections and suggestions applied)

Both reviewers returned `PLAN-APPROVED` in round 1; reviewer-ling added six
non-blocking suggestions, all folded in here:

| # | Suggestion (ling) | Change |
|---|---|---|
| 1 | T2 `NSTextView` needs explicit read-only | T2 now says `isEditable = false` |
| 2 | T4 "same index build" could mislead into building once *with* the agent filter | T4 reworded: one index build with keyword+days but **without** the agent filter; counts from it, rows from it filtered by selection |
| 3 | T5 centering unspecified | T5 pins the label to the scroll view (centered X, top inset) |
| 4 | T2 stale detail on close/re-show | T2 now explicitly clears the detail text view (not just records) in `windowWillClose` |
| 5 | T3 button title unspecified | T3 names the button `Copy` |
| 6 | T2 "full text" overclaims vs the 2000-char normalization | T2 says "the record's stored text (normalized, capped at `QuestionRecord.maxLength`)" |

Round 2: both `PLAN-APPROVED`; reviewer-ling's two further notes applied:

| # | Suggestion (ling, r2) | Change |
|---|---|---|
| 7 | T5 label hierarchy unspecified | T5 states the label sits as a sibling overlay above the scroll view (never inside its document view) |
| 8 | T2 placeholder text unspecified | T2 names the placeholder: `Select a question to read.` (secondary label colour) |

Round 3: both `PLAN-APPROVED`; reviewer-ling's last note applied:

| # | Suggestion (ling, r3) | Change |
|---|---|---|
| 9 | T2 Copy button's status message unspecified | T2's Copy reports the existing double-click message (`Copied the question to the clipboard…`), and like T3's message it stands until the next filter action |

Implementation-time note (mimo, folded before the code gate):

| # | Issue (found while implementing row 9) | Change |
|---|---|---|
| 10 | Row 9's message would repeat `(its session is not live)` even for a **live** session — a false claim (P4) | T2's spec now states the two branches: live session → `Copied the question to the clipboard.`; else → the full existing message with the parenthetical. Implemented in `copyDetail` exactly so |

## E. Wave 1 tasks (all owned by mimo — reviewers are judges, not coders)

**Base**: `BASE = a530ab8` (recorded again at implementation start).

- **T1 — Menu section headers show counts.**
  `sectionHeader` gains the group size: `Claude Code · 3`. Count = exactly
  the rows rendered under that header (never derived from a second source).
  Acceptance: run the app; every visible section header ends in `· N` with N
  = its rows; sections with no rows do not exist (current behaviour kept).
  *No unit test: `VibraApp` is not in the test graph (Package.swift) — this
  is stated, not papered over.*

- **T2 — History detail pane.**
  Split the history window horizontally (`NSSplitView`): left = existing
  table; right = detail column with a meta line (`HH:mm · Agent · project`),
  the record's stored question text (normalized, capped at
  `QuestionRecord.maxLength`) in a selectable, **read-only** (`isEditable =
  false`) wrapping `NSTextView`, and a **Copy** button (same text
  double-click copies). Empty selection shows a placeholder label reading
  `Select a question to read.` (secondary label colour). The Copy button
  reports the existing double-click message — but the existing message ends
  with `(its session is not live)`, which would be a false claim for a live
  session (P4). Two branches: a live session reports `Copied the question to
  the clipboard.`; otherwise the full existing message including the
  parenthetical. Either message stands until the next filter action
  overwrites the status line. Window
  default width 760 → 980. Divider position is not saved (P3). Double-click
  jump/copy behaviour unchanged. On window close, `windowWillClose` clears
  the records, the rows **and the detail text view** (back to the
  placeholder) so a re-show can never display stale text. `renderedText`
  stays status + day headers only — no detail text, ever (P4; the struct doc
  on `QuestionRecord` makes this a rule).
  Acceptance: select a row → stored text readable in place; copy button puts
  it on the clipboard; close/reopen shows no stale text; `--show-history
  --snapshot` diagnostics still print no question text.

- **T3 — Copy visible rows (TSV).**
  A **Copy** button in the filter bar copies every visible *question* row
  (day headers skipped) as `HH\tAgent\tproject\tfirst line`, in display
  order. Status line then reads `Copied N rows to the clipboard.` (overwritten
  by the next filter action). Nothing touches disk (P3).
  Acceptance: with M visible rows, one paste yields M lines; a keyword
  filter changing M changes the pasted line count.

- **T4 — Per-agent counts in the agent popup.**
  `applyFilters` retitles popup items to `All agents (12)`,
  `Claude Code (7)`, … One index build with keyword + days but **without**
  the agent filter is the single source: counts (per agent and total) read
  straight from it; the displayed rows are that same index filtered by the
  selected agent. Counts therefore always sum to the `N questions` total
  under "All agents" and never depend on the agent selection itself.
  Acceptance: change the keyword → counts and total move together; select
  an agent → rows shrink, counts stay.

- **T5 — Empty state.**
  When filters leave zero question rows, show a native centered
  `NSTextField`: `No questions match.` (secondary label colour; hidden
  otherwise). Layout: the label is a sibling overlay pinned above the scroll
  view — centred on X, fixed inset from the top — never inside the table's
  document view. Status line still reports `0 questions · …`.
  Acceptance: a keyword with no matches shows the label; clearing the
  keyword hides it.

- **T6 — README.** Update the History-window bullets (features list and
  window section) for the detail pane, copy button, and counts. No claim
  beyond what the build demonstrates (P4).

Out of scope, unchanged: ingest/read path, filter semantics, menu row
format, status item title, Settings, Report, notch, notifications, adapters.

## F. Verification

1. `make test` (baseline 156) and `swift build` — both must stay green.
2. Snapshot probe: `--show-history --snapshot` before and after; rendered
   diagnostic must still contain day headers/status and **no question text**.
3. Manual passes, recorded in the Outcome: menu counts (T1), detail select →
   read → copy → close/reopen (T2), TSV line count vs visible rows (T3),
   popup counts sum (T4), empty label (T5).
4. Claim discipline: README statements re-checked against the running build.

## G. Process

Plan gate: byte-identical prompt to reviewer-nemotron and reviewer-ling;
`PLAN-APPROVED` required from both **and** written here by mimo. Then
implement, record `BASE`, produce `git diff BASE`, code gate:
`IMPL-APPROVED` from both reviewers and mimo's written vote against the same
diff revision. Verdicts and rounds are appended to the Outcome section
below. Nothing is committed to a shared branch before the code gate passes.

## Outcome

### Plan gate — closed, unanimous (2026-09-27)

| Round | reviewer-nemotron | reviewer-ling | Changes |
|---|---|---|
| 1 | `PLAN-APPROVED` | `PLAN-APPROVED` + 6 suggestions | E0 rows 1–6 folded |
| 2 | `PLAN-APPROVED` | `PLAN-APPROVED` + 2 suggestions | E0 rows 7–8 folded |
| 3 | `PLAN-APPROVED` | `PLAN-APPROVED` + 1 suggestion | E0 row 9 folded |
| 4 (closing text) | `PLAN-APPROVED` | `PLAN-APPROVED` | — |

Verdict files: `nemotron-plan-r{1..4}.md`, `ling-plan-r{1..4}.md`
(scratch dir, written by each seat, read back and freshness-checked).

**mimo: PLAN-APPROVED.** BASE = `a530ab8abe926853cbf5ccc3fbb509275913d0a0`
recorded at implementation start.

### Verification — recorded (2026-09-27, F.3)

1. `swift build` clean; `make test`: **156 tests passed, canary present**
   (baseline 156). Final state after all edits below.
2. Snapshot probe (BASE vs after, `--show-history --snapshot`): window
   760×568 → 980×568; rendered diagnostic structurally identical — status line
   + day headers only, **no question text**. Pixel probes of the real window
   render confirm the side-by-side split, the centered placeholder, the status
   line, and both Copy buttons present (all absent at BASE where applicable).
3. The console session locked mid-verification (blocks AX window access and
   input injection), so T2–T5 were recorded through a temporary
   `--selftest-history` driver that exercises the *real* window
   programmatically (select, `performClick` on the real buttons, filters,
   close/reopen, pasteboard). The scaffold lived in `main.swift` only and was
   removed afterwards: `git diff a530ab8` = `README.md`,
   `Sources/VibraApp/HistoryWindowController.swift`,
   `Sources/VibraApp/MenuBarController.swift`, nothing else. Results
   (evidence files `selftest-history.txt`, `selftest-history-live.txt` in the
   fleet scratch dir — **38 PASS / 0 FAIL each, exit 0**):
   - **T1** — status-item menu read via accessibility: `OpenCode · 6` header
     followed by exactly 6 row items before the separator; separators carry no
     title; no uncounted groups.
   - **T2** — select a question → detail shows the stored text (74 chars for
     the probe record), meta is `HH:mm · Agent · project`, view is read-only +
     selectable, placeholder hidden, detail Copy enabled. Detail Copy puts
     exactly the record's text on the pasteboard; status branches both
     executed: non-live session → `Copied the question to the clipboard (its
     session is not live).`; live session → `Copied the question to the
     clipboard.`. Close clears the detail (placeholder back, Copy disabled);
     reopen reloads (`83 questions`) with no stale text and counts intact.
     `renderedText` does not contain the selected record's text.
   - **T3** — bar Copy: 83 paste lines == 83 visible question rows; every line
     exactly 4 tab-separated fields; first field matches `HH:mm`; status
     `Copied 83 rows to the clipboard.`
   - **T4** — popup titles `All agents (83)`, `Claude Code (77)`,
     `Codex (6)`, `Hermes (0)`; 77+6+0 == 83; selecting an agent leaves the
     titles unchanged, narrows rows to 77, restoring returns to 83; a keyword
     moves counts with the total (no-match → all 0).
   - **T5** — no-match keyword → `No questions match.` shown, status
     `0 questions`, 0 rows; clearing the keyword hides the label and restores
     the counts.
   Corroborated pre-lock by real-window captures + OCR: status line
   `83 questions · read 30.8 MB · covers Claude Code, Codex, Hermes · nothing
   is saved`, the popup titles above, and both Copy buttons at their
   expected positions.
4. README claims re-checked against the build (F.4): counts format, detail
   pane, TSV Copy, agent-filter counts all demonstrated; the wording `full
   question` was dropped (stored text is capped at
   `QuestionRecord.maxLength`).

### Code gate — closed, unanimous (2026-09-27)

Diff under review: `git diff a530ab8` — exactly 3 files (`README.md`,
`Sources/VibraApp/HistoryWindowController.swift`,
`Sources/VibraApp/MenuBarController.swift`), 322 lines; sha256
`7e421da838ae90392d3df408bedaa35a8593e1c8979209ac7963e7e7a4b60ce8`
(`impl-r1.diff` in the fleet scratch dir). Prompt byte-identical for both
seats, only the verdict filename differed.

| Round | reviewer-nemotron | reviewer-ling | Notes |
|---|---|---|---|
| 1 | `IMPL-APPROVED` | `IMPL-APPROVED` + 1 non-blocking | verdict files `nemotron-impl-1.md`, `ling-impl-1.md` (scratch dir; read back in full, freshness-checked) |

reviewer-ling's non-blocking item: the `openRow` comment
(`HistoryWindowController.swift:368`, "the full question on the pasteboard")
is wording the plan now states more precisely. It is **pre-existing** — the
same line exists at BASE (`HistoryWindowController.swift:197` at `a530ab8`)
and the diff only carries it as context — and editing the reviewed file now
would change the approved diff revision, so it is recorded as a follow-up
instead of folded in.

**mimo: IMPL-APPROVED** against the same diff revision. Implementation
matches T1–T6 and E0 row 10; `swift build` clean, `make test` 156 + canary;
snapshot privacy and pixel probes confirmed; T1–T5 acceptances recorded in
the Verification section above (38/38 PASS on both selftest branches);
README claims re-checked.

---

## H. Wave 2 follow-up (implemented in the same commit)

After wave 1 landed, the following were also added while staying inside the
same constraints:

- Transcript path row with **Copy Path** and **Open** buttons in the detail
  pane.
- Session id in the detail meta line.
- On-demand **Tasks** and **Timeline** disclosure sections for Claude Code,
  read only on selection, capped at 12/60 rows, released on window close.
- Window shortcuts: `⌘F` (focus search), `⌘⇧C` (copy visible rows), `⌘J`
  (jump selected row), `Esc` (clear search).
- Tests: `HistoryDetailTests.swift` (8 new), plus coverage in
  `QueryAndHistoryTests.swift`.

Verified: `swift build` clean, `make test` 164 tests + canary; in-process
selftest driver 40/40 PASS on selection metadata, path row, sections, both
disclosure toggles, keyboard handlers, and close/reopen clearing.
`--show-history --snapshot` still prints status and day headers only.

---

## I. Phase 3 — next steps

Almost all of `the reference dashboard`'s patterns that fit Vibra's
constraints are now in place. Remaining opportunities:

1. **Extend Tasks/Timeline to Codex.** Inspect `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` for todo/task structure and tool-call events. Only enable if the format exposes tool names without arguments.
2. **Extend Tasks/Timeline to Hermes.** Inspect `~/.hermes/state.db` schema for tool-call roles or task tables without reading new sensitive columns.
3. **Copy buttons for Tasks and Timeline sections.** Small buttons beside each section header to copy the rendered task/event list.
4. **Clickable path label.** Single-click opens the transcript file; right-click menu with Open, Copy Path, Reveal in Finder.
5. **Copy Report button in Usage Report window.** Copies the rendered report text to the pasteboard, matching the History window Copy pattern.

### Out of scope (unchanged)

- Dark theme / tinted source pills / status chips (P1).
- KPI summary strip / dashboard window (P2).
- SQLite persistence / Excel export (P3).
- Standalone attention panel (P2).
- Quick-range date chips / inline filter pill groups (the popup-with-counts design works).
- Workspace filter group.

### Acceptance criteria for Phase 3

- `make test` and `swift build` stay green.
- `renderedText` still contains no question text, task text, or timeline detail.
- Any new adapter detail path keeps the existing security contract (status path does not read content).
- Copy actions put exactly the rendered text on the pasteboard.
- Codex/Hermes support is only enabled after real-format verification; unsupported agents keep their sections hidden.
