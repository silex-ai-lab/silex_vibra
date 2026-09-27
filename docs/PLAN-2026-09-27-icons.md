# Plan — Add SF Symbols icons to Vibra UI surfaces (2026-09-27)

Status: plan gate closed unanimous at round 1; implementation complete and
verified 2026-09-27; **code gate closed unanimous at round 1**. Ready to
commit.

## Why

Vibra's windows are text-only. Small system-native icons on toolbar controls
make repeated actions faster to recognize. The goal is not decoration: every
icon must clarify an action or state.

## Grounding (repo read, 2026-09-27 — corrections to the v1 draft)

| # | v1 claim | Ground truth |
|---|---|---|
| G1 | "Report Copy button ... already listed as T5 in `PLAN-2026-09-27-history-ui.md`" | Wrong. That plan's T5 is the *No questions match* empty-state label. The report window (`ReportWindowController.swift`) has no toolbar and no buttons at all — it is one read-only `NSTextView`. Adding a Copy button there is a **new feature**, not an icon addition. |
| G2 | "Vibra targets macOS 15, so the availability check is defensive" | `Package.swift` declares `platforms: [.macOS(.v14)]`. SF Symbols API is macOS 11+; no `#available` guard is needed. |
| G3 | Buttons described generically | The four buttons are plain `NSButton()` with titles set in `HistoryWindowController.swift` (`copyRowsButton`, `copyDetailButton`, `copyPathButton`, `openPathButton`), living in horizontal `NSStackView`s. Section headers are a `.disclosure`-bezel `NSButton` + a title `NSTextField` in a stack (`tasksRow`/`timelineRow`, spacing 4) — added in wave 2 precisely because the disclosure bezel sizes to the triangle alone. |
| G4 | — | No `NSImage(systemSymbolName:)` use exists anywhere in `Sources/` yet; this plan makes the first. `AgentKind.symbolName` (SF Symbol names) exists in VibraCore but is unused. |

## Constraints (same as the History UI work)

- **P1 native first.** SF Symbols or system-provided images; no custom drawn
  icons, no imported asset bundles.
- **P2 the menu bar stays the glance surface.** Icons there, if any, must not
  reduce information density.
- **P3 zero new persistence.** Icons are a view concern; no state saved.
- **P4 claim discipline.** Diagnostics and `renderedText` stay content-free.
- **P5 terse.** No icon where text already says everything.

## Scope decisions (v1 sections 1–5, optimized)

### IN — 1. History window buttons (4 controls)

| Button | Symbol | Rationale |
|---|---|---|
| Copy (visible rows) | `doc.on.doc` | The system copy glyph. |
| Copy (question detail) | `doc.on.doc` | Same action, same glyph. |
| Copy Path | `link` | Distinguishes from plain Copy; a path is the file's link. |
| Open | `arrow.up.forward` | The system's "open outwards" arrow, next to the word Open. |

Layout pins: keep every text label; set `image = …` and
`imagePosition = .imageLeading`. An unresolvable name yields a nil image —
the button renders exactly as today (text-only fallback is automatic).

### IN — 2. Section header symbols (Tasks / Timeline)

| Section | Symbol |
|---|---|
| Tasks | `checklist` |
| Timeline | `clock` |

P5 check: the words stay — the symbol is a pre-reading cue in a row that
otherwise reads `▸ Tasks` three glyphs into a 120 pt section. The symbol goes
in the existing stack as its own `NSImageView` between the disclosure button
and the title label (`[triangle, icon, word]`, spacing 4, centerY): the
`.disclosure` bezel must not carry an image — its cell draws the triangle.

### NOT DOING — 3. Menu bar status item

Option A of v1: keep `Vibra 2▶ 1!` text exactly. The counts are the glance
surface; a static icon adds no information (P2, P5). Deferred with prejudice.

### NOT DOING — 4. Emoji state dots

The emoji (🔵🟠🔴🟡⚪️) are established, compact and colored. Replacement
buys nothing and needs template tinting machinery. Deferred.

### OUT — 5. Usage Report Copy button

v1 justified this with the false T5 reference (G1) and with "add to the
report toolbar" — there is no toolbar. A Copy-the-report action is a
legitimate feature but belongs in its own plan (it invents a control rather
than iconizing one). Not in this change.

## Implementation approach

1. Helper, file-private in `HistoryWindowController.swift` (the only file
   that needs it):

   ```swift
   private extension NSImage {
       /// nil when the name does not resolve: every caller keeps working
       /// as a text-only button.
       static func vibraSymbol(_ name: String, description: String) -> NSImage? {
           NSImage(systemSymbolName: name, accessibilityDescription: description)
       }
   }
   ```

   No `#available` (G2). `accessibilityDescription` carries the button's
   title so the image is never an unnamed picture to VoiceOver.

2. Buttons: `image = NSImage.vibraSymbol(<name>, description: <title>)`,
   `imagePosition = .imageLeading`. Titles unchanged.

