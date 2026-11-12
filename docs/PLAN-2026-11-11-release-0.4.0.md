# Plan: release 0.4.0

Plan version 0.5, 2026-11-11. Branch `release/0.4.0`, base 839b6d8 (the head
of PR #8, identical in code to what `main` gets once the landing PR merges).

## Why this is the next task

Homebrew users run 0.3.0. The tap formula pins commit 9ad00e6 (measured,
`silex-ai-lab/homebrew-tap` `Formula/vibra.rb`). Four user-facing changes have
merged since and sit under "Unreleased" in `CHANGELOG.md`: the first-use loop
(#5), Return to Session in Orca (#6), Code checks in Session Details (#7) and
Review Agent Activity (#8). None of them reaches a Homebrew user until a release
moves the pin.

Four gaps stand between `main` and a release that tells the truth.

1. **#8 never reached `main`** (measured). It was stacked on
   `feat/delivery-evidence`, which merged first, so #8 merged into that branch.
   `git diff --stat origin/main 839b6d8` shows 33 files and 12668 lines missing.
   A landing PR from `feat/unauthorized-usage-monitor` to `main` fixes it. Its
   code diff has the same `git patch-id --stable` as the fleet-approved #8
   diff (`bb11c6cfc165`). Opening it needs the user (the sandbox refused the
   write), so it is a precondition here, not a task.
2. **A known false finding in the vendor usage import** (recorded as
   "Left for later" in `PLAN-2026-11-09-agent-incidents.md`). A bucket dated
   after the current UTC day is compared with local usage, which is zero for
   that day, so it can be flagged as usage this Mac cannot explain.
3. **Docs drift** (measured by grep). The English README does not mention Code
   checks. The zh-CN, ja and ko READMEs mention neither Code checks nor Review
   Agent Activity, omit Orca from the jump-back list, and their privacy sections
   omit `incidents.json`, the first file Vibra persists beyond preferences. All
   four READMEs say "To remove it completely: `make uninstall`", but that target
   deletes only `/Applications/Vibra.app`; `incidents.json` and the preferences
   domain stay. ROADMAP lists P3.3 Homebrew cask as "Not started" although a
   source formula ships, and P3.2 Sparkle as "Not started" although an
   auto-updater contradicts the "no network egress at all" promise. STATUS still
   names 0.3.0 as unreleased on an old branch and has no rows for P4.6 or P4.7.
4. **The changelog has no 0.3.0 section** (measured, `git show v0.3.0:CHANGELOG.md`).
   At the tag, "Unreleased" already held performance suggestions, the Claude
   Code token-count fix and the README restyle. Renaming today's "Unreleased"
   to 0.4.0 would call shipped 0.3.0 work new.

## Fleet

Roster `standard`, planner Claude (Opus 5.5), DeepSeek V4.1 Flash through
OpenCode, Codex as third judge. Transport Orca. Both gates unanimous.
`$SCRATCH` is `/var/folders/x3/8mdzc51d11j_z0l1mt77lpmr0000gn/T/fleet-EwKeLz`.
Shared working tree, no concurrent writes to one file.

| Owner | Files, and nothing else |
|---|---|
| planner | `Sources/VibraCore/Incidents/VendorUsage.swift`, `Tests/VibraCoreTests/VendorUsageTests.swift`, `docs/features.md`, `docs/privacy.md`, `README.md`, `docs/ROADMAP.md`, `docs/STATUS.md`, `Makefile`, `CHANGELOG.md`, `docs/releases/v0.4.0.md`, this plan |
| deepseek | `README.zh-CN.md`, `README.ja.md`, `README.ko.md`, and the anchor script `tools/readme-anchors.sh` |

Record paths (reviewed as evidence, not as the implementation): this plan.

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Version 0.4.0, git tag `v0.4.0`, matching the tap's `version "0.3.0"` and tag `v0.3.0` | Semver minor: new features, no removed ones. The dated tags (2026-09-2x) predate the tap and are not continued |
| D2 | A bucket whose UTC day is after the current UTC day and that has at least one result row refuses the whole file with a new `VendorImportError.futureDay`, like `partialPage` and `tooOld`. A future bucket whose row counts zero tokens is refused too. A future bucket with an empty `results` list is padding and is dropped, neither refused nor compared (amended in v0.5, see below). The future-day check runs before the age check, so a file that is both too old and future-dated throws `.futureDay`. The error text names no day and no value from the file: "A day in this file is after today (UTC). Fetch a page that ends today or earlier." | One policy for every malformed page: refuse, never compare part of it. A bucket's start is an absolute instant (Anthropic `starting_at` ISO 8601, OpenAI `start_time` Unix seconds), and Vibra buckets it by UTC day, so a day after today's has not happened. `reconcile` today compares such a day with zero local tokens (`VendorUsage.swift:292` only skips the current day). Keeping the file's values out of error text is the contract at `VendorUsage.swift:42-43` |
| D3 | ROADMAP P3.3 is renamed "Homebrew distribution" and marked "Done (source formula)". A prebuilt, signed cask still needs P3.1. The row records why the "depends on P3.1" rule does not apply to a source formula | The formula builds from source on the user's Mac, so no unsigned binary is distributed. Its caveat says the build is ad-hoc signed |
| D4 | ROADMAP P3.2 Sparkle becomes "Cut". Tap users update with `brew upgrade`; source installs update with `git pull` and `make install` | P1.2 decided "no network, ever". An updater is network egress by definition. This is a product decision the user can overturn |
| D5 | Translations carry the same claims as the English README, not a word-for-word copy. Every claim the English README makes about features, jump-back targets, privacy and removal appears in each translation | The readme-restyle-i18n convention. Each reviewer reads the translated privacy and removal text against the English |
| D6a | `make uninstall` keeps its behaviour. Each README gets one "Removing Vibra" block, placed after both install paths, that covers both (`brew uninstall silex-ai-lab/tap/vibra` or `make uninstall`) and gives the two commands that remove saved data: `rm -rf ~/Library/Application\ Support/Vibra` and `defaults delete ai.silexlab.vibra`. `docs/privacy.md:7-9` and `docs/STATUS.md:304` name the two data-removal commands instead of saying removal is deleting the app. All four READMEs write the `rm -rf` path in exactly that escaped form | Deleting a user's saved answers from a Makefile target is a destructive change nobody asked for. Docs that tell the truth are the smaller change |
| D7 | CHANGELOG gets a retroactive `## 0.3.0 — 2026-11-07` section holding exactly the three bullets present at the tag plus the Homebrew bullet (the formula installs 0.3.0). `## 0.4.0` holds everything else under "Unreleased" plus this plan's changes. No date on the 0.4.0 heading; the tag and GitHub release carry it, as `## 0.1.0` already does | The section boundary follows the tag, not the file's current layout. A date written before the merge cannot be verified |
| D6 | Publishing (tag, GitHub release, tap bump) is a separate step that waits for the user after the code gate | It is outward-facing and pushes a binary-producing change to every Homebrew user |

## Tasks

Each task ends in a check. Commits are small and conventional.

| # | Owner | Depends on | Task | Files | Acceptance |
|---|---|---|---|---|---|
| 1 | planner | — | Failing tests first, then refuse future-dated buckets | `Sources/VibraCore/Incidents/VendorUsage.swift`, `Tests/VibraCoreTests/VendorUsageTests.swift`, `docs/features.md` import paragraph | For each shape (Anthropic, OpenAI), with `now` at 12:00Z and again at 23:59:59Z: a bucket on the current UTC day imports, a bucket on the next UTC day throws `.futureDay`, a zero-token next-day row throws `.futureDay`, empty next-day buckets after a past day are dropped and the file imports, and a file mixing a past day with a next-day bucket throws `.futureDay` (no partial import). The new tests fail on the base, and the commit message quotes the assertion's diff. `errorTextNeverEchoesAKeyOrAValue` covers `.futureDay` and passes. A file both too old and future-dated throws `.futureDay`. `features.md` names the refusal |
| 2 | planner | — | English README | `README.md` | "More it can do" gains a Code checks bullet linking `docs/features.md`, which must not contradict "It never says a task is done", and a Review Agent Activity bullet. Both name "Claude Code and Codex". "To remove it completely" becomes the D6a "Removing Vibra" block |
| 3 | deepseek | 2 | Translated READMEs | `README.zh-CN.md`, `README.ja.md`, `README.ko.md`, `tools/readme-anchors.sh` | Each translation has the Review Agent Activity table row, both "More it can do" bullets, Orca in the jump-back list, the whole `incidents.json` privacy bullet (hashed ids and answers stored, a vendor report is a local draft only you send) and the D6a removal text. `tools/readme-anchors.sh` (executable, run as `tools/readme-anchors.sh` from the repo root) checks each of the four READMEs for the fixed strings `Review Agent Activity`, `Code checks`, `Orca`, `incidents.json`, `rm -rf ~/Library/Application\ Support/Vibra`, `defaults delete ai.silexlab.vibra`, `⌘U`, `⌘Y`, prints a table, and exits non-zero on any gap |
| 4 | planner | — | ROADMAP, STATUS, privacy | `docs/ROADMAP.md`, `docs/STATUS.md`, `docs/privacy.md` | ROADMAP P3.2 and P3.3 rows and sections per D3 and D4. STATUS: (a) a new 0.4.0 entry, placed as the page's newest version entry, names the version, lists the four changes and the future-day fix, and carries the verification Task 6 measures with its date, macOS and Swift versions, like the older entries; (b) the 0.3.0 entry keeps its 2026-09-26 record and Phase 4 content, "(unreleased; branch …)" becomes "released 2026-11-07, tag `v0.3.0`", and one clause says the performance and token-count work in the same tag was verified in its own plan; (c) the capability table gains P4.6 and P4.7 rows and its P3 rows match ROADMAP; (d) the Verdict no longer says everything remaining is blocked on P3.x; (e) "Five adapters" becomes six, naming Hermes with its fixture-only states; (f) the Tests row carries Task 6's measured "N tests in M suites", taken from the `Test run with N tests in M suites passed` line in `build/test.log`. (g) `docs/STATUS.md:304` ("removing it is deleting one `.app`") and `docs/privacy.md:7-9` name the two data-removal commands. Sweep check: `grep -n -i -E "deleting one|remove it completely|whole uninstall" README*.md docs/*.md` finds no line outside `docs/PLAN-*` and `docs/development.md:116` (which is about the local signing key) that calls deleting the app complete removal |
| 5 | planner | 1, 2, 3, 4 | Version and notes | `Makefile` `VERSION := 0.4.0`, `CHANGELOG.md` per D7, `docs/releases/v0.4.0.md` | `make app` produces a bundle whose `CFBundleShortVersionString` reads 0.4.0 (read with `plutil`). `git show v0.3.0:CHANGELOG.md` and the new 0.3.0 section hold the same three bullets, and the 0.4.0 section holds none of them. The release note lists the changes since 0.3.0, names `incidents.json` and the D6a removal commands (also one 0.4.0 CHANGELOG bullet for the corrected removal docs), says Homebrew users upgrade with `brew upgrade silex-ai-lab/tap/vibra`, what was verified, and the limits still open (ad-hoc signing, notification delivery unverified, vendor import tested on documented shapes only) |
| 6 | planner | 5 | Full verification | `docs/STATUS.md` 0.4.0 entry and Tests row | `make test SWIFT_BUILD_SYSTEM=native` passes with the four canaries, and its counts go into STATUS. `tools/readme-anchors.sh` exits 0. `make install`, then the installed binary's `--incidents --days 7` and `--query` exit 0 |

## Publishing, after the code gate and only with the user's go-ahead

1. The user merges the landing PR, then the `release/0.4.0` PR.
2. Tag `v0.4.0` on the merge commit and create the GitHub release from
   `docs/releases/v0.4.0.md`. Source-only, like earlier releases.
3. Open a PR on `silex-ai-lab/homebrew-tap` that moves `url` to the tag's
   archive, sets `version "0.4.0"` and the `sha256` of the downloaded archive.
   Check it with `brew audit --strict` and a local
   `brew install --build-from-source` of the edited formula, `brew test vibra`
   (its test block compares the formula version with the bundle's), then
   `vibra --query`. Update the tap README in the same PR if it names 0.3.0.
4. Close PR #1 (`orca-jump-back`), which #6 superseded. Ask first.

## Not in this change

- Developer ID signing (P3.1). It still needs a paid Apple account, a user
  decision.
- Any network feature, including an opt-in vendor API call.
- OpenClaw (P4.5) and the OpenCode limits in STATUS.

## Risks

- The landing PR can merge with a conflict if `main` moves first. The branch
  is then merged with `main`, not rebased, as before.
- A translation can overclaim. Task 3's anchor table checks presence, not
  meaning, so each reviewer reads the translated privacy bullets against the
  English one.

## Review record

### Round-1 objections → changes

| Objection (who) | Change |
|---|---|
| Task 1 does not pin today accepted and tomorrow refused for each shape, at one second before midnight, nor a mixed-day file (Codex 1) | Task 1 acceptance enumerates all of these per shape |
| "To remove it completely: `make uninstall`" is false in all four READMEs (Codex 2) | Gap 3, D6a, Tasks 2 and 3, and the anchor set |
| Renaming "Unreleased" to 0.4.0 calls shipped 0.3.0 work new (Codex 3, DeepSeek 2) | Gap 4, D7, Task 5 acceptance. The 0.4.0 heading carries no date |
| The error text naming "the day" contradicts the no-file-values contract (DeepSeek 1) | D2 fixes the text, which names no day. `errorTextNeverEchoesAKeyOrAValue` covers the new case |
| STATUS acceptance can pass while STATUS contradicts the release (DeepSeek 3) | Task 4 names the four STATUS edits; Task 6 owns the Tests row |
| Translations omit Orca; privacy bullet must mirror the whole English bullet (DeepSeek 4) | Task 3 and the anchor set |
| Non-blocking, folded in: P3.3 rename (Codex, DeepSeek), error text says what to do (DeepSeek), zero-token future bucket (DeepSeek), anchor script exits non-zero (DeepSeek), update channel for source installs (DeepSeek), Code checks bullet must not overclaim (DeepSeek), `brew test` in publishing (DeepSeek) | D2, D3, D4, Tasks 1, 2, 3, publishing step 3 |
| Non-blocking, folded in: the evidence that a bucket start is an absolute instant, Anthropic ISO 8601 and OpenAI Unix seconds (DeepSeek) | D2 reason column |
| Non-blocking, declined: a second future-day guard inside `reconcile` (DeepSeek) | Boundary discipline: the import's parse is the boundary, and `reconcile` has no other caller that feeds it vendor days. Two guards would be two sources of truth for one rule |

### Round-2 objections → changes

Codex approved v0.2. DeepSeek rejected it.

| Objection (who) | Change |
|---|---|
| Task 4 passes by relabelling the 0.3.0 record as 0.4.0; the 0.4.0 entry need not list the release; "Five adapters" is false (DeepSeek 1) | Task 4 (a), (b), (e) |
| Non-blocking, folded in: `docs/privacy.md:7-9` removal text unowned (DeepSeek) | Planner owns `docs/privacy.md`; D6a and Task 4 |
| Non-blocking, folded in: two-sided CHANGELOG check (DeepSeek) | Task 5 |
| Non-blocking, folded in: anchor both D6a commands (DeepSeek) | Task 3 |
| Non-blocking, folded in: removal text visible to Homebrew users (DeepSeek) | D6a: one "Removing Vibra" block for both install paths |
| Non-blocking, folded in: release note names `incidents.json`, removal and `brew upgrade` (DeepSeek) | Task 5 |
| Non-blocking, folded in: how the suite count is measured (DeepSeek) | Task 4 (f) |
| Non-blocking, folded in: check precedence for too-old and future-dated (DeepSeek) | D2, Task 1 |
| Non-blocking, folded in: anchor script executable, invocation stated (DeepSeek) | Task 3 |
| Non-blocking, folded in: round-1 table missing the absolute-instant evidence (DeepSeek) | Round-1 table row |

### Round-3 objections → changes

DeepSeek approved v0.3. Codex rejected it.

| Objection (who) | Change |
|---|---|
| `docs/STATUS.md:304` still says removing Vibra is deleting one `.app` (Codex 1) | Task 4 (g) fixes it and adds a sweep grep over every README and doc, so no other copy survives. D6a names it |
| Non-blocking, folded in: "three gaps" with four items (DeepSeek) | "Four gaps" |
| Non-blocking, folded in: removal block placement (DeepSeek) | D6a: after both install paths |
| Non-blocking, folded in: name the agents in the new bullets (DeepSeek) | Task 2 |
| Non-blocking, folded in: privacy.md names the two data-removal commands, not the install paths (DeepSeek) | D6a, Task 4 (g) |
| Non-blocking, folded in: 0.4.0 STATUS entry is the newest entry (DeepSeek) | Task 4 (a) |
| Non-blocking, folded in: one escaped `rm -rf` form everywhere (DeepSeek) | D6a |
| Non-blocking, folded in: tap README, CHANGELOG bullet for the removal docs, a 0.3.0 STATUS clause (DeepSeek) | Publishing step 3, Task 5, Task 4 (b) |

### Plan gate: passed on v0.4 (sha256 prefix dfd6331dcd4351a4 before this record)

- DeepSeek (`deepseek-plan-r4`): PLAN-APPROVED
- Codex (`codex-plan-r4`): PLAN-APPROVED
- PLANNER (claude): PLAN-APPROVED

Round 4's non-blocking suggestions from DeepSeek are applied inside the approved
tasks without changing their scope, and the code gate reviews them: the anchor
script also asserts the three translated "complete removal" phrases are gone, the
removal block says to quit Vibra first and leaves no "remove it completely"
wording, STATUS's removal sentence is found by phrase, feature names stay in
English in the translations as they already do, the Homebrew paragraph gets a
one-line pointer to the block, and the tap caveats are checked in publishing.

### v0.5 amendment after the plan gate (needs confirmation)

While implementing Task 1 the planner read Anthropic's reference for
`GET /v1/organizations/usage_report/messages` (platform.claude.com, fetched
2026-11-11). `data` is "one per `bucket_width` interval, including intervals with
no usage (their `results` list is empty)", and the reference does not state that
intervals stop at the current time. The import window's own example command asks
for `starting_at=2026-11-01&limit=31`, a range that runs past today. Under v0.4's
D2 an empty bucket after today would refuse the exact page Vibra tells the user to
fetch (inferred risk, not observed: no real page was fetched). v0.5 keeps every
refusal v0.4 pinned for a bucket with a row, including a zero-token row, and drops
an empty future bucket instead. One test per shape pins the padding case.
Implemented in cb78085.

### Plan gate on v0.5: passed

- Codex (`codex-plan-r5`): PLAN-APPROVED
- DeepSeek (`deepseek-plan-r5`): PLAN-APPROVED
- PLANNER (claude): PLAN-APPROVED

DeepSeek's round-5 suggestions are applied in code: a too-old file with only
empty future days stays `.tooOld` (test added), and the padding guard was shown
to be pinned by removing it (both padding tests fail, 4838111).

### Code gate round 1 → changes

Both seats rejected revision 40d6aab.

| Defect (who) | Change |
|---|---|
| READMEs in four languages say Vibra has no window (Codex 1, DeepSeek 2) | All four now say it starts from the menu bar item and its windows open from that menu |
| STATUS "Secrets are never read" is false: Orca reads the start-up environment, incident and Code checks parsing read raw tool records (Codex 2, DeepSeek 1) | Reworded to "credential stores are not queried, secrets are not kept or emitted", naming both in-memory reads |
| STATUS Measured table and Verdict present 0.2.0 figures as current (Codex 3, DeepSeek 3) | Re-measured 0.4.0 on 2026-11-11 with conditions; 0.2.0 figures kept as labelled history. `make bench` live read 22 KB on the warm pass while three agents wrote; on an APFS clone of the transcripts (`VIBRA_HOME`) it read 0 bytes in 2 runs. Cold refresh 7.53 s is not compared with 0.3.0 |
| Release note says every new test failed on the base (DeepSeek 4) | It now says the refusal tests were red on the base (15 issues) and the padding and precedence tests are pinned by the guard-removal run. Task 1's "the new tests fail on the base" is read the same way: the refusal tests were red on the base; `anEmptyBucketAfterTodayIsPaddingAndIsDropped` and `aTooOldFileWithOnlyEmptyFutureDaysIsTooOld` were added with or after the fix and shown to fail with the guard removed |
| Non-blocking, folded in: `brew uninstall` also removes `bin/vibra`; "leaves only its saved data"; `brew upgrade` before the tap moves; findings limited to Claude Code (DeepSeek) | CHANGELOG, STATUS, release note |
| Non-blocking, declined: "Both checks are mutation-tested" ambiguity (DeepSeek) | The sentence follows the canary assertion and the did-not-run check, unchanged from before this release |

Publishing order follows from the release note: the tap PR merges before the GitHub release is published.
