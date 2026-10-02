# Vibra open-source growth plan (final, 2026-09-28)

Merges two inputs:

- an internal 10-item repository optimization checklist (2026-09-28), and
- a benchmark review against comparable OSS launches (Browser Use, OpenCode,
  Promptfoo, Langfuse, Superpowers, uv, Cline), done with the
  `benchmark-open-source-growth` review method.

Every claim about Vibra below was checked against commit `7d8ae07` on
2026-09-28. Progress is tracked in [STATUS.md](STATUS.md).

## Goal and conclusion

The goal is **installs and repeat use**, not raw stars. Stars are an attention
signal; each item therefore has a funnel metric as its success signal.

The binding constraint is the lack of a signed, downloadable build — not the
README. The README can be fixed in a day, but **do not promote Vibra
(Show HN, social posts, skill directories) until a user can install it in two
steps and receive notifications.**

## Facts verified at `7d8ae07`

- **README contradicts the code.** README line 538 says "No weekly report card",
  but the usage report exists (`Sources/VibraCore/Report/UsageReport.swift`,
  `Sources/VibraApp/ReportWindowController.swift`) and ROADMAP marks P1.3 Done.
  The README is wrong.
- **Developer ID fixes more than distribution.** README line 525: an ad-hoc
  signed bundle is refused notifications by default on macOS 15.7.3 and 26, and
  each rebuild can re-trigger the Automation prompt that terminal jump-back
  needs. One signature fixes install trust, notifications and permission churn.
- **The 2026-09-27 Release has no assets.** It reads as downloadable but is not.
- No `CONTRIBUTING.md`, no `.github/` issue templates.
- Repository topics are empty; no homepage is set.
- README is ~663 lines; the Install section starts at line 176.

Found while executing Day 1 (checked at `d40c4fb`, recorded in
[PLAN-2026-09-28-oss-growth-day1.md](PLAN-2026-09-28-oss-growth-day1.md)):

- A second stale claim, README line 659: "Not yet done: weekly report cards".
- The README never documented **Usage Report…** (⌘U).
- The 2026-09-27 Release body links two files that do not exist in the repo.
- Not every agent can show every state: Vibra reads no approval state from
  Codex or Hermes; OpenCode never shows your turn or stalled; a stalled Cursor
  turn is shown idle. Click-to-jump is per agent (none for OpenCode/Hermes).
- No live observation of Claude Code's states is recorded in the docs; only
  Codex working → your turn, and VS Code / Cursor's live-tested states.
- `docs/ROADMAP.md` and `docs/STATUS.md` contradicted the README on VS Code
  live testing, P2.2 and herdr jump-back.

## Plan

| # | Pri | Item | Change | Scope / dependency | Success signal |
|---|---|---|---|---|---|
| 1 | **P0 — owner decision** | Signing and distribution | Developer ID (USD 99/yr) → sign + notarize → attach `.dmg`/`.zip` to Releases → Homebrew cask in an own tap. README leads with the shortest install; source build moves to "Build from source". | Product/distribution; blocked on ROADMAP P3.1 | Download → installed rate; installs with working notifications |
| 2 | P0 | First-screen demo | 15–25 s real screen recording under the title: several agents running → one finishes → menu bar shows `1!` → click jumps to the session. Plus one static screenshot. Keep the ASCII sketch lower down. | README + assets; must be a real recording, no placeholder | Repo visit → install click |
| 3 | P0 | Outcome headline | e.g. "Know when your coding agents need you." Subtitle: a macOS menu-bar app that shows working / your-turn / needs-approval for Claude Code, Codex, Cursor, VS Code, OpenCode and Hermes sessions. | README only | Click-through when shared |
| 4 | P0 | Slim README | Front page order: demo → who it is for → 3 core abilities → compatibility table → install → privacy → contributing. Move signing-for-development, per-adapter formats and long troubleshooting to `docs/`. Target < 150 lines. Move, don't delete. | README + docs | Scroll depth; install link clicks |
| 5 | P1 | Two-minute first success | Right after install: start an agent → watch the menu bar or run `make probe` → let a turn finish → see 🟠 your turn. State that an empty menu with no recent sessions is expected. | README only; reuses `make probe` | Time to first state change; fewer "empty menu" issues |
| 6 | P1 | Privacy block | "What Vibra reads / What it never does": reads local session files only; no network at all (no account, telemetry or update ping); installs nothing into agents; never approves actions for you. Link the canary tests. **Wording must match README lines 396–422 exactly.** | README only | Fewer trust questions before install |
| 7 | P1 | State consistency | Delete the stale "No weekly report card". Align README, ROADMAP and Release text; distinguish "has a release entry" from "has a downloadable app". Put unverified states (Cursor your-turn/needs-approval, OpenCode blocked, Hermes live states) in compatibility-table footnotes. | README + ROADMAP + Release notes; **do together with #3 and #4** | No self-contradictions |
| 8 | P1 | Per-agent guides | `docs/agents/<agent>.md` for all six: states shown, verified vs. unverified, limits, how to check it yourself. Linked from the compatibility table. | Docs; no adapter changes | Long-tail search traffic |
| 9 | P1 | Discoverability | Topics: `claude-code codex cursor opencode github-copilot macos menubar ai-agents developer-tools`. Homepage once a download page exists. | Repo settings; 10 min | Visits from GitHub search |
| 10 | P2 | `--query` and skill ecosystem | Short example: a coding agent calls `--query --attention` to answer "which session needs me?"; explain the JSON carries state, never message text. Submit `docs/skills/vibra-query` to skill directories only after #1. | README + ecosystem; listing depends on #1 | Installs via the skill |
| 11 | P2 | Contribution entry | `CONTRIBUTING.md` + issue templates; bounded tasks such as "verify state changes on Codex version X", "provide a redacted format sample". New adapters must pass a privacy canary test and a live check. | Collaboration; ongoing | Useful issues/PRs; external live-test reports |

## Sequence

1. **Day 1:** #3, #4, #5, #6, #7, #9 — text and settings only, no dependencies.
   Owner records the GIF for #2 and decides #1.
2. **This week:** #8. If #1 is approved: sign, notarize, Release assets, cask.
3. **After distribution is ready:** #10, #11, then launch posts (Show HN etc.)
   built on the "stop watching five terminals" scene and the "local-only,
   no network" differentiator.
4. **Not doing:** promotion while install is source-only; ~~translated READMEs~~
   (reversed 2026-10-01 at the owner's request: zh-CN, ja, ko added — see
   [PLAN-2026-10-01-readme-restyle-i18n.md](PLAN-2026-10-01-readme-restyle-i18n.md));
   a plugin marketplace of our own.

## Differences from the internal checklist

- Ranked by funnel metrics instead of "effect on stars".
- Added #9 (topics/homepage).
- #1 now records that signing also fixes notifications and permission churn.
- #7 pinned to line numbers and resolved: the README is the stale side.
