# Plan: first-use loop (Milestone A of the external improvement plan)

Date: 2026-11-08. Status: plan v0.4, implemented, code gate passed on diff revision 905be7c.

Source under review: an external model's plan (`Silex_Vibra_Improvement_Plan.md`, copied to
`$SCRATCH/gpt-plan.md`), written from static reading of `b14ecf0`.

## Run record

| Item | Value |
|---|---|
| Roster | standard, Claude planner, transport Orca |
| Planner | Claude Code, `claude-opus-5-5` |
| coder-deepseek | OpenCode 2.0.20, `deepseek/deepseek-flash` (footer: DeepSeek V4.1 Flash) |
| reviewer-codex | Codex CLI 0.166.0, model shown in TUI: GPT-6-Sol medium Fast |
| Branch | `feat/first-use-loop` from `origin/main` at `b14ecf0` |
| `$SCRATCH` | `/var/folders/x3/8mdzc51d11j_z0l1mt77lpmr0000gn/T//fleet-kPMveW` |
| Baseline | `make test`: 254 tests, 35 suites, both canaries pass (measured 2026-11-08) |
| Audits | `$SCRATCH/codex-audit-r1.md`, `$SCRATCH/deepseek-audit-r1.md` |

## Verdict on the external plan

Accepted as direction. Both audits found no false code claim in sections 2, 3 or 6. Its priority
order (reliability of what exists before new surfaces) is right. Five corrections:

1. **Discovery is worse than it says.** Its fix for 3.1 covers the frozen adapter set. It misses that
   an FSEvents stream created on a missing root never delivers. Measured with
   `$SCRATCH/probe/fsevents-missing-root.swift` and a control: root absent at stream creation, then
   created and written twice, 0 events (3 runs); root present, 4 events. So a first-run user whose
   `~/.claude/projects` appears after launch would get every update through the 60 s safety timer
   for the whole process lifetime, not only the first.
2. **Exact return is per target, not per agent.** Cursor and VS Code focus a window, not a chat
   (`TerminalJumper.swift:57-68`), while `canJump` says true. A boolean cannot carry this.
3. **Logic placement.** It puts sort and capability logic in `MenuBarController`. That target cannot be
   tested (`Package.swift:47-48`). All decisions move to pure functions in `VibraCore`.
4. **`reasonCode: String?` is the wrong shape.** An enum makes "no raw error text" structural.
5. **F01 is a functional prerequisite, not packaging.** An ad-hoc bundle is refused notification
   authorization (`docs/troubleshooting.md:87-114`). The first-run window must say so honestly.

## Scope of this run

In scope: A1 to A5 of its Milestone A, which is its stated minimum (F02 to F05).

Out of scope, with reasons:

- **A6 / F01 signed notarized build.** `security find-identity -v -p codesigning` reports 0 valid
  identities on this machine (measured), and `docs/ROADMAP.md:411-423` records Developer ID as an
  owner decision. Writing untestable signing automation proves nothing. The user gets the exact list
  of prerequisites in the final report.
- **Demo data in onboarding.** Cut. Fake sessions in a status display need an isolation mechanism
  across store, notifier and window, for a user who can read one sentence saying "start an agent and
  it appears here".
- **Milestone B and C (F06 to F12).** A separate run after this one ships. F12 also contradicts the
  no-egress decision (`docs/privacy.md:9-11`, `docs/ROADMAP.md:241-248`) and needs a product decision.

## Data shape

New in `VibraCore`, names below are the contract. Task 0 creates every type below with stub bodies, so
nothing is defined twice.

```swift
public struct SessionKey: Hashable, Sendable { public let agent: AgentKind; public let id: String }
// Session gains: public var key: SessionKey { SessionKey(agent: agent, id: id) }

public enum SourceProblem: String, Sendable, CaseIterable { case listFailed, readFailed, parseFailed }

public enum SourceHealth: Sendable, Equatable {
    case absent                                        // isAvailable false
    case ready(lastSuccess: Date?)
    case failing(SourceProblem, lastSuccess: Date?)
}

public enum AttentionStart: Sendable, Equatable {
    case observed(Date)    // Vibra saw the state change
    case firstSeen(Date)   // already in this state when first seen; true start unknown
    public var date: Date { get }
}

public struct AttentionClock: Sendable {
    public init()
    public mutating func advance(to sessions: [Session], now: Date) -> [SessionKey: AttentionStart]
}

public struct StatusSnapshot: Sendable, Equatable {
    public var sessions: [Session]
    public var health: [AgentKind: SourceHealth]
    public var attention: [SessionKey: AttentionStart]
}

public enum ReturnRoute: Sendable, Equatable {
    case attempt        // Vibra will try to reach this session; only the attempt shows how exact it was
    case focusApp       // Vibra can only bring the app window forward
    case none
    public static func of(_ session: Session) -> ReturnRoute
}
```

`ReturnRoute.of`: Claude Code and Codex are `.attempt`, Cursor and VS Code are `.focusApp`, OpenCode and
Hermes are `.none`. No `Session` field proves an exact return for Claude Code or Codex: an IDE-hosted
Claude Code session only brings the editor forward (`docs/agents/claude-code.md:3`,
`TerminalJumper.swift:94-98`). So no tooltip, label or detail line says "exact". The verb is an attempt,
each click re-runs `TerminalJumper.jump`, and failures reuse `explainFailure`.