3. Section rows: an `NSImageView` per row with
   `NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)`,
   inserted between triangle and title; template rendering by default, so it
   follows light/dark like the text beside it.

4. Nothing else moves: no constraints change (stacks size themselves), no
   menu bar change, no report change, no persistence.

## What is out of scope

- Custom drawn icons, imported PNG/SVG assets, animated icons.
- Menu bar status item; emoji state dots (both deferred above).
- Report window Copy button (own plan).
- Tinted source pills (rejected in earlier plans).

## Acceptance criteria

- `swift build` and `make test` green (165 tests + canary — 164 at wave 2
  plus `canJumpIsPinnedPerAgent` from `22286f3`; the icons add no tests).
- Every title/label byte-identical to before; `--show-history --snapshot`
  still 980×568, 175 chars, 7 lines (P4).
- A window snapshot PNG shows the six symbols drawn beside their labels;
  with any symbol name misspelled the build still succeeds and that control
  stays text-only.
- Report window, menu bar rows, emoji dots untouched.
- Screens: one eyeballed snapshot pass (works with the screen locked);
  live hover/voiceover checks recorded as not performed if the screen is
  still locked.

## Files likely to change

- `Sources/VibraApp/HistoryWindowController.swift` — the only code file.
- `README.md` — one clause noting icon buttons (History section).
- `docs/STATUS.md` — record the change at commit time.

No unit test: the symbol names are view-layer detail in `VibraApp`, which has
no test target (tests cover VibraCore only); the resolution tripwire is the
snapshot pass. Flagged for the gate in case a reviewer wants one.

## Recommended order

1. Helper + the four button icons.
2. The two section-header icons.
3. README clause.
4. Build, tests, snapshot eyeball, then the code gate.

## Verification record (post-implementation, 2026-09-27)

- `swift build` clean; `make test` = **165 tests + canary** green.
- Snapshot contract after the final tree: `--show-history --snapshot` prints
  `980x568 / 175 chars / 7 lines`, first lines = footer + the five day
  headers (P4). The `.png` is 1960×1080 (Retina 2× of the 980×568 frame).
- Six symbols eyeballed in a flattened window snapshot
  (`/tmp/icons-expanded-flat.png`): filter Copy `doc.on.doc`, detail Copy
  `doc.on.doc`, Copy Path `link`, Open `arrow.up.forward`, Tasks `checklist`,
  Timeline `clock`. Rows read `[triangle, icon, word]`, both 120 pt sections
  open, question/meta/path text and both empty-state strings intact.
  `/tmp/icons-history.png` (at rest) shows the two Copy icons with no
  question text.
- Method note: a temporary `--icons-check` scaffold (extension on
  `HistoryWindowController` + delegate in `main.swift`) drove programmatic
  row selection and section expansion for the snapshot, since the screen is
  locked and real input injection is blocked. The scaffold was deleted
  before this record; `main.swift` is byte-identical to HEAD and the
  remaining diff is the icon change only.
- Not performed (recorded per acceptance): live hover/tooltip check —
  `CGSSessionScreenIsLocked = 1`, real input injection blocked. The gray-row
  tooltip text shipped earlier is verified by code and screenshot only.
- Installed: `make install` → `/Applications/Vibra.app` relaunched (pid
  37374) on the icon build.

## Review record

| Round | Seat | Verdict | File |
|---|---|---|---|
| 1 | reviewer-nemotron | **PLAN-APPROVED** (G1–G4 verified line by line; scope and design pins hold) | `nemotron-icons-1.md` |
| 1 | reviewer-ling | **PLAN-APPROVED** (grounding, P1–P5, layout and acceptance all verified; one non-blocking note) | `ling-icons-1.md` |
| 1 | mimo (author/implementer) | **PLAN-APPROVED** | this file |

Plan gate closed unanimous at round 1, 2026-09-27. Reviewers read this file
and the `silex_vibra` tree only.

Ling's non-blocking note: it read 165 as a typo for the wave-2 baseline of
164. Resolution: 165 is correct — `22286f3` added
`canJumpIsPinnedPerAgent` after wave 2, and this plan adds no tests. The
acceptance line now spells out the arithmetic.

### Code gate (round 1, 2026-09-27)

Prompts byte-identical across seats after seat-token normalization (diffed
before sending); reviewers read the plan + this repo only.

| Seat | Verdict | File |
|---|---|---|
| reviewer-nemotron | **IMPL-APPROVED** (C1–C7 all pass; one non-blocking layout note) | `nemotron-icons-2.md` |
| reviewer-ling | **IMPL-APPROVED** (C1–C7 all pass with `make test` run independently; no notes) | `ling-icons-2.md` |
| mimo (author/implementer) | **IMPL-APPROVED** (build/tests/snapshot/eyeball verified above) | this file |

Code gate closed unanimous at round 1, 2026-09-27. Nemotron's non-blocking
note: section stack spacing stays 4 pt and the symbol `pointSize: 11` sits
beside `smallSystemFontSize` — accepted as intentional (matches the plan's
layout pin).
