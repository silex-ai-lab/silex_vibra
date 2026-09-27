# Plan — history, query, settings, Hermes (2026-09-26)

> Status: **Plan approved (r5, unanimous). Implementation in progress.**
> seat on the roster returns PLAN-APPROVED.

## Why

A side-by-side comparison with another local, history-oriented agent monitor
(a web app that copies every prompt into its own database) found four things
Vibra lacks. The user picked all four; this plan builds them. The other tool's
code is **not** used: everything below is designed from Vibra's own code and
from the agents' on-disk formats, as ROADMAP.md already requires ("no copied
code").

1. A searchable, day-grouped **history of the questions you asked**.
2. An **agent-queryable interface** (`--query`, JSON).
3. **Settings** for the "needs attention" rules (stall threshold etc.).
4. A **Hermes** adapter (Hermes Agent, `~/.hermes/state.db`).

Deferred, recorded on the ROADMAP: an OpenClaw adapter. OpenClaw is not
installed on the development machine, so an adapter would be a guessed format
with no live verification.

## Design constraint that shapes items 1 and 2: Vibra still stores nothing

Vibra's promise is "reads the agents' files, keeps nothing". History is
normally built by copying records into a database. It is **not** here:

- History is read **on demand**, the same way the usage report is
  (`ReportIngest`): a separate reader, no state shared with `SessionIngest`,
  starting from byte 0, run only when the user opens the window.
- The result lives in memory only while the History window is open, and is
  dropped when it closes. Nothing is written to disk, no cache, no index.
- Settings (item 3) are the one thing persisted: three numbers in the app's
  `UserDefaults` domain. That is configuration, not agent data.

And the existing privacy rule is kept: **no diagnostic or machine-readable
output ever contains message content.** `--query` and the new
`--history-stats` print counts, states and project names only. Question text
appears in exactly one place: the History window on the user's own screen.

## Roster and ownership

| Seat | Runs as | Job |
|---|---|---|
| claude | calling pane | owns plan, implements everything, casts a written vote |
| reviewer-mimo | OpenCode, `opencode/mimo-v2.6-flash-free` | reviews plan and diff |
| reviewer-nemotron | OpenCode, `opencode/nemotron-3-ultra-free` | reviews plan and diff |

Reviewers write no code. Both gates are unanimous across all three seats.
Because one seat implements, there is no file split; tasks run in order.
Reviewers see only this public repo, this plan, and diffs — never the user's
agent state (`~/.claude`, `~/.codex`, `~/.hermes`, ...). Fixtures are synthetic.

Review base: `2164fa653d438cc45f0ef7f0134fbca43ae07fdc` (main, 2026-09-26). Plan gate: r5, unanimous.

## Tasks

### T0 — Foundation: settings model and one shared live-session pipeline

**T0a `VibraSettings` (VibraCore, new `Settings/VibraSettings.swift`).**
A value type holding the user-tunable thresholds, with defaults equal to
today's constants, so an untouched install behaves exactly as now:

| Setting | Key | Default | Allowed range |
|---|---|---|---|
| Stall threshold | `stallThresholdSeconds` | 300 | 60 … 7200 |
| "Your turn" decays to idle after | `attentionDecaySeconds` | 28800 (8 h) | 3600 … 172800 |
| Show sessions active within | `activityWindowSeconds` | 43200 (12 h) | 3600 … 259200 |

`workingWindow` (30 s) stays fixed: it is a parsing tolerance, not a
preference.

**Where they live.** Always the preferences domain `ai.silexlab.vibra`, read
and written through `CFPreferences` with that application id — never
`UserDefaults.standard`, whose domain for a bare binary (`make query`,
`swift run`) is the process name, so the CLI and the app would read different
numbers. `CFPreferencesAppSynchronize` runs before each load so a
`defaults write` made while the app runs is picked up on its next refresh.
Storage is behind a small `SettingsStore` protocol (CFPreferences in the app,
a dictionary in tests).

`load(from:)` clamps out-of-range numbers to the
range and replaces non-numeric values with the default (a bad `defaults write` cannot break classification) and
guarantees `stallThreshold > workingWindow`. `stateEngineConfig` derives a
`StateEngineConfig`. `save(to:)` / `reset(in:)` for the UI.