`AttentionClock` keeps the state of **every** session present in the last pass, plus a start for attention
states. First call: attention sessions are `.firstSeen(now)`. Later: key absent from the previous pass is
`.firstSeen(now)`; recorded state unchanged keeps its start; recorded state different and the new state is
attention is `.observed(now)`. Keys absent from the current pass are pruned, so a session that vanishes and
returns is `.firstSeen`.

`SessionIngest` gains `public private(set) var health: [AgentKind: SourceHealth]`, set on every `refresh()`
from a sticky `[URL: SourceProblem]` plus per-adapter listing failures.

- A failure stays until that source is successfully re-read or stops being listed. A failed read writes no
  new entry, so the next pass sees a changed descriptor and retries. An unchanged source that never failed
  stays clean.
- Lifecycle of the problem map: whenever `sources()` succeeds, the map for that adapter is intersected with
  the URLs it returned, so a deleted or rotated source clears its failure on the next pass. When `sources()`
  throws, the whole map and every entry of that adapter are kept and the adapter records `.listFailed`, which
  is recomputed every pass and clears on the next successful listing.
- `lastSuccess` is stamped for a source when it is actually re-read and `update` returns successfully, for
  JSONL and SQLite alike. An unchanged source is skipped, so an idle pass stamps nothing, the snapshot stays
  equal and `SessionStore`'s equality gate still holds.
- A source that fails while a previous entry exists keeps contributing `previous.state.sessions`. A
  `sources()` throw keeps every entry of that adapter. Entries gain `agent` to allow this.
- What a failure does and does not do to a session. Ingest output for a retained source is byte-identical
  across the failing passes, so a read failure by itself cannot change a session's state, remove it, or start
  or reset its `AttentionClock` entry. `LivePipeline` still applies time decay, the activity window and
  process liveness to it, exactly as for a healthy source. An alert withdrawn because a `turnComplete` decayed
  during a failure is correct, because it would have happened anyway. A genuinely new event on recovery is a
  normal transition. There is no per-row stale flag; the agent's notice and the detail `healthLine` carry it.
- A file unreadable but unchanged is not detected until something forces a read. That is stated in
  `docs/troubleshooting.md`, not hidden.

Errors reach ingest by throwing. `JSONLTreeScanner.files(under:)` becomes `throws` when the root exists and
cannot be listed. Unreadable subdirectories stay partial results (documented limit). `ClaudeCodeAdapter`
and `CodexAdapter` propagate it. `VSCodeAdapter` throws when a user directory exists but cannot be listed.
A schema mismatch in `OpenCodeAdapter`, `CursorAdapter` and `HermesAdapter` throws a `SourceSchemaError`
from `discoverSessions` and `update`, mapped to `.parseFailed`. `discoverSessionsSafely` still yields `[]`,
and `schemaMismatchYieldsNothing` tests move to that entry point.

```swift
public enum MenuSectionKind: Sendable { case needsYou, running, recent }
public enum RowClick: Sendable, Equatable { case returnToSession, openDetails }
public struct MenuRow: Sendable, Equatable {
    public let key: SessionKey
    public let title: String
    public let tooltip: String
    public let click: RowClick
}
public struct MenuSection: Sendable, Equatable { public let kind: MenuSectionKind; public let rows: [MenuRow] }
public struct SessionMenuModel: Sendable, Equatable {
    public let sections: [MenuSection]      // empty sections omitted, in enum order
    public let detailRows: [MenuRow]        // every session, for the Session Details submenu
    public let emptyMessage: String?        // non-nil only when there are no sessions and nothing is failing
    public let notices: [String]            // one per failing agent, also shown when sessions exist
    public static func build(_ snapshot: StatusSnapshot, now: Date) -> SessionMenuModel
    // Content-free lines for --dump-menu and VIBRA_DEBUG_MENU_DUMP: section, agent, id, state, wait kind
    // and seconds, click, and failing agent plus SourceProblem. Never a title, cwd, branch or tooltip.
    public func diagnosticLines(_ snapshot: StatusSnapshot, now: Date) -> [String]
}

public struct SessionDetailModel: Sendable, Equatable {
    public let heading: String
    public let agentName: String
    public let branch: String               // "Not reported" when nil
    public let stateLine: String
    public let evidenceLine: String
    public let lastObservedLine: String
    public let healthLine: String
    public let tokensLine: String           // "None reported" when total is 0
    public let cwd: String
    public let returnRoute: ReturnRoute
    public let isLive: Bool                 // key still present in the snapshot
    public let historyAvailable: Bool
    public static func build(session: Session, snapshot: StatusSnapshot, now: Date) -> SessionDetailModel
}
```

Menu behaviour fixed by `build`:

- `needsYou`: `blocked` before `awaitingInput`, then longest waiting first (`AttentionStart.date`
  ascending), then `lastActivity` descending, then `SessionKey`, so the order is deterministic. `running`: `working` and `stalled`. `recent`: `idle`.
  Every section sorted across all agents; agent is a label on the row, not a group.
- Row title: `<label> · <Agent> · <state text>`. Label is `displayName`. When rows share a label, append
  the branch; if still equal, the last two path components; if still equal, the shortest id prefix of at
  least 4 characters that is unique among the colliding rows, falling back to the full id.
- State text: `needs approval · 4m` / `your turn · 4m` for `.observed`, `first seen 4m ago` for
  `.firstSeen`. `stalled` reads `no activity for 8m`. No token count in the row. The tooltip carries tokens
  or `Tokens: none reported`. A reported zero is indistinguishable from unreported today, so the wording
  claims neither; F08 owns the real coverage model.
