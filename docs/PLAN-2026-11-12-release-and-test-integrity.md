# Plan: notarized release pipeline, and test-weakening evidence in Code checks

Version: v0.4. Status: draft for the plan gate, round 4. Date: 2026-11-12.

## What the owner asked for

"Research the latest research and open-source work against my goal, pick the
most promising direction, draft a plan, execute after it passes." The owner set
the goal split at **distribution 40 : evidence layer 60**, and will have an
external agent do the Apple account steps for signing from a runbook the
planner supplies.

The planner's reading of the goal, stated to the owner and accepted with that
ratio: Vibra is the owner's own daily tool, and the open-source seed of Silex's
thesis that agents are trusted through local, verifiable evidence. Its growth
goal is installs and repeat use (`plan/OSS-GROWTH-PLAN.md`). Engineering has
advanced since 2026-10-01 while distribution has not: P3.1 Developer ID has been
"blocked on owner decision" since 2026-09-28, and the repo has 4 stars, 0 forks,
0 issues (`gh repo view`, 2026-11-12).

## Run record

| Item | Value |
|---|---|
| Fleet | orca-agent-fleet, standard roster, transport Orca (own handle resolved, runtime reachable) |
| Planner | Claude Code, `claude-opus-5-5`, calling pane |
| reviewer-claude | Claude Code started with `claude --model fable --permission-mode default --add-dir $SCRATCH` (Fable, a model other than the planner's); joined at round 3 |
| reviewer-codex | Codex CLI 0.167.2, TUI shows GPT-6-Sol medium Fast; weekly limit 22% left at start |
| coder-deepseek | OpenCode 2.0.20, `deepseek/deepseek-flash`, footer shows DeepSeek V4.1 Flash. Codes, never votes |
| Gates | Both reviewers' literal approvals plus the planner's written sign-off |
| Roster change | Rounds 1-2 ran under the earlier standard roster (DeepSeek and Codex voting). The owner's rule of 2026-11-12 (the skill now says two reviewer approvals pass a gate and DeepSeek only codes) was adopted before round 3: reviewer-claude added, DeepSeek's votes now advisory. Its round-1 objections stay answered below; its round-2 PLAN-APPROVED is recorded, not counted |
| Branch | `feat/release-and-test-integrity` from `origin/main` at `35fdc05` |
| Not stacked on | PR #13 (`docs/swift-6.1-floor`, README only, open). This run edits no README, so the two do not conflict |
| `$SCRATCH` | `/var/folders/x3/8mdzc51d11j_z0l1mt77lpmr0000gn/T//fleet-MVz3zM` |
| Baseline | `make test`: 513 tests (last local `build/test.log` at 0.4.2; task 1 re-measures before its change) |
| Review base | `BASE=5005054` (plan gate passed; Step 5 started 2026-11-12). Layout: one shared working tree, coder-deepseek (OpenCode, DeepSeek V4.1 Flash) in its own pane |
| Data rule | Repo is public. Seats read the repo and `$SCRATCH` only, never `~/.claude`, `~/.codex`, `~/Library`, or any transcript. Probes over real transcripts are run by the planner only and print counts only |

## Research behind the pick

Three research passes, each with a URL per claim, are committed in
`docs/research/2026-11-12/`. The planner re-checked the claims this plan rests
on at the source; corrections are in that directory's errata.

1. **Landscape** (`research-landscape.md`). The field is crowded: menu-bar
   session monitors (cc-status-bar 89 stars, Claudoscope 274), quota bars
   (CodexBar 23k), multiplexers (herdr, cmux, vibe-kanban). Every menu-bar rival
   covers Claude Code and at most Codex, and most install hooks; users report
   hook breakage (cc-status-bar #18, #19) and flaky state (cmux #1027, 45
   reactions). Vibra's gap is six agents, no hooks, zero network, plus an audit.
   Competitors ship notarized DMGs. Generic menu-bar Show HNs score 2-5 points;
   differentiated launches about 200.
2. **Distribution.** Homebrew 5.0.0 deprecated unsigned casks and disables
   official-repo casks that fail Gatekeeper from September 2026
   ([brew.sh](https://brew.sh/2025/11/12/homebrew-5.0.0/), re-checked: the
   cutoff names only Homebrew/homebrew-cask, so our own tap's source formula is
   unaffected). Apple notarizes a ZIP but cannot staple it; a DMG can be stapled.
   Core cask needs 225 stars for a self-submission.
3. **Standards** (`research-standards.md`). OpenTelemetry GenAI agent and tool
   spans are status Development in a repo with no release. Agent Trace is an RFC
   at v0.1.0 (re-checked at agent-trace.dev). OWASP Top 10 for Agentic
   Applications (9 Dec 2025) names tool misuse (ASI02) and identity and
   privilege abuse (ASI03), which are what Review Agent Activity flags.
4. **Literature** (`research-literature.md`). ImpossibleBench (ICLR 2026): of
   the cheating runs of Claude models and Qwen3-Coder, over 79% modified tests.
   Developers treat passing tests as proof of correctness (Dhanorkar et al.
   2026). ImpossibleBench released no labelled transcripts, and a later audit
   found current Claude 5.5 and GPT-6 models almost never cheat on it, so
   prevalence had to be measured locally.

### Local measurements (planner-only probes, counts only)

Scripts and outputs: `docs/research/2026-11-12/probe/`. Window 30 days,
run 2026-11-12. They reuse `tools/evidence-oracle` for check classification.
They are token-pattern counts, not confirmed test weakening, and they use a
looser rule than the spec below (union of effects, fixture directories counted
as test paths, no comment stripping, issue time not completion time).

| Measure | Claude Code | Codex | Source |
|---|---|---|---|
| Sessions | 204 | 35 | `tamper-30d.txt` |
| Failed test run whose next test run passed | 107 | 2 | `tamper-30d.txt` |
| ... with a test-file edit in between | 11 | 0 | `tamper-30d.txt` |
| ... with only test-file edits in between | 8 (3 sessions) | 0 | `tamper-30d.txt` |
| ... whose test edits matched fewer assertion, more skip, or fewer test-function tokens | 3 (1 only-test, 2 mixed) | n/a | `weaken-30d.txt` |
| Human answers in Review Agent Activity (`incidents.json`) | 0 | | `incidents.json` read for shape and count |

Reading: a pass right after edited-out assertion text is rare (3 of 107
recoveries, one machine, one month) but present. Whether those 3 were
legitimate is unknown (task 13). The zero answers mean any "evidence count from
human answers" has no data yet, so it is out of scope. The rule shipped is
measured on real data again in task 4 before any public claim uses it.

## The pick

**Evidence (60%). Test-weakening evidence in Code checks.** Today Code checks
can say "Test command issued 2 m ago, after the last code change. It exited
with status 0." When that pass came right after a failed run and an edit that
took assertion calls out of a test or added a skip, that sentence is true and
misleading: it is the shortcut ImpossibleBench measures and the heuristic
developers rely on. The row gains one clause that says what the edited text
shows, and that it compares only the edited text. It is evidence, not an
accusation: no notification, no incident, no verdict. Plus a small standards
alignment: each Review Agent Activity kind carries its OWASP Agentic Top 10 id
in the JSON and the vendor-report draft.

Why this over "minutes your agents waited on you", which would show every
session: that metric is new surface (a new figure, a new window section, a new
measurement method), while the clause corrects a sentence Vibra already shows
and can be wrong about today. Correcting an existing claim comes first; the
waiting metric is the next plan.

**Distribution (40%).** One packaging script, used by a CI dry run on every
push and by a tag-triggered release, that builds a universal, hardened-runtime
DMG and checks the app inside the mounted DMG. In release mode it signs with
Developer ID, notarizes, staples and creates a draft release. The Apple account
side is a runbook for the owner's external agent. A real tagged release is its
own gated task, and P3.1 stays open until it passes. Then a launch kit for the
owner to post.

### Considered and not picked

| Candidate | Why not now |
|---|---|
| Local OTLP-JSON export of agent and tool spans | The GenAI conventions are Development status with no release; we would chase a moving schema. Revisit at its first release |
| Agent Trace records | RFC v0.1.0; needs line ranges, which needs reconstructing file contents Vibra does not read |
| Per-rule evidence counts from human answers | 0 answers on the planner's machine |
| "Minutes your agents waited on you" | Next plan (see above) |
| Quota panel | The popular ones read the keychain or call vendors; conflicts with zero network |
| Auto-update | Cut in ROADMAP P3.2: an updater is network egress |

## Specification

### Evidence: test-weakening clause

Types (task 1, the foundation):

```swift
public enum TestEditEffect: String, Sendable, CaseIterable {
    case fewerAssertionMatches, moreSkipMatches, moreFocusMatches, moreExpectedFailureMatches, fewerTestFunctionMatches
}
/// Pattern-match counts in an edit's removed and inserted text. Numbers only.
public struct PatternCounts: Sendable, Equatable {
    public var assertion, skip, focus, expectedFailure, testFunction: Int
    public init(assertion: Int, skip: Int, focus: Int, expectedFailure: Int, testFunction: Int)
}
/// Opaque per-session key for one file: a hash of its path. Never printed.
public struct PathKey: Sendable, Hashable { /* hash value only */ }
public enum CodeChangeTarget: Sendable, Equatable {
    case source
    case test(path: PathKey, before: PatternCounts?, after: PatternCounts?)   // nil: text not available
}
public struct CodeChange: Sendable, Equatable {
    public let at: Date            // the edit call's open time, as today
    public let completedAt: Date?  // its successful result's record time
    public let target: CodeChangeTarget
}
public struct ObservedCheck: Sendable, Equatable {
    public let at: Date            // issued, as today
    public let completedAt: Date?  // result record's time; nil when not reported
    public let kind: CheckKind, result: CheckResult
}
public enum EvidenceEvent: Sendable, Equatable {
    case codeChange(CodeChange)
    case check(ObservedCheck)
}
```

Existing Code checks logic keeps using `CodeChange.at`, so today's rows do not
change.

`PathKey` is an opaque per-session key for "the same file" (a hash of the path,
computed in the extractor, never printed). It exists only so edits to one file
can be netted; no path reaches any output.

`completedAt` (on checks and changes) comes from the `tool_result` record's
timestamp (Claude Code) and the `item_completed` record's timestamp (Codex).

**Test path.** The edit's path is made absolute against the workspace root
with `IncidentExtractor.absolute(_:cwd:)`. The workspace root is the `cwd` in
effect at the edit: the `cwd` field of the Claude Code record that carries the
edit call, or for Codex the most recent `cwd` from `session_meta` or
`turn_context` before the edit. So a mid-session `cd` moves the root with it.
Directory components are read **only from the part of the path below that
root**; the root's own components and its ancestors never count, so a repo at
`/Users/test/app` or `~/code/testing/app` does not make every file a test path.
A path outside the root, or any path when no root is known, is decided by its
file name alone.

A changed path is a test path when a directory component below the root is one
of `test`, `tests`, `__tests__`, `spec`, `specs`, `Tests`, `testing`, or the
file name matches `test_*.py`, `*_test.{py,go,rs,rb}`, `*.test.{js,jsx,ts,tsx}`,
`*.spec.{js,jsx,ts,tsx}`, `*Test.{swift,java,kt}`, `*Tests.{swift,java,kt}`,
`conftest.py`. A path with a `fixtures`, `Fixtures`, `testdata`, `test_data` or
`__snapshots__` component below the root is never a test path. Paths already
excluded from code changes (docs, temp dirs) stay excluded.

**Counting, Claude Code only.** At the edit's open, from the tool input:
`Edit` counts `old_string` (before) and `new_string` (after); `MultiEdit` the
joined `old_string`s and the joined `new_string`s. An `Edit` with
`replace_all: true`, or a `MultiEdit` with any such entry, changes an unknown
number of occurrences, so it carries `before: nil, after: nil`, as do `Write`,
`NotebookEdit` and Codex `FileChange` to a test path.

Before counting, drop every line matching `^\s*(//|/\*|\*|#(\s|$))` (a comment
line; `#expect`, `#require`, `#[test]` and `#[ignore]` are kept because `#` is
followed by a non-space). So commenting an assertion out counts as removing it.

The patterns are normative, verbatim, case-sensitive, matched with
non-overlapping leftmost search (Python `re.findall`, Swift `NSRegularExpression`
`matches`):

| Count | Regex |
|---|---|
| assertion | `\bassert\w*\b\|\bXCTAssert\w*\|#expect\b\|#require\b\|\bexpect\(\|\.should\b\|\bt\.(?:Error\|Fatal)f?\(\|\brequire\.[A-Z]\w*\(` |
| skip | `pytest\.mark\.skip\w*\|\b(?:it\|test\|describe\|context\|suite\|pytest\|this)\.skip\(\|\.skipTest\(\|(?<![.\w])xit\(\|(?<![.\w])xdescribe\(\|\bXCTSkip\w*\|@Disabled\b\|\.disabled\(\|\bt\.Skip\w*\(\|#\[ignore\]\|@unittest\.skip\w*` |
| focus | `\b(?:it\|test\|describe\|context\|suite)\.only\(\|(?<![.\w])fit\(\|(?<![.\w])fdescribe\(` |
| expectedFailure | `pytest\.mark\.xfail\b\|\bwithKnownIssue\b\|\bXCTExpectFailure\b\|@unittest\.expectedFailure\b\|\b(?:it\|test)\.failing\(` |
| testFunction | `\bdef test_\w*\|\bfunc test\w*\|@Test\b\|(?<![.\w])it\(\|(?<![.\w])test\(\|#\[test\]\|\bfunc Test\w+\(` |

(`\|` above is a table escape for `|`.) The oracle implements the same table.
`(?<![.\w])` is a fixed-width lookbehind, supported by Python `re` and ICU.
Receiver-free calls are anchored this way and receiver calls name their
receivers, so ordinary code does not match: `re.test(x)`, `iter().skip(1)`,
`stream.skip(n)`, `button.disabled`, `require.resolve(`, Django's
`qs.only("id")` and `model.fit(x)` are pinned non-matches.
`.todo(` is deliberately in no family: turning `it(` into `it.todo(` already
lowers the test-function count, and adding a new todo weakens nothing.

**When the clause shows.** All of these must hold:

1. The row is `checkedAfterLastChange` and the reported check P is a **passed
   test** check.
2. The test check immediately before P (no other test check between them) is F,
   and F **failed**. Build and lint checks between them do not break adjacency.
3. F has a `completedAt`.
4. Let `Fc = F.completedAt` and treat a nil `change.completedAt` as "never
   finished" (+∞). A test-path change **touches the window** when
   `change.at < P.at` and `change.completedAt > Fc`. It is **inside** when
   `Fc < change.at` and `change.completedAt < P.at` (both strict): it started
   after F's result was recorded and finished before P was issued. Group the
   changes that touch the window by `PathKey`. A file is **dropped** (no claim
   about it) when any of its window-touching changes is not inside (it
   straddles `Fc` or `P.at`, or has no result), or has nil counts. This holds
   even when another change to that file is inside: an edit still running when
   P starts may have undone the earlier one. For each remaining file, net =
   sum(after) − sum(before) per count over its inside changes.
5. An effect is present when at least one remaining file has the effect's sign
   **and** the sum of nets across all remaining files has the same sign:
   assertion net < 0 (`fewerAssertionMatches`), skip net > 0
   (`moreSkipMatches`), focus net > 0 (`moreFocusMatches`), expectedFailure
   net > 0 (`moreExpectedFailureMatches`), testFunction net < 0
   (`fewerTestFunctionMatches`). No effect: no clause.

Netting per file makes "skip added, then removed before the pass" and "assertion
moved within the file" produce no clause; the cross-file sum makes "assertion
moved from one test file to another" produce none either. Only the first passing run after the
failure can carry the clause; a second run with no edit between hides it
(stated in `docs/features.md`).

The existing rule is unchanged: a check at the same instant as a change counts
as before it, so a change at exactly P.at makes the row `changedAfterLastCheck`
and no clause can show.

**Wording.** It names pattern matches, never calls, markers or functions,
because a string containing a pattern word matches like code.
`… It exited with status 0. Between a failed test run that finished 12 m ago and this run, edits to test files changed Vibra's text-pattern counts in the edited text: fewer assertion matches, more skip matches. Vibra matches text patterns in the edited text only; it does not parse code or read the whole file.`
Effect phrases, in `TestEditEffect.allCases` order, joined with ", ": "fewer
assertion matches", "more skip matches", "more focus (.only) matches", "more
expected-failure matches", "fewer test-function matches". The existing limit
sentence stays last.

**Shape change.** `DeliveryEvidence.checkedAfterLastChange(ObservedCheck)`
becomes `checkedAfterLastChange(ObservedCheck, testEdits: Set<TestEditEffect>)`.
Every caller migrates; `caseName` is unchanged. `--evidence-stats`: `change
agent=<a>` becomes `change agent=<a> target=<source|test.compared|test.unseen>`
(`test.compared` = counts present, `test.unseen` = nil), and a new counted group
`qualified agent=<a> effect=<e> n=<k>` (rows whose clause names that effect),
aggregated and sorted like the other groups.

**Known limits, written in `docs/features.md` and `docs/privacy.md`.** A
whole-file `Write`, a notebook edit, a shell edit and every Codex edit produce
no clause. Strings and identifiers containing the pattern words count like
code; the wording says "matches" for that reason. A re-run after the first pass
hides the clause. The window starts at the last failed run only, so a test edit
followed by another failure and then a pass shows nothing. F and P may be
different commands (a full run fails, a filtered run passes). A line
commented out as `#assert x` (no space after `#`) is not stripped, so that
removal is missed. A `replace_all` edit drops its file.

**Privacy.** Edit text is read only to count pattern matches, in the extractor,
and dropped; the path is reduced to an opaque key. `evidenceSentinelsNeverLeak`
gains edits on a test path whose `old_string`, `new_string` and path hold the
sentinels, and asserts no sentinel reaches the row text, `--evidence-stats`, or
any other output it already checks.

### Evidence: OWASP Agentic Top 10 ids

`IncidentKind` gains `owaspAgentic: [String]`, an exhaustive switch. Proposed
mapping, to be re-checked against the OWASP PDF in task 5 before any code:

| Kind | Ids | Reason |
|---|---|---|
| `credentialReadAttempt`, `workspaceSecretFileNamed` | ASI03 | Credential access the agent should not hold |
| `unrestrictedSession` | ASI03 | Session running with escalated privilege |
| `deniedCallRanLater`, `writeToPathOutsideWorkspace`, `forcePushAttempt` | ASI02 | Unsafe use of an available tool |
| `authFailure`, `unexplainedVendorUsage` | none | Not an agent behaviour |

Shown as an `owasp` array in `--incidents` JSON and one line in the vendor
report draft worded as a related category, not a finding against the vendor
("Related OWASP category (Top 10 for Agentic Applications 2026): ASI03"). The window
is unchanged.

### Distribution

**Makefile** (defaults unchanged, so the tap formula's `make app SIGN_IDENTITY=`
builds exactly as today):

- `ARCHS ?=` empty: host arch, `.build/release/VibraApp`, as now.
  `ARCHS="arm64 x86_64"`: the `build` target runs, per arch,
  `swift build -c release --product VibraApp --triple <arch>-apple-macosx14.0 --scratch-path .build/<arch>`,
  then `lipo -create` into `.build/universal/VibraApp`, and `BIN_SRC` points
  there. (`swift build --help` on Swift 6.4 lists `--triple` and
  `--scratch-path`, not `--arch`.)
- `HARDENED ?=` empty as now. `HARDENED=1` signs with
  `--options runtime --entitlements packaging/Vibra.entitlements`, and adds
  `--timestamp` when `SIGN_IDENTITY` is a real identity.
- `packaging/Vibra.entitlements` holds only
  `com.apple.security.automation.apple-events`. A reviewer questioned whether a
  non-sandboxed hardened app needs it; task 11 decides by test both ways
  (Return to Session with and without it) and drops it if it is not needed.
- `make dmg` is **packaging only**: no prerequisite, fails if
  `build/Vibra.app` is missing, never rebuilds. It writes
  `build/Vibra-$(VERSION).dmg` (UDZO, `Vibra.app` plus an `Applications` link),
  and signs the DMG when `SIGN_IDENTITY` is a real identity.

**`tools/release/package.sh --dry-run | --release`**, the one script both
workflows run:

1. `make app ARCHS="arm64 x86_64" HARDENED=1 SIGN_IDENTITY=<"" in dry run, $MACOS_SIGN_IDENTITY in release>`
2. `codesign --verify --strict` on the bundle; `make dmg`.
3. Mount the DMG read-only and check the **mounted** app: `lipo -archs`
   contains both `x86_64` and `arm64` (any order); `codesign -d --verbose` flags include `runtime`; the
   entitlements (if kept) are present; its CDHash equals the pre-DMG bundle's.
   Release only: `TeamIdentifier` equals `$APPLE_TEAM_ID`.
4. Release only: `xcrun notarytool submit --wait` with the API key; on a
   non-Accepted status print `notarytool log` and fail. Then `xcrun stapler
   staple` and `xcrun stapler validate` on the DMG; remount the stapled DMG and
   require `spctl -a -t open --context context:primary-signature -vv` on the DMG
   and `spctl -a -vv` on the mounted app to report accepted, source Notarized
   Developer ID.
5. Dry run: launch the mounted app for 20 s as the existing launch check does.
6. Write `Vibra-<ver>.dmg.sha256` from the final (stapled, in release) DMG.

**CI dry run** (`build.yml`, new job, same triggers as the existing jobs):
`tools/release/package.sh --dry-run` on both `macos-15` and `macos-15-intel`,
so the 20 s launch runs each slice natively; upload the arm64 runner's DMG as
an artifact (7-day retention). The macos-15 leg also exercises
`tools/release/keychain.sh setup` with a throwaway self-signed code-signing
identity generated in the job (openssl, then `.p12`), requires `security
find-identity -p codesigning` to list it, and runs `keychain.sh teardown`. The
build itself stays ad-hoc signed. This moves the likeliest first-tag failure
(keychain and search list) onto a branch run.

**Release** (`release.yml`):

- Trigger: `push` of tags `v*` only. One job, `environment: release` (owner
  sets a required reviewer and a `v*` tag rule), `runs-on: macos-15`,
  `permissions: contents: write` on this job only, top-level
  `permissions: contents: read`. No `workflow_dispatch`: the dry run lives in
  `build.yml`, so it runs on branches without the protected environment.
- No third-party actions except `actions/checkout`, pinned by full commit SHA,
  with `persist-credentials: false`. The `gh release create` step sets
  `GH_TOKEN: ${{ github.token }}` explicitly.
- Bounded: `timeout-minutes: 60` on the job; `notarytool submit --wait
  --timeout 30m`.
- Fails unless the tag equals `v$(VERSION)` from the Makefile,
  `docs/releases/v$(VERSION).md` exists, and the tagged commit is an ancestor
  of `origin/main` (fetched explicitly). The required reviewer stays the real
  gate.
- Secrets enter through `env:` on the steps that use them, never on the job;
  no `set -x` in those steps. The DMG is signed with `--timestamp` too.
- Keychain steps live in `tools/release/keychain.sh setup|teardown`, shared
  with the dry run. Keychain: create `$RUNNER_TEMP/release.keychain-db` with
  `MACOS_KEYCHAIN_PASSWORD`, `security set-keychain-settings -lut 21600`,
  `security unlock-keychain`, import the `.p12` decoded into `$RUNNER_TEMP`,
  `security set-key-partition-list -S apple-tool:,apple:,codesign:`, and
  `security list-keychains -d user -s "$KEYCHAIN" <the existing list>` so
  `codesign` finds the identity. Check `security find-identity -v -p
  codesigning` lists `$MACOS_SIGN_IDENTITY` before building.
- The `.p8` is decoded into `$RUNNER_TEMP`. An `if: always()` final step
  deletes the keychain, restores the search list, and removes every decoded
  file; a step before `gh release create` removes the decoded files too, so no
  key exists when assets upload.
- Runs `tools/release/package.sh --release`, then `gh release create v<ver>
  --draft --notes-file docs/releases/v<ver>.md` with the DMG and its `.sha256`.
  The owner publishes it.
- Secret names match the runbook exactly: `MACOS_CERT_P12_BASE64`,
  `MACOS_CERT_PASSWORD`, `MACOS_KEYCHAIN_PASSWORD`, `MACOS_SIGN_IDENTITY`,
  `APPLE_TEAM_ID`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8_BASE64`.

**Runbook.** `docs/RUNBOOK-developer-id.md`: enrolment, the Developer ID
Application certificate, the App Store Connect API key, the `release`
environment and its secrets, with "the human takes over" at every login,
payment and key step, and a key-free hand-back checklist. Given to the owner;
committed with this run.

**Launch kit.** `plan/LAUNCH-KIT.md`, for the owner after task 14 passes: a
Show HN draft on the audit angle ("which of my agents read ~/.ssh or
force-pushed, with no hooks and no network"), plus the test-edit line only if
task 4 finds the clause on real data; the awesome-claude-code one-liner (the
list requires a human submitter); a 20-second demo shot list; and the README
and tap changes to make once the DMG is published. `plan/STATUS.md` brought up
to date (it still says 1 star). No README edit in this run.

## Tasks

| # | Owner | Task | Depends on | Acceptance |
|---|---|---|---|---|
| 1 | planner | Foundation: the types above, every caller migrated, behaviour unchanged (`.source` for every change, `completedAt` filled where available, empty `testEdits`) | — | `make test` count equals the count measured just before the change; `--evidence-stats --days 30` on the planner's data identical apart from the renamed change line, with both binaries built first and the two runs taken back to back (recorded) |
| 4a | planner | Oracle half first: `tools/evidence-oracle` implements the spec (test path with root, regex table, rules 1-5) and its selftest with the task 3 cases; real-data `qualified` count | — | `oracle_selftest.py` passes; the 30-day `qualified … n=` lines are recorded here before task 2 starts. A 0 is recorded and drops the launch-kit test-edit line; tasks 2-3 still run, since the clause corrects a sentence whenever it fires |
| 2 | deepseek | Claude and Codex extractors: test path, `PathKey`, comment stripping, counts, `completedAt` for checks and changes; synthetic fixtures | 1 | `EvidenceExtractorTests`: each regex family, including `XCTExpectFailure` and `.failing(`; boundary non-matches `wait(`, `exit(`, `split(`, `.shoulder`, `latest(`, `asser`, `button.disabled`, `iter().skip(1)`, `stream.skip(n)`, `re.test(x)`, `require.resolve(`, `qs.only("id")`, `model.fit(x)`; matches `require.NoError(`, `@Test(.disabled("x"))`, `it.skip(`, `self.skipTest(`, `test.only(`, `fit(`, `test.failing(`; a commented-out assertion counted as removed; `#expect` kept; with root `/Users/test/app`: `/Users/test/app/src/main.py` source, `/Users/test/app/tests/test_x.py` test, `/Users/test/app/conftest.py` test, `/Users/test/app/tests/fixtures/a.py` and `/Users/test/app/test_data/x.py` not; a path outside the root with a `tests` ancestor and a non-test file name source; no root known → file name only; Claude root from the record's `cwd`, Codex from the latest `session_meta`/`turn_context` `cwd`, including a mid-session change; `Write`, `NotebookEdit`, `replace_all` `Edit`, Codex as nil counts; `completedAt` from the result record for both agents, for checks and for edits; `make test` green |
| 3 | deepseek | `DeliveryEvidence.build` per "When the clause shows"; wording; `--evidence-stats` lines | 2 | `DeliveryEvidenceTests`: clause on fail → assertion-removing edit → pass; no clause when a passed or unknown test check sits between F and P; no clause when the edit is before `F.completedAt` (made while F ran); no clause when F has no `completedAt`; no clause when the edit opens before P and its result lands after P is issued; no clause for an assertion-removing edit inside the window plus a restoring edit to the same file that opens before P and completes after P is issued (the file is dropped); same with the second edit opening before `F.completedAt` and completing after it; assertion moved from one test file to another → none; fail → source-only edit → pass → none; fail → source edit plus assertion-removing test edit → pass → clause; a `replace_all` edit on the only file → none; a string-only change (`"assert(x)"` text removed inside a string literal) produces the clause with the pinned "matches" wording; skip added then removed → none; assertion removed then restored → none; assertion moved within one file → none; nil-count edit on the only file → none; passed build → none; two effects in order; a build check between F and P keeps adjacency; change at exactly P.at → case `changedAfterLastCheck`. `EvidenceStatsTests` updated |
| 4 | planner | Oracle agreement with the Swift build; real-data run | 3, 4a | `oracle_selftest.py` passes; on the planner's 30-day data `diff <(Vibra --evidence-stats --days 30) <(evidence_oracle.py --days 30)` is empty; the `qualified … n=` lines are recorded here (the probe's 3 is an upper-bound guide only, the rule differs), and, if at least one row qualifies, one rendered clause from a real row is quoted here (content-free by construction); if the count is 0, that is recorded and the launch kit drops the test-edit line |
| 5 | planner | Check the OWASP ids against the OWASP PDF; amend the mapping table (a change here needs a confirmation round before task 6) | — | The table cites the PDF page for each id |
| 6 | deepseek | `IncidentKind.owaspAgentic`, the JSON field, the vendor-report line | 5 | Tests pin the mapping for every kind and the JSON field; `incidentSentinelsNeverLeak` still passes |
| 7 | deepseek | Privacy canary extension for edit text and test paths | 2 | The extended `evidenceSentinelsNeverLeak` passes, and fails when the planner mutates the extractor to put `new_string` in the row text (mutation run recorded) |
| 8 | deepseek | Makefile `ARCHS`, `HARDENED`, packaging-only `dmg`; `packaging/Vibra.entitlements`; `tools/release/package.sh`; `tools/release/keychain.sh` | — | On this Mac: plain `make app` unchanged (`codesign -d` shows ad-hoc, no runtime flag); `make dmg` without a bundle fails and builds nothing; `package.sh --dry-run` passes all its mounted-app checks if Command Line Tools here can build x86_64, otherwise the task 9 CI log is the proof and the local failure is recorded; `shellcheck tools/release/package.sh tools/release/keychain.sh` clean |
| 9 | deepseek | `build.yml` dry-run job | 8 | Green on the branch's CI run on both runners; the logs show the mounted-app checks and the 20 s launch on each, and on macos-15 the throwaway identity listed by `find-identity` and the teardown |
| 10 | deepseek | `release.yml` per spec | 8 | `actionlint` clean; the release path of `package.sh` reviewed line by line against the spec in the code gate. Its real proof is task 14 |
| 11 | planner | Live check of the hardened build on this Mac, with and without the entitlement: menu fills, Return to Session in iTerm and Orca, `--query` exits 0 | 8 | Recorded here with date, what was seen, the signing identity of each variant, and the Automation (TCC) grant state before each test (reset with `tccutil reset AppleEvents ai.silexlab.vibra` between variants); entitlement kept only if Return to Session fails without it |
| 12 | planner | Docs: CHANGELOG, `docs/features.md`, `docs/privacy.md`, ROADMAP (P3.1 "pipeline built, awaiting certificate"; P1.4 untouched), `docs/RUNBOOK-developer-id.md` (closing paragraph aligned: entitlement per task 11, cask outside this run; step 4 notes "Prevent self-review" stays off when the owner is the only reviewer), `docs/releases/v0.5.0.md` (draft notes), `plan/LAUNCH-KIT.md`, `plan/STATUS.md` | 3, 4, 6, 10 | `tools/readme-anchors.sh` exits 0; every claim in the new text names a probe, test or task here |
| 13 | owner (optional) | Label the 3 probe recoveries legitimate or not; the planner prints session ids and timestamps only | — | Result recorded here; informs wording later, gates nothing |
| 14 | planner, with the owner | Real release, after the code gate, the merge, the owner's go-ahead and the secrets: bump to 0.5.0 in a release PR (as with 0.4.2), merge it, tag `v0.5.0` on the merged `main` commit, `release.yml` runs | 12, secrets | The run log shows notarization Accepted, `stapler validate` ok, both `spctl` checks accepted as Notarized Developer ID, `lipo` both arches, and the `TeamIdentifier` check passed (the log masks the secret value as `***`; the step's pass is the evidence); the draft release carries the DMG, its `.sha256` (checked against a fresh download) and `docs/releases/v0.5.0.md` as body; a downloaded copy with `com.apple.quarantine` opens without the unidentified-developer block, Vibra's Setup reports notification authorization granted. Only then ROADMAP P3.1 becomes Done and the launch kit applies |

The cask in `silex-ai-lab/homebrew-tap` pointing at the notarized DMG is a
separate change to that repo after task 14; the source formula stays.

## File ownership

- **planner:** `Sources/VibraCore/Evidence/DeliveryEvidence.swift`,
  `Sources/VibraCore/Evidence/EvidenceExtractor.swift`,
  `Sources/VibraCore/Evidence/EvidenceStats.swift`,
  `Sources/VibraApp/SessionDetailWindowController.swift`,
  `Sources/VibraApp/MenuBarController.swift` (task 1 only, then the three
  Evidence files go to deepseek); `tools/evidence-oracle/*`; this plan;
  `docs/research/2026-11-12/*`; `CHANGELOG.md`, `docs/features.md`,
  `docs/privacy.md`, `docs/ROADMAP.md`, `docs/RUNBOOK-developer-id.md`,
  `docs/releases/v0.5.0.md`, `plan/LAUNCH-KIT.md`, `plan/STATUS.md`.
- **deepseek:** after task 1, the three Evidence files above;
  `Sources/VibraCore/Incidents/Incident.swift`,
  `Sources/VibraCore/Incidents/IncidentJSON.swift`,
  `Sources/VibraCore/Incidents/VendorReport.swift`;
  `Tests/VibraCoreTests/EvidenceExtractorTests.swift`,
  `Tests/VibraCoreTests/EvidenceFixtures.swift`,
  `Tests/VibraCoreTests/EvidencePrivacyTests.swift`,
  `Tests/VibraCoreTests/DeliveryEvidenceTests.swift`,
  `Tests/VibraCoreTests/EvidenceStatsTests.swift`,
  `Tests/VibraCoreTests/VendorReportTests.swift`,
  `Tests/VibraCoreTests/IncidentExtractorTests.swift`;
  `Makefile`, `packaging/Vibra.entitlements`, `tools/release/package.sh`,
  `tools/release/keychain.sh`, `.github/workflows/build.yml`,
`.github/workflows/release.yml`.
- One shared working tree. DeepSeek tasks run one at a time in the order
  8, 9, 10, 2, 3, 7, 6; task 2 starts only after task 1 is committed and
  task 4a's count is recorded.
  Nothing in `tools/evidence-oracle/` changes while a review round is open.

## Round-1 objections → changes

Round 1 on v0.1 (`6dc87e0`): codex PLAN-REJECTED (5), deepseek PLAN-REJECTED (9).

| Objection (who) | Change |
|---|---|
| F may not be adjacent to the pass; issue time is not result time (codex 1) | F is the test check immediately before P; `ObservedCheck.completedAt`; edits must follow `F.completedAt`; tests for both |
| Union of effects reports edits undone before the pass (deepseek 2) | Net per file across the interval; tests for skip added-then-removed, assertion removed-then-restored, assertion moved |
| Same-instant sentence contradicts the code (deepseek 3) | Rewritten to the shipped rule; a test asserts the case name |
| Glob rendering of the patterns is wrong; "plan wins" is incoherent (deepseek 4) | Normative regex table pasted verbatim; boundary tests listed |
| Labels overclaim: snippet counts, comments, xfail/.only are not skips (codex 2, deepseek 5) | Five effects (assertion calls, skip, focus, expected-failure, test functions); comment lines stripped; wording says "in the edited text" and "compares only the edited text"; Show HN line conditional on task 4 |
| Nothing proves the clause fires on real data (deepseek 6) | Task 4 records real `qualified` counts and quotes a real rendered clause; 0 drops the launch claim |
| Dry run cannot run on a branch through a protected environment and `workflow_dispatch` (codex 3, deepseek 1) | Dry run moved to `build.yml` via the shared `package.sh`; `release.yml` is tag-only |
| `make dmg` may rebuild the default bundle; checks only pre-DMG (codex 4) | `dmg` is packaging only; `package.sh` checks the mounted app, including CDHash equality |
| No real signed-run proof; P3.1 could be marked done early (codex 5, deepseek 7) | Task 14 with the full real-release acceptance; P3.1 Done only after it; release notes file required by the workflow |
| `codesign` will not see the temporary keychain (deepseek 8) | Search-list, unlock, partition-list and `find-identity` steps specified; decoded keys in `$RUNNER_TEMP`, removed before upload and in `always()` |
| Research file still claims ImpossibleBench transcripts (deepseek 9) | Corrected in `research-literature.md`, errata added (`docs/research/2026-11-12`) |
| Folded non-blocking | `--triple`/`--scratch-path` cross-build (codex); prevalence framed as token counts (codex); why the clause beats the waiting metric, Write/Codex limits stated, three stats labels, baseline count, entitlement decided by test, CI fallback for x86_64, runbook CSR step fixed, `APPLE_TEAM_ID` used for TeamIdentifier, `test_data` excluded, STATUS star count (deepseek). Runbook "G2 Sub-CA" kept with its "if the page offers it" guard |

## Round-2 objections → changes

Round 2 on v0.2 (`b68f071`): codex PLAN-REJECTED (2), deepseek PLAN-APPROVED (advisory after the roster change).

| Objection (who) | Change |
|---|---|
| An edit opened before P can finish after P starts; changes carry no completion time (codex 1) | `CodeChange` carries `completedAt`; rule 4 requires `change.completedAt < P.at`; nil drops the file; task 3 fixture for the straddling edit |
| "Fewer assertion calls / a skip marker" overclaims when only string text matched (codex 2) | Effects renamed to pattern matches (`fewerAssertionMatches` …); wording says "text-pattern counts", "matches", "does not parse code"; task 3 pins a string-only fixture with that wording |
| Folded non-blocking | Counted `qualified … n=` lines (deepseek 1); re-run hides the clause, documented (deepseek 2); `XCTExpectFailure` added, `.failing(` kept (Jest `test.failing`) (deepseek 3); `.todo(` omission made deliberate (deepseek 4); `lipo` contains-both (deepseek 5); task 12 depends on 4 (deepseek 6); `PathKey: Hashable`, `PatternCounts.init` (deepseek 7); `persist-credentials: false`, explicit `GH_TOKEN` (deepseek 8); "edits to test files" (deepseek 9); task 4 quote conditional (codex); task 11 records identity and TCC state (codex) |

## Round-3 objections → changes

Round 3 reviewed v0.3 at `604a42f`: reviewer-codex PLAN-REJECTED (1),
reviewer-claude PLAN-REJECTED (2).

| Objection (who) | Change |
|---|---|
| An edit straddling P.at is excluded, but an earlier qualifying edit to the same file still counts (codex 1) | Rule 4 rewritten: every change that touches the window must be inside it, or its file is dropped; task 3 fixture with an inside removal plus a restoration straddling P.at, and one straddling `F.completedAt` |
| Directory components are read from the absolute path, so a workspace under `/Users/test/...` makes every file a test path (claude 1) | Components are read only below the workspace root (`cwd` at the edit; Codex from the latest `session_meta`/`turn_context`); outside the root or with no root, file name only; task 2 path cases with root `/Users/test/app` |
| Four patterns match ordinary code: `.disabled`, `.skip(`, `test(`/`it(`, `require.X(` (claude 2) | Receivers named for `.skip(`, `.only(`, `.failing(`; `(?<![.\w])` for receiver-free calls (also `xit(`, `xdescribe(`, `fit(`, `fdescribe(`); `.disabled(`; `require.[A-Z]`; `.skipTest(` added. Pinned non-matches add `qs.only(...)` and `model.fit(...)`. Checked with Python `re` and Swift `NSRegularExpression` on the table text: 16 non-matches, 28 matches, no disagreement (`$SCRATCH/regex-check.py`, `regex-check.swift`) |
| Folded non-blocking (claude) | Oracle half first as task 4a, its real `qualified` count recorded before task 2; `replace_all` → nil counts; cross-file net sign required (assertion moved between files → none); streak start, F/P different commands and `#assert` listed as known limits; task 3 source-only and source-plus-test fixtures; task 1 back-to-back runs; release.yml `timeout-minutes` and notary `--timeout`, tag commit must be on `origin/main`, secrets only in step `env:`, no `set -x`, DMG `--timestamp`; dry run on both runners and a throwaway keychain identity via shared `keychain.sh`; masked `TeamIdentifier` wording; runbook closing paragraph and "Prevent self-review" note; OWASP line worded as a related category; 0.5.0 bump in a release PR |
| Not taken | Gating the dry-run job to `push` only: it follows the existing jobs' triggers; the duplicate PR run costs minutes, not correctness |

## Plan gate record

Round 4 reviewed v0.4 at `dc3168c` (`$SCRATCH/interdiff-plan-r4.txt`).

| Seat | Model (self-reported) | Verdict | Reply |
|---|---|---|---|
| reviewer-codex | GPT-6-Sol | PLAN-APPROVED | `$SCRATCH/codex-plan-r4.md` |
| reviewer-claude | claude-fable-5-2 | PLAN-APPROVED | `$SCRATCH/claude-plan-r4.md` |

Non-blocking suggestions from round 4, carried into implementation as task
notes and checked at the code gate (no change to the approved rules):

- Spec "Test path": the helper is `IncidentPaths.absolute(_:cwd:)` (in
  `IncidentExtractor.swift`), not `IncidentExtractor.absolute` (both).
- Task 8: resolve each slice's binary with `swift build --show-bin-path` using
  the same `--triple` and `--scratch-path` (codex).
- Task 12 Known limits gain: an agent that has `cd`-ed into `tests/` or `src/`
  turns some test files into source (a miss, never a false claim); assertions
  moved into a file written whole with `Write` still show "fewer assertion
  matches"; `\.disabled\(` also matches the SwiftUI modifier; an edit still in
  flight on a live transcript is absent, not nil, until its result arrives, so
  the clause can show until the next refresh (accepted) (claude 2-5). Task 3
  adds the `Write` fixture pinning that behaviour.
- Task 8: `keychain.sh setup` takes the `find-identity` validity flag as an
  argument (release `-v`, dry run without); the throwaway certificate carries
  the codeSigning EKU; OpenSSL 3 `.p12` export uses `-legacy` if `security
  import` needs it (claude 6).
- Task 10: checkout with `fetch-depth: 0` for the ancestor check, which
  compares `$GITHUB_SHA` (claude 7). Task 12 runbook troubleshooting: import
  `DeveloperIDG2CA.cer` if signing reports "unable to build chain" (claude 8,
  marked by the reviewer as unverified).

PLANNER (claude): PLAN-APPROVED, plan v0.4 at `dc3168c`. Both reviewers'
literal approvals were read in their reply files. The appended notes above
change no rule, test or acceptance in the approved plan.

## Execution record

Spec fix during task 3 (planner decision, 2026-11-13, for the code gate). The
approved Wording names the failed run's finish time ("a failed test run that
finished 12 m ago"), but the approved Shape change
`checkedAfterLastChange(ObservedCheck, testEdits: Set<TestEditEffect>)` cannot
carry it to `line(now:)`. DeepSeek raised this before writing code. The wording
is kept; the payload becomes `testEdits: TestEdits?`, where `TestEdits` holds
`failedRunFinishedAt` (F.completedAt) and a never-empty `effects` set, and nil
means no clause. The case keeps two payloads and its `caseName`, so pattern
matches elsewhere are unchanged. Rules 1-5 and every acceptance item are
unchanged.

| Task | Result | Evidence |
|---|---|---|
| 1 | Done, `0b9398e`. `make test`: 514 tests (513 at `BASE`, measured just before the change, plus one completion-time test). Existing extractor tests compare on issue time through test-only views in `EvidenceFixtures.swift`; completion times have their own test | `--evidence-stats --days 30`, both binaries built first, run back to back twice in opposite orders (05:07-05:19 UTC). Apart from the renamed `change ... target=source` lines, the only differences are check counts that grow with run time whichever binary ran later (live sessions were writing), so they are drift, not the change |
| 4a | Done, `b7fb3b2`. `oracle_selftest.py` passes: 14 path cases, 13 pinned non-matches, 10 matches, 21 clause cases, the same-instant case. Four mutations of the rule (straddle drop removed, v0.3 inside-only window, root ignored, cross-file sign removed) each fail it | Real 30-day run (05:21 UTC): **no `qualified` line, so 0 rows qualify**. Change targets: Claude Code source 804, test.compared 147, test.unseen 144; Codex source 5, test.unseen 2. Funnel (`docs/research/2026-11-12/probe/funnel_4a.py`, counts only): of 25 Claude Code rows reported as checked after the last change, 9 report a passed test, 1 has a failed test immediately before it, and that one has no change in the window. The probe's 107 counted every fail-then-pass pair in a session; the clause reads only the session's current row. Per the plan, the launch kit drops the test-edit line, and tasks 2-3 still run |
| 5 | Done, mapping unchanged, so no confirmation round. Source: "OWASP Top 10 for Agentic Applications, Version 2026, December 2025", 57 pages, from https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/ (download 52117, sha256 `a2db94cd…886fcb5c`, PDF created 2025-12-09). ASI02 "Tool Misuse and Exploitation", printed page 12: "the agent operates within its authorized privileges but applies a legitimate tool in an unsafe or unintended way - for example deleting valuable data" (forcePushAttempt, writeToPathOutsideWorkspace, deniedCallRanLater). ASI03 "Identity and Privilege Abuse", printed page 15: "identity ... includes ... any authentication material (API keys, OAuth tokens, delegated user sessions)" (credentialReadAttempt, workspaceSecretFileNamed) and "agents with default privileges, such as unrestricted Internet access, also inherit more authority than intended" (unrestrictedSession). The ASI03 text also covers "bypass controls", which a denied call that later ran can resemble; it stays ASI02 because Vibra cannot tell a bypass from an approved retry, and the report line says "Related OWASP category" | `pdftotext` of the downloaded PDF; table of contents lines 46-152 |
| 8 | Done, `4a22394` (DeepSeek, reviewed by the planner line by line) | On this Mac: plain `make app` signs ad-hoc, no runtime flag; `make dmg` with no bundle exits 2 and builds nothing; `package.sh --dry-run` rc=0 in 1m24s (`lipo -archs: x86_64 arm64`, hardened runtime yes, CDHash matches, automation entitlement present, still running after 20 s); `shellcheck` on both scripts clean |
| 9 | Done, `b5c574d` (DeepSeek; my commit `160fe3c` had swept its file in mid-edit, so it was split before the first push) | CI run 43382966703 on `feat/release-and-test-integrity`, all four jobs green (4m18s). On both `macos-15` and `macos-15-intel`: `lipo -archs: x86_64 arm64`, `hardened runtime: yes`, `CDHash matches the built bundle`, `automation entitlement: present`, `still running after 20 s`. On `macos-15`: `keychain ready: .../release.keychain-db lists "Vibra CI Throwaway"` and `keychain removed`. Artifact `Vibra-dmg`, 2756801 bytes, expires 2026-11-20. No generated password appears in the log (grep for 32-hex values after `PASSWORD=` or `pass:` finds 0) |
| 10 | Done, `5391ae6` (DeepSeek, reviewed by the planner against the spec) | `actionlint` clean (run by the planner too). Secrets appear only under step `env:`, each step carries only the ones it uses, no `${{ }}` inside a `run:` body; checkout pinned with `fetch-depth: 0`; ancestor check on `$GITHUB_SHA` after `git fetch origin main`. VERSION is parsed from the Makefile's `VERSION :=` line, as `package.sh` does. Real proof is task 14 |
| 4 | Done at `cc32bdc` (planner worktree, so DeepSeek's builds were untouched). `oracle_selftest.py` passes. Real 30-day run, both outputs sorted, 37 lines each: **no `qualified` line on either side, so 0 rows qualify**, as in 4a; the launch kit drops the test-edit line | Run 1 Swift then oracle (07:41-07:44 UTC): differs only in `sessions agent=claudeCode` 228 vs 229 and `case ... noCodeChangeSeen` 78 vs 79. Run 2 oracle then Swift (07:44-07:48 UTC): differs only in Codex `sessions` 54 vs 56 and two Codex `case` lines. In both orders the later run has the extra sessions (new sessions started between runs), so it is drift. Every `change`, `check`, `reported` and target line agrees: Claude Code source 804, test.compared 147, test.unseen 144; Codex source 5, test.unseen 2 |
| 7 | Done, `2fc8354` (DeepSeek). The canary feeds Claude Code Edit, MultiEdit and Write and a Codex FileChange on test paths whose path, `old_string` and `new_string` carry sentinels, and asserts the clause fires first | Mutation run (`mutate-canary.sh`, planner worktree at `99f758e` plus the new test): baseline green; M1, `PathKey` keeps the raw path: red, 6 issues, `SENTINEL_TESTPATH_7d1`; M2, the Claude extractor keys an edit by its `new_string` on top of M1: red, 9 issues, `SENTINEL_NEW_6c2` and `SENTINEL_TESTPATH_7d1`; restored: green. 559 tests |
| 6 | Done, `af95fc0` (DeepSeek). Exhaustive `IncidentKind.owaspAgentic` per the task 5 table; `owasp` array on every `--incidents` row; vendor draft line after the facts. `IncidentPrivacyTests.swift` also changed, outside the listed files, because it pins the exact JSON key set (reported by DeepSeek, accepted) | 563 tests; `incidentSentinelsNeverLeak` passes; mapping pinned against `IncidentKind.allCases` |
| 12 | Done, `23c0ce6` (planner, drafted by a planner fork and reviewed). Known limits include every spec item plus the round-4 four; launch kit has no test-edit line (0 rows qualified, task 4); runbook keeps its human-takes-over rules; the entitlement line waits on task 11 | `tools/readme-anchors.sh` exit 0; no long dashes in added lines |