**T0b-core `LivePipeline` (VibraCore, new `State/LivePipeline.swift`).** The
pure part of the pipeline now inlined in `SessionStore.performRefresh`:
`recent(raw, settings, now)` (activity-window filter → `StateEngine.classify`
→ sort — the pipeline's only sort, as today) and `finish(recent, desktop:, claudeStatus:, live:, editorLaunch:)`
(`claudeStatus: [String: ClaudeLiveStatus]` feeds `enriched`,
`live: [AgentKind: Set<String>]` feeds `withoutExited`; the existing
`Session.enriched` → `withoutExited` → `settlingOrphaned`; no re-sort, as
today, so the order is unchanged). No I/O; every input is a parameter, so it is unit-tested in VibraCore.

**T0b `LiveSessions.snapshot(...)` (VibraApp, new `LiveSessions.swift`).**
The impure remainder only: gathers `desktop` (ClaudeDesktopIndex), `live`
(ProcessLocator), `editorLaunch` (TerminalJumper) off the main actor and calls
`LivePipeline`. `SessionStore` calls it; so does `--query` (T3). Today `--probe`, `--locate`
and `--jump` each re-implement a *subset* of it and so disagree with the menu
(e.g. `--probe` does not drop exited sessions). `--probe` is left as it is —
it is a raw diagnostic — but `--query` must say exactly what the menu says.

**T0c `--dump-sessions [--all]` (VibraApp).** Diagnostic: one line per
session — agent, id, project, state, lastEvent, lastActivity, entrypoint,
unattended. No title, no content. It runs `SessionStore`'s own refresh
(not a copy of its body), so before and after the refactor it prints the
menu's real output; `--all` constructs the store with an unbounded activity
window and ingest horizon (used for T1's real-data check). `SessionStore`
gains an `overrides` init parameter (activity window, horizon); when set it
**wins over** the per-refresh settings load (T2), so `--all` stays unbounded
after T2 lands. `SessionStore` passes the horizon to `SessionIngest` (today it
uses the ingest default).

*Acceptance:* `make test` green; existing tests unchanged. Settings tests:
defaults equal today's constants, each key clamps both ends, garbage → default,
stall ≤ working window impossible, the CFPreferences store uses domain
`ai.silexlab.vibra` regardless of process name. `LivePipeline` tests: window
filter; classification uses the passed settings (a 90 s-silent producing
session is `working` at stall 300 s and `stalled` at 60 s); `finish` equals
the old inline composition on a fixture set (enriched title, archived dropped,
exited dropped, orphaned editor session settled). Before/after: land T0c
*first* as its own local commit, capture `--dump-sessions` output, do the
refactor, capture again, and diff; the only differences allowed are sessions
whose `lastActivity` moved between the two runs (live drift), listed by hand.

### T1 — Hermes adapter

**Provenance, and correcting the ROADMAP.** ROADMAP P2.2 (2026-09-20)
recorded Hermes as `~/.hermes/sessions/sessions.json`, "no transcripts, no
token usage". That was incomplete. On 2026-09-26 the dev machine's
`~/.hermes/state.db` (`schema_version` 17) was read directly with `sqlite3
-readonly` (schema and counts only, no content): tables `sessions` (6 rows:
4 `cli`, 1 `feishu`, 1 `subagent`) and `messages` (285 rows). `sessions.json`
is a two-entry gateway routing map, not the session store. Observed DDL, the
columns this plan relies on:

```
sessions(id TEXT PK, source TEXT NOT NULL, model TEXT, started_at REAL NOT NULL,
  ended_at REAL, end_reason TEXT, cwd TEXT, git_branch TEXT, title TEXT,
  input_tokens INT, output_tokens INT, cache_read_tokens INT,
  cache_write_tokens INT, reasoning_tokens INT, parent_session_id TEXT,
  archived INT NOT NULL DEFAULT 0, ...)
messages(id INTEGER PK, session_id TEXT, role TEXT, content TEXT,
  timestamp REAL NOT NULL, finish_reason TEXT, active INT, ...)
INDEX idx_messages_session ON messages(session_id, timestamp)
roles seen: user, assistant, tool, session_meta
finish_reason seen: stop, tool_calls, length, NULL
active seen: 1 (all 285 rows)
ended_at IS NULL: 3 of 6 sessions (2 cli, 1 feishu), so status statement 2
  runs on real data
```

T5 rewrites the ROADMAP P2.2 Hermes row with this and the date. The
adapter is **verified against real data only for discovery** (T1 acceptance
below); its *live state transitions* are fixture-only and README says so, as
it already does for the unverified parts of Cursor and VS Code.

New `AgentKind.hermes` (display "Hermes", symbol `bubble.left.and.text.bubble.right`)
and `Adapters/HermesAdapter.swift`, modelled on `OpenCodeAdapter`'s security
contract:

- Path `VibraPaths.hermesStateDB` = `$VIBRA_HOME/.hermes/state.db`.
- Opened `SQLITE_OPEN_READONLY` + `mode=ro` URI. `sources()` fingerprints the
  db plus `-wal`/`-shm` (reuse `OpenCodeAdapter.describeDatabase`, moved to a
  shared helper). `FileWatcher.pollURL` becomes `pollURLs: [URL]`, and its
  poll signature folds each db's `-wal`/`-shm` in the same way (today a write
  that lands only in OpenCode's WAL may not wake the app — fixed for both).
  `SessionStore.start` passes `[openCodeDB, hermesStateDB]`.
- **Column allowlist, no `SELECT *`, `PRAGMA table_info` check first**
  (schema mismatch → `[]`, never a broader query). Tables: `sessions`,
  `messages` only. Columns from `sessions`: `id, source, model, started_at,
  ended_at, cwd, git_branch, title, input_tokens, output_tokens,
  cache_read_tokens, cache_write_tokens, archived, parent_session_id`.
  From `messages` on the status path: `id, session_id, role, finish_reason,
  timestamp, active` — **never `content`** on the status path.
- **Status SQL, exactly two statements, cost bounded by open sessions:**
  1. `SELECT id, source, model, started_at, ended_at, cwd, git_branch, title,
     input_tokens, output_tokens, cache_read_tokens, cache_write_tokens,
     parent_session_id FROM sessions WHERE archived = 0`
  2. Only for sessions with `ended_at IS NULL`:
     `SELECT role, finish_reason, timestamp FROM messages WHERE session_id = ?
     AND active = 1 AND role IN ('user','assistant','tool')
     ORDER BY timestamp DESC, id DESC LIMIT 1`
     — served by `idx_messages_session` (checked with `EXPLAIN QUERY PLAN`:
     `SEARCH messages USING INDEX idx_messages_session (session_id=?)`).
  An ended session needs no message read: it is `.settled` with
  `lastActivity = ended_at`. So cost scales with the number of *open*
  sessions, one indexed single-row lookup each, not with message volume.
- **`allSQL` splits into `statusSQL` and `historySQL`** (the T4 statement).
  Tests: every statement in both sets references only `sessions`/`messages`
  and no `SELECT *`; **no statement in `statusSQL` contains `content`**; the
  status code path is driven with a fixture and the SQL it actually prepares
  is recorded (the adapter takes an optional prepare-observer, test-only) and
  asserted to be ⊆ `statusSQL`.
- The query-plan test asserts the whole `EXPLAIN QUERY PLAN` output for
  statement 2 contains a `SEARCH messages USING INDEX` and no `SCAN messages`
  or `TEMP B-TREE`.
- `AdapterRegistry.all()` gains `HermesAdapter()`.
- A `FileWatcher` test covers the new poll signature: a write that changes
  only `<db>-wal` fires `onChange`.
- `~/.hermes` also holds `.env` and `auth.json` with secrets. They are never
  opened. A canary test (like OpenCode's) puts a secret token in a fixture
  `.env`, `auth.json`, and in a `messages.content` row, and asserts the
  token appears in no `Session` field, no `--query` JSON, and no error text.
- State, from each open session's latest active message among roles
  `user|assistant|tool` (`session_meta` ignored):
  - `archived = 1` → dropped (by the WHERE clause). On the dev machine all 6
    rows have `archived = 0`, so "6" is the one predicate `archived = 0`.
  - `ended_at` not null → `.settled`, `lastActivity = ended_at`.
  - last is `assistant` with `finish_reason` `stop` or `length` → `.turnComplete`.
  - last is `assistant` with `tool_calls`, or `tool`, or `user` → `.producing`.
  - otherwise → `.unknown`.
  - Hermes has no approval column we can see → never `.permissionPrompt`
    (stated in README as a known limitation, like OpenCode's was).
- `lastActivity` (open sessions) = that message's timestamp, else `started_at` (seconds, REAL).
- `entrypoint` = `sessions.source` (`cli`, `feishu`, `subagent`, ...). A
  `subagent` session is unattended (its finished turn asks nobody anything);
  `Session.isUnattended` gains that case. Gateway chats (`feishu`, etc.) are
  attended.
- Usage = per-session token columns. `reasoning_tokens` is not added (it may
  already be inside `output_tokens`; double counting is worse than omission —
  documented). No per-record timestamps for tokens → `usageSamples` returns
  `[]`, and the report's "undated totals" path, today special-cased to
  `.openCode`, becomes a protocol property `reportsUndatedTotals` that both
  set.
- Jump: `ProcessLocator` returns `nil` for Hermes (not locatable), and
  `liveSessionIDs` returns `nil` (cannot tell → keep sessions), exactly like
  OpenCode.

*Acceptance:*
- Fixture `Fixtures/hermes_state.sql` (synthetic DDL matching the observed
  schema, built into a temp db by the test) covering every state rule,
  archived, subagent, inactive (rewound) messages ignored, WAL fingerprint
  change, schema mismatch → `[]`.
- Canary test passes; the SQL-set tests above pass; mutation check: adding
  `content` to status statement 2 makes the suite fail (the `statusSQL`
  no-`content` assertion), confirmed by actually making the edit once.
- **Real data, by the implementing seat (Claude) only:** `--dump-sessions
  --all` lists exactly the ids `sqlite3 -readonly ~/.hermes/state.db "select
  id from sessions where archived=0"` returns (6 today), with the ended ones
  `idle` (settled) and `entrypoint` `subagent` on the subagent row. Recorded in
  the Outcome section as counts and states, not ids.
- Live state transitions are **not** claimed: the newest real Hermes activity
  is from July. So on the dev machine, under the default 12 h window, Hermes
  shows no menu, `--probe` or `--query` rows, and no History rows (July is
  beyond the 30-day maximum). That is expected, not a bug, and the README
  does not claim Hermes was observed live.

### T2 — Settings window

- Menu item **"Settings…"** (⌘,) opens a small window: three steppers with a
  text field each (minutes / hours, showing the allowed range), and
  **"Restore Defaults"**. Values save immediately via `VibraSettings.save`.
- `SessionStore` reads `VibraSettings.load()` at the start of every refresh
  and builds that refresh's `StateEngine` from `stateEngineConfig` (today it
  is a `let` made at init); a change in the window triggers
  `requestRefresh()`, so a new threshold takes effect immediately — no
  relaunch. `--probe` keeps today's fixed defaults on purpose (raw diagnostic).
- `ReportIngest`'s horizon is unaffected (the report has its own 7-day window).
- The `SessionIngest` freshness horizon follows `activityWindowSeconds`
  (otherwise raising the window to 24 h would show nothing older than 12 h,
  because those files are never read). `SessionIngest` gains
  `setHorizon(_:)`; widening it makes the next refresh consider the newly
  in-range sources (checkpoints of already-read sources are kept, no cold pass).

*Acceptance:* `defaults write ai.silexlab.vibra stallThresholdSeconds 60`,
then `.build/release/VibraApp --query` (a fresh process) against a fixture
tree via `VIBRA_HOME` shows a 90 s-silent mid-turn session as `stalled`, and
as `working` after `defaults delete`. The running app picking the change up
without relaunch rests on `CFPreferencesAppSynchronize` per refresh and is
checked once by hand. `SessionIngest.setHorizon` unit test: widening makes an
older fixture source appear. Window opens and renders (`--show-settings
--snapshot`).

### T3 — `--query` (agent-queryable, JSON)

`Vibra --query [--attention] [--agent <kind>]` prints one JSON object to
stdout and exits 0 (exit 1 on internal failure):

```json
{"generatedAt":"…ISO8601…","settings":{"stallThresholdSeconds":300,…},
 "sessions":[{"agent":"claudeCode","id":"…","project":"silex_vibra",
   "cwd":"/…","gitBranch":"main","state":"awaitingInput","needsAttention":true,
   "lastEvent":"turnComplete","lastActivity":"…","startedAt":"…",
   "model":"…","tokens":{"input":0,"output":0,"cacheRead":0,"cacheCreation":0},
   "estimatedCostUSD":0.12,"unattended":false}]}
```

- Built from `LiveSessions.snapshot` (T0b), so it matches the menu. The
  output types and encoder (`QueryOutput`, taking `[Session]` +
  `VibraSettings` + `now`) live in **VibraCore**, so the schema test and the
  canary can build: the test target cannot link VibraApp (an executable).
- **No `title`.** Titles are derived from message text (OpenCode, Claude UI).
  Excluding them keeps the rule "machine-readable output has no message
  content" without exceptions. `project` + `cwd` + `id` identify a session.
- `estimatedCostUSD` is `null` when the model has no published rate (never 0).
- Keys are stable and sorted (`JSONEncoder.outputFormatting = .sortedKeys`);
  dates ISO 8601.
- `Makefile`: `make query` runs it from the build (`.build/release/VibraApp
  --query`); it reads the same `ai.silexlab.vibra` settings as the app (T0a).
  `docs/skills/vibra-query/SKILL.md` documents it for an agent: when to call
  it, the fields, the "never contains content" guarantee, and both paths —
  `/Applications/Vibra.app/Contents/MacOS/Vibra --query` after `make install`,
  or the build path.

*Acceptance:* test encodes a fixture snapshot and checks the schema and key
set; canary test (T1) also runs over `--query`'s encoder; `--attention`
returns only `needsAttention == true`; output parses with `python3 -m json.tool`.

### T4 — History window (on demand, nothing stored)

**Core.** New `QuestionRecord {agent, sessionID, timestamp, project, text}`
and two adapter entry points:

- `historyExtractor() -> (any HistoryExtractor)?` — JSONL adapters. A
  `HistoryExtractor` is a **stateful, per-source** folder:
  `mutating func fold(_ lines: [String]) -> [QuestionRecord]`. `HistoryIngest`
  makes one extractor per source and feeds it every batch of that source in
  order, so session-level facts seen early (Codex `session_meta.originator`,
  Claude's first-prompt `<scheduled-task>` tag, `entrypoint`) apply to every
  later batch. It carries only those facts (ids, cwd, flags), never earlier
  text. Default `nil` = "this adapter has no history", and `HistoryIngest`
  then **does not read that adapter's files at all** (VS Code, Cursor,
  OpenCode), so `--history-stats`' bytes-read is meaningful.
- `storedQuestions(since: Date) -> [QuestionRecord]` — database adapters,
  default `[]`. Only `HermesAdapter` implements it in v1.

`HistoryIngest` (actor, modelled on `ReportIngest`: separate reader, from byte
0, `windowDays` 1…30, default 7) reads, per adapter that has an extractor,
each `jsonl` source whose mtime is within **window + 1 day** (the
`ReportIngest` precedent: a file written just after midnight holds the
previous day's records); then calls `storedQuestions(since:)` with the same
widened cutoff. **The window itself is applied per record, for every
adapter**, in `HistoryIndex.build(records, since:, calendar:)`: a question is
shown iff its local day is ≥ the window's first local day, computed exactly
as `ReportBuilder` does (`calendar.date(byAdding: .day, value: -(windowDays -
1), to: startOfDay(now))`) — one meaning for
"last N days" whatever the source. `--history-stats --days N` goes through
the same function.
`HistoryIndex` (pure, testable, takes an injected `Calendar` like
`UsageAggregator.byDay`) groups by local day, newest first, and filters
by keyword (case- and diacritic-insensitive substring), agent, and project.

What counts as "a question you asked", per adapter in v1. **Provenance:**
the record shapes below were observed on 2026-09-26 on the dev machine by
counting record types and key names only (no text read beyond classifying a
leading wrapper tag): 10 recent Claude transcripts (user records: 409
tool-result, 71 plain string, 8 `isMeta`, 7 text-block; all carry
`entrypoint`, `cwd`, `sessionId`), 40 recent Codex rollouts (`originator`
`codex-tui`; user prompts appear only as `response_item` / `message` /
`role: "user"` with `input_text` blocks — **no `event_msg` `user_message`
records at all** in this Codex version; of those blocks, 6 plain, 3
`<environment_context>`, 3 `<turn_aborted>`).


- **Claude Code**: `type == "user"` records whose `message.content` is a
  string or has a `text` block, excluding `isMeta`, `isSidechain`
  (subagent prompts), tool results, and command/stdout wrappers
  (`<command-name>`, `<local-command-stdout>`, `<local-command-caveat>`,
  `<system-reminder>`-only). Unattended sessions (`sdk-cli`, scheduled task)
  excluded: nobody typed those.
- **Codex**: `response_item` whose payload is `type: "message"`,
  `role: "user"`, taking its `input_text` blocks; a block that is entirely one
  wrapper element (`<environment_context>…`, `<turn_aborted>…` — both
  observed; `<user_instructions>…` and a leading `# AGENTS.md instructions`
  — defensive, not observed) is dropped.
  `event_msg`/`user_message` is ignored even if an older Codex writes it, so
  a prompt is never counted twice. Accepted consequence: a Codex version that
  wrote prompts *only* as `event_msg` would show no history in v1; the
  current version does not. Sessions whose `session_meta.originator`
  is `codex_exec` are excluded (unattended).
- **Hermes**: `storedQuestions(since:)` runs the single `historySQL`
  statement:
  `SELECT m.session_id, m.timestamp, m.content, s.cwd FROM messages m JOIN
  sessions s ON s.id = m.session_id WHERE m.role = 'user' AND m.active = 1
  AND m.timestamp >= ? AND s.archived = 0 AND s.source <> 'subagent'
  ORDER BY m.timestamp`
  It is the only statement that selects `content`; it is in `historySQL`, not
  `statusSQL`, and the prepare-observer test (T1) proves the status path never
  prepares it.
- **OpenCode, Cursor, VS Code**: not in v1. Their prompt text lives in stores
  (OpenCode `part` table, Cursor/VS Code state DBs) whose reading would widen
  those adapters' security contracts; the window says "History covers Claude
  Code, Codex and Hermes" rather than implying completeness.

Text is trimmed and capped at 2,000 characters in memory; a row shows the
first line (≤ 160 chars).

**App.** Menu item **"History…"** (⌘Y) opens a window: search field, agent
pop-up, a "last N days" pop-up (1, 3, 7, 14, 30; default 7), and an
`NSOutlineView` grouped by day (rows: time · agent · project · first line).
Double-click a row → the existing jump for that session if it is still live,
otherwise copy the full text to the pasteboard. Loading shows a progress
line first, like the usage report. Closing the window releases the records.

`--history-stats [--days N]` prints per-day, per-agent **counts only** and
bytes read — the testable CLI face of the feature. Its formatter
(`HistoryStats.format`) lives in VibraCore so the canary is a `make test`
unit test. "Bytes read" counts JSONL reader bytes, as `ReportIngest` does, so
a Hermes-only history prints 0 bytes.

*Acceptance:* fixture tests for each adapter's inclusion/exclusion rules
(meta, sidechain, tool result, wrappers, unattended); **a batch-boundary
test**: `IncrementalLineReader` with a small injected `maxLinesPerRead` (e.g.
3) over a `codex_exec` rollout and a scheduled-task Claude transcript whose
questions sit after the first batch — both must yield zero questions (and
the same files with the unattended marker removed must yield them, so the
test can fail); **a window test**: a source with an in-window mtime holding a
question older than the window shows it neither in `HistoryIndex` nor in
`HistoryStats` counts; local-day bucketing across midnight UTC with an
injected calendar/time zone; keyword/agent/project filters; an adapter with
no extractor has zero bytes read; `--history-stats` output
contains no fixture message text (canary); window renders (snapshot flag);
steady-state `make bench` still reads 0 bytes on an unchanged refresh (history
must not touch the polling path).

### T5 — Docs and log

README (agents table + Hermes + known limitations, History, Settings,
`--query`; the `## Privacy and safety` section gains the history rule: prompt
text in memory only while the window is open, never written, machine output
still content-free), STATUS.md, ROADMAP.md (new Phase 4 rows, OpenClaw deferred with
reason; P2.2 Hermes row rewritten, and its "no adapter is developed by reading
the user's real session data" decision amended: reading schema and row counts
is not reading session data, and neither are record-type and key-name counts
or classifying a leading wrapper tag — no message text beyond that), this plan file updated with the review tables and the Outcome
section. Version bump to 0.3.0 in the Makefile.

## Out of scope

- Export (CSV/Excel/JSON of history). `--query` is the machine interface; a
  history export would write prompt text to disk, which the design rules out.
- Per-task success/failure outcomes under each question.
- OpenClaw.

## Verification (all before the code gate)

`make test` (count goes up, canary present), `make bench` (PASS),
`make probe`, `--agents`, `--query | python3 -m json.tool`,
`--history-stats`, `--show-history --snapshot`, `--show-settings --snapshot`,
`make install` and a manual look at the menu.

## Round-1 objections → changes

r1 verdicts: nemotron PLAN-APPROVED; mimo PLAN-REJECTED (6 blocking).

| # | Objection (who) | Change |
|---|---|---|
| 1 | T1 Hermes schema has no basis in the repo; ROADMAP says `sessions.json`, no transcripts; every T1 check passes vacuously (mimo) | Read the real `state.db` schema (schema only), recorded the DDL and date in T1 "Provenance", explained `sessions.json`; T5 corrects the ROADMAP row; added a real-data discovery check via `--dump-sessions --all`; live transitions declared fixture-only |
| 2 | T4 Hermes history unreachable: `ReportIngest`-style ingest skips non-JSONL (mimo) | Second entry point `storedQuestions(since:)`, the exact branch in `HistoryIngest`, the exact SQL, `allSQL` split into `statusSQL`/`historySQL` |
| 3 | T3/T0b tests unbuildable: test target cannot link VibraApp (mimo) | Pure pipeline → VibraCore `LivePipeline`; `QueryOutput` encoder in VibraCore; T0b in VibraApp is only the input gathering |
| 4 | T2 defaults domain not pinned; bare CLI reads a different domain (mimo) | CFPreferences with application id `ai.silexlab.vibra` everywhere, behind `SettingsStore`; test for it; T2 acceptance names the binary |
| 5 | Nothing enforces "status path never reads `content`"; no cost bound on SQLite (mimo) | Exact status SQL written down; ended sessions need no message read; open sessions one indexed `LIMIT 1` (query plan recorded); `statusSQL` no-`content` test plus a prepare-observer test; mutation check performed |
| 6 | T0b "menu unchanged" untestable (mimo) | `LivePipeline` unit tests incl. equivalence with the old composition; `--dump-sessions` (T0c) lands first, before/after diff with live drift listed |
| n1 | `pollURL` single URL, WAL not in trigger (mimo, non-blocking) | Adopted: `pollURLs`, WAL/SHM folded into the poll signature |
| n2 | `SessionIngest.horizon` is `let` (mimo) | Adopted: `setHorizon(_:)`, checkpoints kept |
| n3 | `locatable` undefined (mimo) | Adopted: field dropped from `--query` |
| n4 | external `defaults write` vs running process (mimo) | Adopted: `CFPreferencesAppSynchronize` per refresh; acceptance uses a fresh process, running-app pickup checked by hand |
| n5 | T5 promises sections that do not exist (mimo) | The review tables are this section; Outcome section added below |
| n6 | new top-level `skills/` dir; install-only path (mimo) | Moved to `docs/skills/vibra-query/`; both paths documented |
| n7 | gate T0 separately (mimo) | Not adopted: one code gate on the full diff keeps rounds cheap for two free seats; T0 is instead a local checkpoint commit with its own unit tests and dump diff, and the code-review diff is against the recorded base so T0 is reviewed in full |

## Round-2 objections → changes

r2 verdicts: nemotron PLAN-APPROVED; mimo PLAN-REJECTED (1 blocking).

| # | Objection (who) | Change |
|---|---|---|
| 1 | T0c line format lacks `entrypoint`, which T1's real-data check reads (mimo) | T0c prints `entrypoint` and `unattended` |
| n1 | say where the dump baseline comes from (mimo) | Adopted: T0c runs `SessionStore`'s own refresh; `--all` = unbounded window and horizon |
| n2 | `finish` needs two live inputs (mimo) | Adopted: `claudeStatus:` and `live:` |
| n3 | record `active` and open-session counts (mimo) | Adopted in Provenance |
| n4 | `--history-stats` canary needs a Core formatter (mimo) | Adopted: `HistoryStats.format` in VibraCore |
| n5 | inject Calendar into `HistoryIndex` (mimo) | Adopted |
| n6 | poll-folding test; register adapter (mimo) | Adopted |
| n7 | assert full query plan (mimo) | Adopted |
| n8 | amend ROADMAP P2.2 "no real data" decision (mimo) | Adopted in T5 |
| n9 | write down empty-on-dev-machine expectation (mimo) | Adopted in T1 acceptance |

## Round-3 objections → changes

r3 verdicts: nemotron PLAN-APPROVED; mimo PLAN-REJECTED (2 blocking).

| # | Objection (who) | Change |
|---|---|---|
| 1 | "last N days" not applied per record for JSONL; two semantics (mimo) | Read bound = window + 1 day for all sources; per-record window filter in `HistoryIndex` for every adapter; window test added |
| 2 | stateless per-batch `questions(from:)` loses session-level facts past 2,000 lines; tests vacuous (mimo) | Stateful per-source `HistoryExtractor`; batch-boundary test with small `maxLinesPerRead`, positive and negative |
| — | (found by Claude while answering n5) Codex user prompts are not `event_msg`/`user_message` in the current Codex | Rule rewritten from observation: `response_item` user messages minus wrapper blocks; provenance recorded |
| n1 | `--all` vs per-refresh settings (mimo) | Adopted: `overrides` win; horizon wired through `SessionStore` |
| n2 | Hermes watch registration (mimo) | Adopted |
| n3 | "final sort" does not exist today (mimo) | Adopted: dropped |
| n4 | don't read agents without history (mimo) | Adopted: extractor `nil` ⇒ no reads; test |
| n5 | provenance for T4 rules (mimo) | Adopted, and it found the Codex error above |
| n6 | one predicate for "6" (mimo) | Adopted |
| n7 | `--history-stats` default; per-refresh `StateEngine` (mimo) | Adopted: default 7; engine rebuilt per refresh; `--probe` unchanged |

## Round-4 → r5 (non-blocking notes folded after unanimous r4 approval)

r4 verdicts: nemotron PLAN-APPROVED; mimo PLAN-APPROVED; claude PLAN-APPROVED.

| # | Note (who) | Change |
|---|---|---|
| n1 | ROADMAP amendment narrower than the practice recorded (mimo) | Widened in T5 |
| n2 | name README "Privacy and safety" (mimo) | Added to T5 |
| n3 | pin window day arithmetic to ReportBuilder (mimo) | Added to T4 |
| n4 | two Codex wrappers unobserved (mimo) | Labelled |
| n5 | older-Codex consequence (mimo) | Stated as accepted |
| n6 | garbage → default vs clamp (mimo) | Body now says default |
| n7 | bytes-read meaning (mimo) | Stated |

## Outcome

_(filled in after the code gate)_

## Votes

CLAUDE: PLAN-APPROVED (r4)
CLAUDE: PLAN-APPROVED (r5)