- `emptyMessage`: when no source is failing and at least one is available, `No active sessions` (string kept,
  four READMEs quote it). When none is available, `No sessions yet` with the supported-agent list and what
  to run. `.absent` means no state on disk, so the text never says an agent is not installed. When a source
  is failing and there are no sessions, nil plus the notices.
- `click`: `.returnToSession` unless `ReturnRoute` is `.none`.
- `notices`: one per failing agent, `Couldn't read <Agent> data (last read 3m ago)`, or `(never read)` when
  `lastSuccess` is nil. Built only from the enum and date.

`History` coverage moves from `HistoryWindowController.covered` to a public `HistoryCoverage.agents`
in `VibraCore` so the detail model and the window share one source.

## AppKit decisions

- One `NSMenu` with a delegate. `menuNeedsUpdate` rebuilds items from the latest snapshot with the
  current time, so a wait label is right when the menu opens and refreshes stop rebuilding menus nobody
  is looking at.
- A row is one `NSMenuItem`. `.openDetails` rows open details directly. Below the sections a
  `Session Details` submenu is rebuilt from `detailRows` in `menuNeedsUpdate`, and its items always open the
  detail window whatever `click` says. This replaces the planned `isAlternate` items: one
  mechanism, visible without knowing a modifier, and it does not depend on OS rendering of alternates.
  `recent` renders as a submenu `Recent · N`.
- `SessionDetailWindowController` shows `SessionDetailModel` and buttons: Return to Session (absent for
  `.none`, titled `Open <App>` for `.focusApp`, disabled when `isLive` is false), View History (only when
  `historyAvailable`), Open Project Folder, Copy Path. It refreshes on snapshot change. A session that left
  the snapshot keeps its last model with `No longer active`.
- A notification click on a `.none` route opens details instead of dismissing silently. Clicks remain keyed
  by bare session id as today; cross-agent id collision is a known residual, not widened here.
- `SetupWindowController`: per-agent status from `AgentDetector.detectAll`, worded `seen recently` or `no
  sessions yet`, never `not installed`, because `.absent` only means no state on disk. Notification status read
  asynchronously, Enable and Send Test buttons, Open Notification Settings, Launch at Login
  (`SMAppService.mainApp`, result and failure shown as text, labelled best-effort on an ad-hoc build), Start
  Using Vibra. Shown once when `onboardingCompleted` is absent; closing the window counts as completing it, so it never
  reappears uninvited. Reopened by a `Setup…` menu item. The startup
  authorization request runs only after onboarding completes. Existing installs see it once.
- `SessionStore` owns the `AttentionClock` and advances it on each refresh that changes sessions; the menu
  model only reads the result.
- `SessionStore.onChange` carries `(previous: [Session], snapshot: StatusSnapshot)`. `NotchOverlay` and
  `AttentionNotifier` keep taking `[Session]`, so neither signature changes.

## Discovery changes

- `AppDelegate`, the two lazy windows and `--query` pass `AdapterRegistry.all()`. `detected()` and
  `AgentDetector.activeAdapters()` are deleted. `SessionIngest.refresh` already checks `isAvailable`.
  `docs/ROADMAP.md:349-353` and the test that encoded the old decision change in the same task set.
- `FileWatcher.pollOnce`: first poll seeds; afterwards absent to present and present to absent fire
  `onChange`. Stored signature becomes optional.
- `FileWatcher` root re-arm. It holds `armedRoots: [String: RootIdentity]`, where `RootIdentity` is
  `(device, inode)` from `stat`, for what the running stream actually covers. The existing 1 Hz timer stats
  each watched root and computes `desired` the same way. Comparing identity, not only paths, catches a
  directory deleted and recreated between two ticks. When `desired != armedRoots`: create and start a new
  stream for `desired`; only if that succeeds, stop the old stream, set `armedRoots = desired`, then fire
  `onChange` with the changed roots. New before old, so no gap. On failure the old stream and `armedRoots`
  stay, so the next tick retries. `desired` empty tears the stream down. Creation goes through an internal
  injectable closure so a test can force failure. The timer starts when either list is non-empty. The
  `mustRescan` path keeps calling `onChange(watchedDirectories)`; the store ignores the URL list, so no change
  is needed.
- The rescan after re-arm is a stat of unchanged descriptors, so a warm refresh still reads 0 log bytes.

## Tasks

