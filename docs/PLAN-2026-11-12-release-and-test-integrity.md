# Plan: notarized release pipeline, and test-weakening evidence in Code checks

Version: v0.1. Status: draft for the plan gate. Date: 2026-11-12.

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
| coder-deepseek | OpenCode 2.0.20, `deepseek/deepseek-flash` (footer to be checked: DeepSeek V4.1 Flash) |
| reviewer-codex | Codex CLI 0.167.2 |
| Branch | `feat/release-and-test-integrity` from `origin/main` at `35fdc05` |
| Not stacked on | PR #13 (`docs/swift-6.1-floor`, README only, open). This run edits no README, so the two do not conflict |
| `$SCRATCH` | `/var/folders/x3/8mdzc51d11j_z0l1mt77lpmr0000gn/T//fleet-MVz3zM` |
| Review base | Written here at Step 5 |
| Data rule | Repo is public. Seats read the repo and `$SCRATCH` only, never `~/.claude`, `~/.codex`, `~/Library`, or any transcript. Probes over real transcripts are run by the planner only and print counts only |

## Research behind the pick

Three research passes, each with a URL per claim, are committed in
`docs/research/2026-11-12/`. The planner re-checked the claims this plan rests
on at the source; two corrections are marked.

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
   2026). **Correction 1:** ImpossibleBench released no labelled transcripts,
   only the task datasets and an LLM judge
   ([repo](https://github.com/safety-research/impossiblebench)), so it cannot be
   used as a free recall set. **Correction 2:** a later audit found current
   Claude 5.5 and GPT-6 models almost never cheat on it under other scaffolds
   ([LessWrong](https://www.lesswrong.com/posts/qnrjAhiqire7JeoN2/good-evals-are-hard-an-impossiblebench-audit)),
   so prevalence had to be measured locally.

### Local measurements (planner-only probes, counts only)

Scripts and outputs: `docs/research/2026-11-12/probe/`. Window 30 days,
run 2026-11-12. They reuse `tools/evidence-oracle` for check classification.

| Measure | Claude Code | Codex | Source |
|---|---|---|---|
| Sessions | 204 | 35 | `tamper-30d.txt` |
| Failed test run followed by a passing one | 107 | 2 | `tamper-30d.txt` |
| ... with a test-file edit in between | 11 | 0 | `tamper-30d.txt` |
| ... with only test-file edits in between | 8 (3 sessions) | 0 | `tamper-30d.txt` |
| Test-edit recoveries whose edit has fewer assertions, an added skip, or fewer test functions | 3 (1 only-test, 2 mixed) | n/a | `weaken-30d.txt` |
| Human answers in Review Agent Activity (`incidents.json`) | 0 | | `incidents.json` read for shape and count |

Reading: a pass that followed a weakened test is rare (3 of 107 recoveries,
2.8%, one machine, one month) but present. Whether those 3 were legitimate is
unknown; the owner can label them (task 13). The zero answers mean any
"evidence count from human answers" has no data yet, so it is out of scope.

## The pick

**Evidence (60%). Test-weakening evidence in Code checks.** Today Code checks
can say "Test command issued 2 m ago, after the last code change. It exited
with status 0." When that pass came right after a failed run and a test file
edit that removed assertions or added a skip, that sentence is true and
misleading: it is exactly the shortcut ImpossibleBench measures and the
heuristic developers rely on. The row gains one factual clause naming what the
edit did. It is evidence, not an accusation: no notification, no incident, no
verdict. Plus a small standards alignment: each Review Agent Activity kind
carries its OWASP Agentic Top 10 id in the JSON and the vendor-report draft.

**Distribution (40%).** A tag-triggered GitHub Actions release that builds a
universal, hardened-runtime, Developer ID signed, notarized, stapled DMG, with
a dry-run of every non-Apple step on every push so it is proven before the
secrets exist. The Apple account side is a runbook for the owner's external
agent. Then a launch kit for the owner to post once the first notarized build
is published.

### Considered and not picked

| Candidate | Why not now |
|---|---|
| Local OTLP-JSON export of agent and tool spans | The GenAI conventions are Development status with no release; we would chase a moving schema. Revisit at its first release |
| Agent Trace records | RFC v0.1.0; needs line ranges, which needs reconstructing file contents Vibra does not read |
| Per-rule evidence counts from human answers | 0 answers on the planner's machine |
| "Minutes your agents waited on you" | Strong next candidate (no prior study measured it, and it sells the README's claim). Kept for the next plan to keep this one small |
| Quota panel | The popular ones read the keychain or call vendors; conflicts with zero network |
| Auto-update | Cut in ROADMAP P3.2: an updater is network egress |

## Specification

### Evidence: test-weakening clause

Types (task 1, the foundation):

```swift
public enum TestEditEffect: String, Sendable, CaseIterable { case fewerAssertions, skipAdded, fewerTests }
public enum CodeChangeTarget: Sendable, Equatable {
    case source
    case test(seen: Set<TestEditEffect>?)   // nil: the edit's before/after text was not available
}
public enum EvidenceEvent: Sendable, Equatable {
    case codeChange(Date, CodeChangeTarget)
    case check(ObservedCheck)
}
```

**Test path.** A changed path is a test path when a directory component is one
of `test`, `tests`, `__tests__`, `spec`, `specs`, `Tests`, `testing`, or the
file name matches `test_*.py`, `*_test.{py,go,rs,rb}`, `*.test.{js,jsx,ts,tsx}`,
`*.spec.{js,jsx,ts,tsx}`, `*Test.{swift,java,kt}`, `*Tests.{swift,java,kt}`,
`conftest.py`. A path with a `fixtures`, `Fixtures`, `testdata` or
`__snapshots__` component is never a test path, even under `tests/` (editing a
fixture is not editing a test's assertions). The probe counted fixture
directories as test paths, so its figures may differ slightly from what the
spec yields. Paths already excluded from code changes (docs, temp dirs) stay
excluded.

**Effects, Claude Code only.** Computed when the edit opens, from the tool
input, and only the enum is kept:

- `Edit`: compare `old_string` with `new_string`. `MultiEdit`: the joined
  `old_string`s with the joined `new_string`s.
- `fewerAssertions`: fewer matches in new than old of the assertion pattern
  (`assert*`, `XCTAssert*`, `#expect`, `#require`, `expect(`, `assert_eq!`,
  `assert!`, `t.Error`/`t.Fatal`, `require.X(`, `.should`).
- `skipAdded`: more matches in new than old of the skip pattern
  (`pytest.mark.skip`/`xfail`, `.skip(`, `xit(`, `xdescribe(`, `.only(`,
  `XCTSkip`, `@Disabled`, `.disabled`, `t.Skip`, `#[ignore]`, `@unittest.skip`,
  `.todo(`, `withKnownIssue`).
- `fewerTests`: fewer matches in new than old of the test-function pattern
  (`def test_`, `func test…`, `@Test`, `it(`, `test(`, `#[test]`, `func Test…(`).
- `Write` and `NotebookEdit` to a test path: `.test(seen: nil)` (the old text
  is not in the transcript). Codex `FileChange` to a test path:
  `.test(seen: nil)`.

The exact patterns are the ones in `docs/research/2026-11-12/probe/weaken_probe.py`;
Swift and the oracle must implement this list, and the plan text wins if they
differ.

**When the clause shows.** Only when the row is `checkedAfterLastChange` and the
reported check is a **passed test**. Let F be the latest failed test check
issued before that pass. If any code change in the open interval (F.at,
pass.at) is `.test(seen: s)` with `s` non-empty, the row carries the union of
those effects. No failed test check before the pass: no clause. A same-instant
change counts as before the check, as today.

**Wording.**
`… It exited with status 0. Between a failed test run (12 m ago) and this pass, a test file was edited: fewer assertions, a skip added.`
Effects list in `TestEditEffect.allCases` order: "fewer assertions", "a skip
added", "fewer tests". The existing limit sentence stays last.

**Shape change.** `DeliveryEvidence.checkedAfterLastChange(ObservedCheck)`
becomes `checkedAfterLastChange(ObservedCheck, testEdits: Set<TestEditEffect>)`.
Every caller migrates; `caseName` is unchanged. `--evidence-stats` gains lines
`qualified agent=<a> effect=<e> n=<k>` (one per effect present in a reported
row) and `change agent=<a> target=<source|test.seen|test.unseen>` replaces
`change agent=<a>`.

**Privacy.** Edit text is read only to count pattern matches, in the extractor,
and dropped. `evidenceSentinelsNeverLeak` gains edits whose `old_string` and
`new_string` hold the sentinels, on a test path, and asserts no sentinel reaches
the row text, `--evidence-stats`, or any other output it already checks.
`docs/privacy.md` says so.

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
report draft ("OWASP Top 10 for Agentic Applications 2026: ASI03"). The window
is unchanged.

### Distribution

**Makefile** (defaults unchanged, so the tap formula's `make app SIGN_IDENTITY=`
builds exactly as today):

- `ARCHS ?=` empty builds the host arch as now. `ARCHS="arm64 x86_64"` builds
  each arch and `lipo`s one universal `VibraApp`.
- `HARDENED ?=` empty as now. `HARDENED=1` signs with
  `--options runtime --entitlements packaging/Vibra.entitlements`, and adds
  `--timestamp` when `SIGN_IDENTITY` is a real identity.
- `packaging/Vibra.entitlements` holds only
  `com.apple.security.automation.apple-events` (terminal jump-back uses
  `NSAppleScript`; `Info.plist` already has `NSAppleEventsUsageDescription`).
- `make dmg` builds `build/Vibra-$(VERSION).dmg` (UDZO, `Vibra.app` plus an
  `Applications` link) from the built bundle, and signs the DMG when
  `SIGN_IDENTITY` is a real identity.

**CI dry run** (`build.yml`, new job, every push): `make app ARCHS="arm64
x86_64" HARDENED=1 SIGN_IDENTITY=`, `make dmg`, assert `lipo -archs` lists both,
assert the signature has the runtime flag and the entitlement, mount the DMG
read-only and launch the app from it for 20 s as the existing launch check
does. Upload the DMG as a workflow artifact (7-day retention).

**Release** (`release.yml`):

- Triggers: `push` of tags `v*`, and `workflow_dispatch` with input
  `dry_run` (default true) that skips every step needing a secret.
- Job uses `environment: release` (owner sets required reviewer and a `v*`
  tag rule), `runs-on: macos-15`, `permissions: contents: write` on this job
  only, top-level `permissions: contents: read`.
- No third-party actions except `actions/checkout`, pinned by full commit SHA.
- Fails unless the tag equals `v$(VERSION)` from the Makefile.
- Imports `MACOS_CERT_P12_BASE64` into a temporary keychain made with
  `MACOS_KEYCHAIN_PASSWORD`, sets the partition list, and deletes the keychain
  and every decoded key file in an `if: always()` step.
- `make app ARCHS="arm64 x86_64" HARDENED=1 SIGN_IDENTITY="$MACOS_SIGN_IDENTITY"`,
  `codesign --verify --strict`, `make dmg`.
- `xcrun notarytool submit --wait` with the API key (`NOTARY_KEY_P8_BASE64`,
  `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`); on a non-Accepted status, prints
  `notarytool log` and fails.
- `xcrun stapler staple` then `xcrun stapler validate` on the DMG;
  `spctl -a -t open --context context:primary-signature -vv` on the DMG and
  `spctl -a -vv` on the mounted app must both say accepted, source Notarized
  Developer ID.
- Writes `Vibra-<ver>.dmg.sha256` and creates a **draft** GitHub release with
  both files via `gh`. The owner publishes it.
- Secret names match the runbook exactly: `MACOS_CERT_P12_BASE64`,
  `MACOS_CERT_PASSWORD`, `MACOS_KEYCHAIN_PASSWORD`, `MACOS_SIGN_IDENTITY`,
  `APPLE_TEAM_ID`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8_BASE64`.

**Runbook.** `docs/RUNBOOK-developer-id.md`: enrolment, the Developer ID
Application certificate, the App Store Connect API key, the `release`
environment and its secrets, with "the human takes over" at every login,
payment and key step, and a key-free hand-back checklist. Draft already given
to the owner; committed with this run.

**Launch kit.** `plan/LAUNCH-KIT.md`, for the owner to use after the first
notarized release is published: a Show HN draft on the audit angle ("which of
my agents read ~/.ssh, force-pushed, or passed its tests by deleting
assertions, with no hooks and no network"), the awesome-claude-code one-liner
(the list requires a human submitter), a 20-second demo shot list, and the
README and tap changes to make once the DMG exists. `plan/STATUS.md` brought up
to date. No README edit in this run: the README must not claim a DMG before one
is published, and PR #13 owns the README now.

## Tasks

| # | Owner | Task | Depends on | Acceptance |
|---|---|---|---|---|
| 1 | planner | Foundation: the three types above, every caller migrated, behaviour unchanged (`.source` for every change, empty `testEdits`) | — | `make test` passes with the same test count as baseline; `--evidence-stats` output unchanged on the planner's data apart from the renamed change line |
| 2 | deepseek | Claude and Codex extractors emit `CodeChangeTarget` per the spec; synthetic fixtures for each pattern and for a non-test path | 1 | New tests in `EvidenceExtractorTests` for every effect, each pattern family, `Write`/`NotebookEdit`/Codex as `seen: nil`, a fixture-directory path as `.source`; `make test` green |
| 3 | deepseek | `DeliveryEvidence.build` attaches `testEdits` per "When the clause shows"; wording; `--evidence-stats` lines | 1 | `DeliveryEvidenceTests`: clause on fail → weakening test edit → pass; none without a prior failure; none when the weakening edit is before F; none for a passed build; union of two effects; same-instant rule. `EvidenceStatsTests` updated |
| 4 | planner | Oracle mirrors tasks 2-3 in `tools/evidence-oracle`; selftest | 1 | `oracle_selftest.py` passes; on the planner's real 30-day data, `diff <(Vibra --evidence-stats --days 30) <(evidence_oracle.py --days 30)` is empty |
| 5 | planner | Check the OWASP ids against the OWASP PDF; amend the mapping table in this plan (a change here needs a confirmation round before task 6 starts) | — | The table cites the PDF page for each id |
| 6 | deepseek | `IncidentKind.owaspAgentic`, the JSON field, the vendor-report line | 5 | Tests pin the mapping for every kind and the JSON field; `incidentSentinelsNeverLeak` still passes |
| 7 | deepseek | Privacy canary extension for edit text | 2 | The extended `evidenceSentinelsNeverLeak` fails when the extractor is changed to put `new_string` in the row text (planner runs this mutation), passes otherwise |
| 8 | deepseek | Makefile `ARCHS`, `HARDENED`, `dmg`; `packaging/Vibra.entitlements` | — | On this Mac: `make app` unchanged (`codesign -d` shows ad-hoc, no runtime flag); `make app ARCHS="arm64 x86_64" HARDENED=1` gives `lipo -archs` = `x86_64 arm64`, `codesign -d --entitlements -` shows the entitlement, flags include `runtime`; `make dmg` mounts and holds `Vibra.app` |
| 9 | deepseek | `build.yml` dry-run job | 8 | Green on the branch's CI run, both steps visible in the log |
| 10 | deepseek | `release.yml` per spec | 8 | `actionlint` clean; a `workflow_dispatch` run with `dry_run: true` on the branch is green |
| 11 | planner | Live check of a hardened build on this Mac: install the ad-hoc hardened universal app, confirm the menu fills, Return to Session works in iTerm and Orca (Apple Events under hardened runtime), `--query` exits 0 | 8 | Recorded here with the date and what was seen |
| 12 | planner | Docs: CHANGELOG, `docs/features.md`, `docs/privacy.md`, ROADMAP P3.1 and P1.4 rows, `docs/RUNBOOK-developer-id.md`, `plan/LAUNCH-KIT.md`, `plan/STATUS.md` | 3, 6, 10 | `tools/readme-anchors.sh` exits 0; every claim in the new text matches a probe or test named here |
| 13 | owner (optional) | Label the 3 weakening recoveries from the probe as legitimate or not; the planner prints session ids and timestamps only | — | Result recorded here; it informs wording later, it does not gate this run |

After the code gate, with the owner's go-ahead and the secrets in place: push,
open the PR, merge, bump to 0.5.0, tag, run `release.yml`, and the owner
publishes the draft. A cask in `silex-ai-lab/homebrew-tap` pointing at the
notarized DMG is a separate change to that repo after the first published
release; the source formula stays.

## File ownership

- **planner:** `Sources/VibraCore/Evidence/DeliveryEvidence.swift`,
  `Sources/VibraCore/Evidence/EvidenceExtractor.swift`,
  `Sources/VibraCore/Evidence/EvidenceStats.swift` (task 1 only, then handed to
  deepseek); `tools/evidence-oracle/*`; this plan; `docs/research/2026-11-12/*`;
  `CHANGELOG.md`, `docs/features.md`, `docs/privacy.md`, `docs/ROADMAP.md`,
  `docs/RUNBOOK-developer-id.md`, `plan/LAUNCH-KIT.md`, `plan/STATUS.md`.
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
  `Makefile`, `packaging/Vibra.entitlements`, `.github/workflows/build.yml`,
  `.github/workflows/release.yml`.
- One shared working tree. DeepSeek tasks run one at a time in the order
  8, 9, 10, 2, 3, 7, 6; task 2 starts only after task 1 is committed.
  Nothing in `tools/evidence-oracle/` changes while a review round is open.

## Round-N objections → changes

(none yet)
