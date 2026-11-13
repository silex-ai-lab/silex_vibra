# OSS growth plan — status

Resume point for [OSS-GROWTH-PLAN.md](OSS-GROWTH-PLAN.md). Update this file at
the end of every session.

**Last updated:** 2026-11-13 · **Baseline commit:** `af95fc0` (branch
`feat/release-and-test-integrity`, not merged) · **Repo stats:** not rechecked
in this run (the run makes no network request); the last recorded figure, 1
star, is from 2026-10-01 and is stale.

## Items

| # | Item | State | Notes |
|---|---|---|---|
| 1 | Signing and distribution | **Pipeline built, awaiting certificate** 2026-11-13 | Owner chose Developer ID; enrollment due about 2026-11-15. Universal hardened DMG, CI dry run green (run 43382966703), tag-only `release.yml`. Waits on Apple enrollment and the 8 secrets (`docs/RUNBOOK-developer-id.md`), then plan task 14. Unblocks #10 listing and launch. |
| 2 | First-screen demo | Not started — owner | Needs a real screen recording with live sessions. |
| 3 | Outcome headline | **Done** 2026-09-28 (branch `oss-growth-day1`, not yet pushed) | |
| 4 | Slim README | **Done** 2026-09-28 (not yet pushed) | 149 lines; moved to `docs/features.md`, `troubleshooting.md`, `development.md`, `privacy.md`, `CHANGELOG.md`. |
| 5 | Two-minute first success | **Done** 2026-09-28 (not yet pushed) | Scoped to Claude Code / Codex. |
| 6 | Privacy block | **Done** 2026-09-28 (not yet pushed) | Full text verbatim in `docs/privacy.md`. |
| 7 | State consistency | **Partly done** 2026-09-28 | README/ROADMAP/STATUS reconciled. **Pending owner:** edit the 2026-09-27 Release body (source-only note, two dead links). |
| 8 | Per-agent guides | **Done** 2026-09-28 (not yet pushed) | `docs/agents/*.md`, per-state evidence. Follow-up: record a live Claude Code observation. |
| 9 | Topics / homepage | **Pending owner go-ahead** | Topics proposed in the Day-1 plan. Homepage after #1. |
| 10 | `--query` + skill ecosystem | **Example done** 2026-09-28 | In `docs/features.md`; listing after #1. |
| 11 | CONTRIBUTING + issue templates | Not started | After #1. |

## Open decisions

- **Developer ID**: the owner chose it and asked for a runbook (2026-11-12).
  Enrollment (Organization or Individual) waits about two days from
  2026-11-13, then the runbook's secrets.
- **Launch**: post only after plan task 14 passes. Copy and checklist are in
  [LAUNCH-KIT.md](LAUNCH-KIT.md).

## How to resume

1. `git pull`, then read this file and `OSS-GROWTH-PLAN.md`.
2. If README line numbers above no longer match, re-verify the facts in the
   plan's "Facts verified" section against the new HEAD before editing.
3. Take the next Day 1 item; show the README diff to the owner before pushing.
4. Record progress, the new baseline commit and the date here.

## Log

- 2026-09-28 — Plan finalized (internal checklist + benchmark review merged).
  No README or product changes yet.
- 2026-09-28 — Day 1 executed on branch `oss-growth-day1` (base `d40c4fb`)
  with the three-seat Herdr fleet: #3–#6, #8, #10 example, #7 except the
  Release body. Record: [PLAN-2026-09-28-oss-growth-day1.md](PLAN-2026-09-28-oss-growth-day1.md).
- 2026-10-01 — README restyled on the Agent Reach template (centred header,
  badges, "Why Vibra?", "Before you install", agent icons from Lobe Icons,
  design principles) and translated into zh-CN, ja and ko at the owner's
  request, reversing the growth plan's "no translated READMEs". Branch
  `readme-agent-reach-style`, base `6840769`. Record:
  [PLAN-2026-10-01-readme-restyle-i18n.md](PLAN-2026-10-01-readme-restyle-i18n.md).
- 2026-11-13. Release pipeline and test-edit evidence built on branch
  `feat/release-and-test-integrity` with the orca fleet (recorded in
  `docs/PLAN-2026-11-12-release-and-test-integrity.md`). Code checks says
  when test-file edits between a failed and a passing run changed its
  test-pattern counts; it fired
  0 times on the owner's 30-day data (plan task 4). Review Agent Activity names
  related OWASP Agentic categories. 563 tests pass. Pending: task 11 live check
  of the hardened build, the code gate, then task 14 after enrollment.