Slices never write the same file concurrently. Every task's acceptance includes `swift build --product
VibraApp` and `make test`, because `make test` alone does not compile the app target.

| # | Owner | Depends on | Task | Acceptance |
|---|---|---|---|---|
| 0 | planner | — | Foundation: every type above with stub bodies, `Session.key` | Build and `make test` green, committed |
| 1 | deepseek | 0 | `FileWatcher` poll transitions and root re-arm, tests on real FSEvents in a temp dir | Root created after start, two later writes fire; root vanishes and reappears still fires; root replaced between two ticks then written fires; DB absent to present fires; forced arm failure retries next tick; reverting each change fails a test |
| 2 | deepseek | 0 | `SessionIngest.health` and retention, errors propagated through scanner and adapters | Failed read stays failing until a successful re-read; a failing source that is deleted returns the adapter to `ready` next pass; a database source read successfully and then failing reports `failing(_, lastSuccess:)` with that time, not nil; `lastRefreshBytesRead == 0` on warm refresh; adapter appearing between refreshes is picked up; ingest output for a retained source is unchanged across failing passes, and the notifier given those identical inputs delivers and withdraws nothing |
| 3 | deepseek | 0 | `AttentionClock`, `ReturnRoute`, `HistoryCoverage`, notifier body uses `projectName` (or scheduled task name plus project), canary covers notification body | Test for working to awaitingInput to working to blocked, vanish then return, two sessions in one project; title with prompt-like text never appears in a body; `HistoryCoverage.agents == [.claudeCode, .codex, .hermes]` |
| 4 | deepseek | 0 | `SessionMenuModel.build`, `SessionDetailModel.build`, tests with six agents and 20+ sessions | All attention rows precede running rows; label disambiguation including shared id prefix; deterministic tie-break; wait text; both empty cases; notices alongside sessions, including `(never read)`; `isLive` false for a vanished session; a title and path canary never appears in `diagnosticLines` |
| 5 | planner | 1,2,3,4 | `SessionStore` snapshot and health-only updates, menu, detail and setup windows, diagnostics, delete `detected()`, migrate `canJump` callers and delete it with its test | Probes P1 to P7 |
| 6 | deepseek | 5 | Docs: `privacy.md` (one new key, `--dump-menu`, the env dump), `STATUS.md:31-37`, `ROADMAP.md:349-353`, `features.md`, `troubleshooting.md`, `CHANGELOG.md`, jump and first-run text in the four READMEs | Each changed claim matches a probe; no claim about signing or notarization changes |

File lists:

- planner task 0: `Sources/VibraCore/Status/StatusTypes.swift`, `Sources/VibraCore/Status/AttentionClock.swift`, `Sources/VibraCore/Status/ReturnRoute.swift`, `Sources/VibraCore/History/HistoryCoverage.swift`, `Sources/VibraCore/Presentation/SessionMenuModel.swift`, `Sources/VibraCore/Presentation/SessionDetailModel.swift` (all new), `Sources/VibraCore/Models/Session.swift`.
- deepseek 1: `Sources/VibraCore/Watch/FileWatcher.swift`, `Tests/VibraCoreTests/FileWatcherTests.swift`.
- deepseek 2: `Sources/VibraCore/Ingest/SessionIngest.swift`, `Sources/VibraCore/Ingest/JSONLTreeScanner.swift`, `Sources/VibraCore/Adapters/ClaudeCodeAdapter.swift`, `Sources/VibraCore/Adapters/CodexAdapter.swift`, `Sources/VibraCore/Adapters/VSCodeAdapter.swift`, `Sources/VibraCore/Adapters/OpenCodeAdapter.swift`, `Sources/VibraCore/Adapters/CursorAdapter.swift`, `Sources/VibraCore/Adapters/HermesAdapter.swift`, `Sources/VibraCore/Adapters/AgentAdapter.swift`, `Tests/VibraCoreTests/IngestHealthTests.swift` (new), `Tests/VibraCoreTests/HermesAdapterTests.swift`, `Tests/VibraCoreTests/OpenCodeAdapterTests.swift`, `Tests/VibraCoreTests/CursorAdapterTests.swift`, `Tests/VibraCoreTests/JSONLTreeScannerTests.swift`, `Tests/VibraCoreTests/MalformedInputTests.swift`.
- deepseek 3: `Sources/VibraCore/Status/AttentionClock.swift`, `Sources/VibraCore/Status/ReturnRoute.swift`, `Sources/VibraCore/History/HistoryCoverage.swift`, `Sources/VibraCore/Notify/AttentionNotifier.swift`, `Tests/VibraCoreTests/AttentionNotifierTests.swift`, `Tests/VibraCoreTests/AttentionClockTests.swift` (new), `Tests/VibraCoreTests/ReturnRouteTests.swift` (new).
- deepseek 4: `Sources/VibraCore/Presentation/SessionMenuModel.swift`, `Sources/VibraCore/Presentation/SessionDetailModel.swift`, `Tests/VibraCoreTests/SessionMenuModelTests.swift` (new), `Tests/VibraCoreTests/SessionDetailModelTests.swift` (new).
- planner task 5: `Sources/VibraApp/SessionStore.swift`, `Sources/VibraApp/MenuBarController.swift`, `Sources/VibraApp/AppDelegate.swift`, `Sources/VibraApp/AdapterRegistry.swift`, `Sources/VibraApp/SessionDetailWindowController.swift` (new), `Sources/VibraApp/SetupWindowController.swift` (new), `Sources/VibraApp/HistoryWindowController.swift`, `Sources/VibraApp/Notify/UserNotificationSink.swift`, `Sources/VibraApp/main.swift`, `Sources/VibraCore/Detect/AgentDetector.swift`, `Sources/VibraCore/Locate/ProcessLocator.swift`, `Sources/VibraCore/Settings/VibraSettings.swift`, `Tests/VibraCoreTests/AgentDetectorTests.swift`, `Tests/VibraCoreTests/SettingsAndPipelineTests.swift`, `Tests/VibraCoreTests/ProcessLocatorTests.swift`.
- deepseek 6: `docs/privacy.md`, `docs/STATUS.md`, `docs/ROADMAP.md`, `docs/features.md`, `docs/troubleshooting.md`, `CHANGELOG.md`, `README.md`, `README.zh-CN.md`, `README.ja.md`, `README.ko.md`.

## Code-gate probes

Output saved to `$SCRATCH/probes-rN.txt`. All run against the built `Vibra.app` with `VIBRA_HOME`
pointing at a fixture tree, never the developer's real agent data.

The running app is observable through one env-guarded channel. With `VIBRA_DEBUG_MENU_DUMP=<path>` set,
`MenuBarController` atomically writes `diagnosticLines` after each snapshot. With it unset, nothing is
written, matching the `VIBRA_HOME` pattern. It exercises the real `AppDelegate` wiring, which is where the
frozen-adapter bug lives.

Launch for every running-app probe is the bundled executable, in the background, with env set inline:
`VIBRA_HOME=<fixture> VIBRA_DEBUG_MENU_DUMP=<path> build/Vibra.app/Contents/MacOS/Vibra`. `open` is not used,
because LaunchServices would not pass the environment and the app would read the developer's real agent
data. Each probe also asserts that the dump lists only fixture session ids, so a mis-launch fails loudly.

- P1 discovery: start the app on an empty `VIBRA_HOME`. Create `.claude/projects/...jsonl` ending in a producing
  record, then append a turn-complete record. The dump shows the session as `working` within 5 s and then its
  change to `awaitingInput` within 5 s, the append marker being that state change. The bound is measured by
  timestamps taken outside the app. Negative controls, in a
  scratch copy of the final tree with the dump kept: (a) revert only the startup registry change, (b) revert
  only the root re-arm. Each must fail P1 for its predicted reason, quoted in the probe output.
- P2 cross-agent ordering: `--dump-menu` on a fixture with six agents and 20+ sessions; all needs-you rows
  first.
- P3 health, on the running app. Read failure: `kill -STOP` the app, append to the source, `chmod 000`
  it, `kill -CONT`, so the pending append can only be read after permissions are gone. The dump shows `.readFailed` with the session
  list unchanged. `chmod 644` alone clears it on the next pass and the append is folded in. Listing failure:
  `chmod 000` the fixture `.claude/projects` root and `touch` it. The dump shows `.listFailed`, sessions
  unchanged. `.parseFailed` is covered by unit tests on a schema-mismatched fixture.
- P4 detail: `--show-detail` for an OpenCode and a Claude Code fixture session renders a snapshot PNG; the
  OpenCode one has no Return button, the Claude Code one shows `Return to Session`, and a vanished session's
  Return button is disabled.
- P5 setup: `--show-setup` snapshot on the current build, after the asynchronous authorization status
  arrives, reporting real authorization and real `SMAppService` status. A
  `DictionarySettingsStore` test round-trips `onboardingCompleted`. One relaunch against a temporary preferences
  domain shows the window once, not twice.
- P6 cost: idle CPU over a fixed window against a `b14ecf0` build with both numbers and run counts. The
  zero-byte property is asserted by the new unit test in task 2; `--bench` already uses `all()` so it cannot
  fail on this change.
- P7 menu: a `--menu-check` diagnostic builds the real `NSMenu` from a fixture and invokes a
  `Session Details` submenu item through `performActionForItem`, confirming the detail window opens with
  the right session.
- `make test` green; canaries pass; each new test shown able to fail by reverting its fix.

## Privacy and performance constraints

- No network. `SourceProblem` carries no error text. Notification bodies stop using `displayName`, which
  can be a prompt-derived title; task 3 owns this and its canary. Notices contain no prompt, command or path.
- `--query` and `--report --json` keep their exact keys; this run adds nothing to them.
- Persistent state grows by one key, `onboardingCompleted`; `privacy.md` changes in the same PR.
- `--dump-menu` and `VIBRA_DEBUG_MENU_DUMP` emit `diagnosticLines`: keys, states and codes, no title, path or
  branch. A canary test covers it. The dump writes only when the env var is set.
- `AttentionClock` and the detail model are memory-only.

## Round objections and changes

### Round 1 (plan v0.1, both seats PLAN-REJECTED)

| Objection | Change |
|---|---|
| AttentionClock dropped non-attention memory, so `.observed` was unreachable (Codex 1, DeepSeek 1) | Clock keeps every present session's state, prunes absent keys, tests added |
| Health could not see scanner and adapter failures; stale behaviour undefined (Codex 2) | Errors propagate by throwing through scanner and adapters, task 2 list broadened; sessions retained through failure; notifier consequence defined and tested |
| Per-pass health vanishes; `ready(now)` churns the snapshot (DeepSeek 2) | Failures sticky until a successful re-read; `lastSuccess` stamped only on actual reads. Partly disagree on the mechanism: a failed read writes no entry, so the descriptor differs and the source is retried each pass rather than reused, but the required behaviour and its test are adopted |
| ReturnTarget overstated exactness and ignored vanished sessions (Codex 3, DeepSeek 3) | Replaced by `ReturnRoute` (`attempt`, `focusApp`, `none`) plus `isLive`; no surface claims "exact"; each click re-attempts |
| Four-character id prefix can collide (Codex 4, DeepSeek nit 8) | Shortest unique prefix of at least 4, full id fallback, test with a shared prefix |
| Stream recreation had an unarmed failure state (Codex 5) | `armedRoots`; new stream created and started before the old is stopped; failure keeps the old and retries next tick; injectable creation for the test |
| `canJump` deletion before its callers migrate (Codex 6, DeepSeek 8) | Deletion moved to task 5; every task's acceptance now builds `VibraApp` |
| Privacy claim about notifications had no owner (Codex 7) | Task 3 owns `AttentionNotifier` body and canary |
| P1 and P3 could not fail (Codex 8, DeepSeek 5) | Env-guarded dump from the running app exercises real wiring; P1 also run against `b14ecf0`; P3 forces a read with `touch` |
| "No coding agents found" asserts what `.absent` cannot support (DeepSeek 4) | `No sessions yet` plus supported list; never says not installed |
| Alternate-item path unprobed and invisible (DeepSeek 6) | Dropped `isAlternate`; a visible `Session Details` submenu is the single secondary path; P7 invokes it |
| Two owners for `AttentionClock` and `ReturnTarget` (DeepSeek 7) | Task 0 creates all files as stubs; task 3 edits them |

Folded non-blocking suggestions: `None reported` wording, `first seen 4m ago`, P6 restated, `SMAppService`
reported in P5, `--dump-menu` added to `privacy.md`, residual bare session-id ambiguity recorded,
`NotchOverlay` and `AttentionNotifier` signatures stated as unchanged.

### Round 2 (plan v0.2, both seats PLAN-REJECTED)

| Objection | Change |
|---|---|
| "Failure then recovery delivers nothing" overclaimed: LivePipeline still ages and removes retained rows (Codex 1) | Claim replaced by a precise rule: ingest output is identical across failing passes, so a failure alone changes nothing; decay, window and liveness run as for any source. Test asserts the identical-input property. No per-row stale flag; notice and `healthLine` carry it |
| One-per-source notices cannot be built from per-agent health (Codex 2, DeepSeek nit 1) | Notices are per failing agent |
| Sticky map never cleared for a deleted or rotated source (Codex 2, DeepSeek 2) | Lifecycle defined: intersect with `sources()` output when it succeeds; keep all when it throws; test added |
| Path set misses a root replaced between ticks (Codex 3) | `armedRoots` holds `(device, inode)`; replacement test added |
| P3 could not read at cached EOF (Codex 4) | Append and `chmod 000` in one command; `chmod 644` alone clears it; list failure probed separately |
| P1 negative control had no observer (Codex 5, DeepSeek nit 10) | Controls keep the dump and revert one change each, with the predicted failure quoted |
| Dumps carry titles and paths (Codex 6) | `diagnosticLines` is content-free by construction, with a canary test |
| `open` loses env and reads real data (DeepSeek 1) | Launch command named; dump asserted to contain only fixture ids |

Folded non-blocking suggestions: deterministic tie-break, `(never read)` wording, `HistoryCoverage` assertion,
`Session Details` items always open details and are rebuilt per open, `chmod 644` alone in P3, list failure
probe. `mustRescan` deliberately unchanged, with the reason in the plan.

### Round 3 (plan v0.3, Codex PLAN-APPROVED, DeepSeek PLAN-REJECTED)

| Objection | Change |
|---|---|
| `lastSuccess` tied to a byte counter that the database branch never increments (DeepSeek 1) | Stamped on a successful re-read for JSONL and SQLite alike; test added for a database source that succeeds then fails |

Folded non-blocking suggestions from both seats: P3 made deterministic with `kill -STOP`; P1 observes a state
change as its append marker, timed externally; setup wording avoids `not installed`; closing setup completes it;
`onboardingCompleted` round-trip and relaunch check; P4 asserts both route mappings and the vanished case;
`SessionStore` named as the clock's owner.

## Planner approval

Plan v0.4, sha256 prefix 7e7ff91cb526e6ec (the text before this record was appended).

- `deepseek-plan-r5`: PLAN-APPROVED
- `codex-plan-r5`: PLAN-APPROVED
- PLANNER (claude): PLAN-APPROVED

Round 4 was void. The patch script failed before writing, so both seats reviewed unchanged v0.3 text and each
rejected it for that reason. Round 5 re-sent the actual v0.4, bound to its hash.

Review base for the code gate: `b14ecf0fb58dbe3fa03b433ce9e5fea6e064c589`.

## Outcome

Implemented A1 to A5 of the external plan's Milestone A on `feat/first-use-loop`. Not pushed. A6 (signed,
notarized build) is not done: this machine reports 0 code signing identities and Developer ID is an owner
decision (`docs/ROADMAP.md:411-423`).

Rounds: plan gate 5 rounds, of which round 4 was void (the patch script failed before writing, so both seats
reviewed unchanged text). Code gate 3 rounds.

What each seat caught:

- Codex: `AttentionClock` losing non-attention state; health unable to see scanner and adapter failures; stream
  recreation with an unarmed failure state; root replacement between ticks; P1 and P3 unable to fail; content
  in diagnostics; a nested unreadable directory aborting the whole listing; a horizon rule that violated the
  approved sticky-failure text; probes that printed instead of asserting.
- DeepSeek: per-pass health that vanished; `ReturnTarget` repeating the exactness error; `No coding agents
  found` asserting what `.absent` cannot support; `open` losing env and reading real data; `lastSuccess` tied
  to a byte counter the database branch never increments; a control that passed a window longer than the
  safety timer; `VSCodeAdapter` aborting on one workspace.
- Planner: FSEvents never delivering for a root absent at stream creation (measured); an empty listing
  stamping `lastSuccess` every pass.

Verification at the approved revision, in `$SCRATCH/probes-r3.txt` (`GATE=0`): `make test
SWIFT_BUILD_SYSTEM=native` 308 tests in 41 suites, both canaries. P1 on the running app 0.3 s and 0.02 s
against a 5 s bound; control a (frozen adapters) and control b (no re-arm) both fail that bound, and control b
arrives at about 57 s through the safety timer. P3, P2, P4, P5, P7 pass. P6 idle CPU, 3 runs of 60 s against
`b14ecf0`: base 0.04, 0.07, 0.08 CPU-seconds, new 0.07, 0.08, 0.08, measured before the final two commits,
which change only failure paths and docs. That difference is inside the 0.01 s sampling of `ps`.

Not verified: the menu was built and its Session Details item invoked by `--menu-check`, but no one clicked
the real status item in this run. Notification delivery and `SMAppService` registration were only reported
by status (`notifications are off`, login item `notFound` for the probe copy), not exercised.

Known limits, recorded rather than fixed: a failing source that ages past the horizon stays failing until
re-read or no longer listed; an unreadable nested directory is skipped without a notice; a click on a
notification still resolves by bare session id.

Review evidence caveat: Codex's final approval came from a 12 s turn scoped by the planner's follow-up to the
three round-1 defects, after a first turn that ended with no file. Its only full read of the diff was round 1.
DeepSeek re-read the full diff at the final revision. The Codex TUI showed `GPT-6-Sol` during the plan gate and
`GPT-6-Luna` by code gate round 2; the planner did not change it.

### Final verdicts, diff revision 905be7c6e0b5976226dbfad9693b832c60fa61fa, base b14ecf0

- `deepseek-impl-r3`: IMPL-APPROVED
- `codex-impl-r3`: IMPL-APPROVED
- PLANNER (claude): IMPL-APPROVED

## Dispatch ledger

The row `impl-note` is a planner mistake (a stray test call) and corresponds to no task. `codex-impl-r2` was
marked superseded on the belief its send never landed; the seat did receive the later r3 prompt.

```
2026-11-08T08:43:01Z	deepseek-audit-r1	deepseek	base b14ecf0	sent
2026-11-08T08:43:20Z	deepseek-audit-r1	deepseek	dialog: external dir SCRATCH	question scratch access
2026-11-08T08:43:20Z	deepseek-audit-r1	deepseek	dialog: external dir SCRATCH	answered allow once
2026-11-08T08:43:20Z	deepseek-audit-r1	deepseek	base b14ecf0	delivered
2026-11-08T08:45:51Z	codex-audit-r1	codex	base b14ecf0	sent
2026-11-08T08:45:55Z	codex-audit-r1	codex	base b14ecf0	delivered
2026-11-08T08:48:16Z	codex-audit-r1	codex	base b14ecf0	verdict AUDIT-DONE
2026-11-08T08:50:19Z	deepseek-audit-r1	deepseek	base b14ecf0	verdict AUDIT-DONE
2026-11-08T08:54:03Z	deepseek-plan-r1	deepseek	plan v0.1	sent
2026-11-08T08:54:05Z	codex-plan-r1	codex	plan v0.1	sent
2026-11-08T08:54:16Z	deepseek-plan-r1	deepseek	plan v0.1	delivered
2026-11-08T08:54:16Z	codex-plan-r1	codex	plan v0.1	delivered
2026-11-08T08:57:17Z	codex-plan-r1	codex	plan v0.1	verdict PLAN-REJECTED
2026-11-08T08:58:32Z	deepseek-plan-r1	deepseek	plan v0.1	verdict PLAN-REJECTED
2026-11-08T08:59:53Z	deepseek-plan-r2	deepseek	plan v0.2	sent
2026-11-08T08:59:55Z	codex-plan-r2	codex	plan v0.2	sent
2026-11-08T09:00:00Z	deepseek-plan-r2	deepseek	plan v0.2	delivered
2026-11-08T09:00:00Z	codex-plan-r2	codex	plan v0.2	delivered
2026-11-08T09:01:57Z	codex-plan-r2	codex	plan v0.2	verdict PLAN-REJECTED
2026-11-08T09:03:57Z	deepseek-plan-r2	deepseek	plan v0.2	verdict PLAN-REJECTED
2026-11-08T09:03:58Z	deepseek-plan-r3	deepseek	plan v0.3	sent
2026-11-08T09:03:59Z	codex-plan-r3	codex	plan v0.3	sent
2026-11-08T09:04:05Z	deepseek-plan-r3	deepseek	plan v0.3	delivered
2026-11-08T09:04:05Z	codex-plan-r3	codex	plan v0.3	delivered
2026-11-08T09:05:58Z	codex-plan-r3	codex	plan v0.3	verdict PLAN-APPROVED
2026-11-08T09:06:26Z	deepseek-plan-r3	deepseek	plan v0.3	verdict PLAN-REJECTED
2026-11-08T09:06:26Z	deepseek-plan-r4	deepseek	plan v0.4	sent
2026-11-08T09:06:28Z	codex-plan-r4	codex	plan v0.4	sent
2026-11-08T09:06:34Z	deepseek-plan-r4	deepseek	plan v0.4	delivered
2026-11-08T09:06:34Z	codex-plan-r4	codex	plan v0.4	delivered
2026-11-08T09:07:31Z	deepseek-plan-r4	deepseek	plan v0.3 text, mis-sent as v0.4	superseded
2026-11-08T09:08:09Z	codex-plan-r4	codex	plan v0.3 text, mis-sent as v0.4	superseded
2026-11-08T09:08:09Z	deepseek-plan-r5	deepseek	plan v0.4 7e7ff91cb526e6ec	sent
2026-11-08T09:08:11Z	codex-plan-r5	codex	plan v0.4 7e7ff91cb526e6ec	sent
2026-11-08T09:08:17Z	deepseek-plan-r5	deepseek	plan v0.4 7e7ff91cb526e6ec	delivered
2026-11-08T09:08:17Z	codex-plan-r5	codex	plan v0.4 7e7ff91cb526e6ec	delivered
2026-11-08T09:09:01Z	codex-plan-r5	codex	plan v0.4 7e7ff91c	verdict PLAN-APPROVED
2026-11-08T09:09:56Z	deepseek-plan-r5	deepseek	plan v0.4 7e7ff91c	verdict PLAN-APPROVED
2026-11-08T09:11:05Z	planner-task0	planner	build and make test 254 green	done succeeded
2026-11-08T09:11:05Z	deepseek-task1-a1	deepseek	plan v0.4, base b14ecf0	sent
2026-11-08T09:11:12Z	deepseek-task1-a1	deepseek	plan v0.4, base b14ecf0	delivered
2026-11-08T09:22:32Z	deepseek-task1-a1	deepseek	make test native 3/3, 259 tests	done succeeded
2026-11-08T09:22:33Z	deepseek-task2-a1	deepseek	plan v0.4, base b14ecf0	sent
2026-11-08T09:22:39Z	deepseek-task2-a1	deepseek	plan v0.4, base b14ecf0	delivered
2026-11-08T09:32:51Z	deepseek-task2-a1	deepseek	make test native 271 tests; planner fixed empty-listing stamp and horizon clear	done succeeded
2026-11-08T09:32:52Z	deepseek-task3-a1	deepseek	plan v0.4, base b14ecf0	sent
2026-11-08T09:32:58Z	deepseek-task3-a1	deepseek	plan v0.4, base b14ecf0	delivered
2026-11-08T09:36:31Z	deepseek-task3-a1	deepseek	make test native 281 tests	done succeeded
2026-11-08T09:36:31Z	deepseek-task4-a1	deepseek	plan v0.4, base b14ecf0	sent
2026-11-08T09:36:38Z	deepseek-task4-a1	deepseek	plan v0.4, base b14ecf0	delivered
2026-11-08T09:43:04Z	deepseek-task4-a1	deepseek	make test native 306 tests	done succeeded
2026-11-08T09:44:06Z	deepseek-task5b-a1	deepseek	plan v0.4, base b14ecf0	sent
2026-11-08T09:44:13Z	deepseek-task5b-a1	deepseek	plan v0.4, base b14ecf0	delivered
2026-11-08T09:52:44Z	planner-task5	planner	P1-P5 P7 pass, controls fail as predicted; P6 running	done succeeded
2026-11-08T09:52:44Z	deepseek-task5b-a1	deepseek	fixture: 24 sessions, six agents, P2 pass	done succeeded
2026-11-08T09:52:45Z	deepseek-task6-a1	deepseek	plan v0.4, base b14ecf0	sent
2026-11-08T09:52:51Z	deepseek-task6-a1	deepseek	plan v0.4, base b14ecf0	delivered
2026-11-08T09:56:38Z	deepseek-task6-a1	deepseek	docs spot-checked against source	done succeeded
2026-11-08T10:00:43Z	deepseek-impl-r1	deepseek	base b14ecf0 rev ea1457c	sent
2026-11-08T10:00:45Z	codex-impl-r1	codex	base b14ecf0 rev ea1457c	sent
2026-11-08T10:00:51Z	deepseek-impl-r1	deepseek	base b14ecf0 rev ea1457c	delivered
2026-11-08T10:00:51Z	codex-impl-r1	codex	base b14ecf0 rev ea1457c	delivered
2026-11-08T10:03:47Z	codex-impl-r1	codex	base b14ecf0 rev ea1457c	verdict IMPL-REJECTED
2026-11-08T10:06:30Z	deepseek-impl-r1	deepseek	base b14ecf0 rev ea1457c	verdict IMPL-REJECTED
2026-11-08T10:07:23Z	impl-note	planner	x	done succeeded
2026-11-08T10:07:44Z	impl-note	planner	mistaken row, no such task	abandoned
2026-11-08T10:15:15Z	deepseek-impl-r2	deepseek	base b14ecf0 rev a531ed9	sent
2026-11-08T10:15:38Z	codex-impl-r2	codex	base b14ecf0 rev a531ed9	sent
2026-11-08T10:15:44Z	deepseek-impl-r2	deepseek	base b14ecf0 rev a531ed9	delivered
2026-11-08T10:15:44Z	codex-impl-r2	codex	base b14ecf0 rev a531ed9	delivered
2026-11-08T10:18:12Z	deepseek-impl-r2	deepseek	base b14ecf0 rev a531ed9	verdict IMPL-APPROVED
2026-11-08T10:18:12Z	codex-impl-r2	codex	not delivered: Codex composer stayed empty, no turn started	superseded
2026-11-08T10:22:53Z	deepseek-impl-r3	deepseek	base b14ecf0 rev 905be7c	sent
2026-11-08T10:23:15Z	codex-impl-r3	codex	base b14ecf0 rev 905be7c	sent
2026-11-08T10:23:25Z	deepseek-impl-r3	deepseek	base b14ecf0 rev 905be7c	delivered
2026-11-08T10:24:03Z	codex-impl-r3	codex	base b14ecf0 rev 905be7c	followup one resend: seat ended turn with no reply file
2026-11-08T10:24:11Z	codex-impl-r3	codex	base b14ecf0 rev 905be7c	delivered
2026-11-08T10:25:24Z	deepseek-impl-r3	deepseek	base b14ecf0 rev 905be7c	verdict IMPL-APPROVED
2026-11-08T10:25:24Z	codex-impl-r3	codex	base b14ecf0 rev 905be7c	verdict IMPL-APPROVED
2026-11-08T10:25:24Z	planner-gate	planner	base b14ecf0 rev 905be7c	done succeeded
2026-11-08T10:25:24Z	seat:deepseek	deepseek	-	disposition left
2026-11-08T10:25:24Z	seat:codex	codex	-	disposition left
```
