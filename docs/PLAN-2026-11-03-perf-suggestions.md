# Plan: performance suggestions for Claude Code sessions (MVP)

Status: draft v0.8, 2026-11-03. Source proposal: `Vibra_Perf_Optimization_Proposal_2026-11-03.md`
(copied to `$SCRATCH/proposal.md`). This plan replaces the proposal's section 4.1 and its section 6
MVP row where they disagree. "Changes from the proposal" says why. Each review round's objections and
their resolutions are in the tables at the end.

## Run info

| Item | Value |
|---|---|
| Roster | standard. Planner `claude` (Claude Code, claude-opus-5-5). Coder and reviewer `coder-deepseek` (OpenCode, `deepseek/deepseek-flash`, footer "DeepSeek V4.1 Flash"). Third judge `reviewer-codex` (Codex CLI 0.166.0, GPT-6.1-Sol, reasoning high). |
| Gates | Plan gate and code gate are unanimous across all three seats. |
| Branch | `feat/perf-suggestions`, cut from `main` at `60a61b8`. |
| Review base | `BASE` = `c4b318c` (the plan gate record commit). |
| Scratch | `$SCRATCH`, a session scratch directory outside the repo (verdicts, ledger, probes). |
| Checkout | One shared working tree. Owners write disjoint files. Task 3 starts only after Task 2 is done, so no half-written file breaks another owner's build. Nothing under `tools/perf-oracle/` changes while a review round is open. |
| Data rule | The repo is public. Seats read the repo, `$SCRATCH` and synthetic fixtures only. They never read `~/.claude` or the frozen snapshot. The snapshot of real transcripts lives in a planner-only directory outside `$SCRATCH`. Seats see aggregate counts with no project names. |
| Data incident, round 1 | In round 1 the snapshot sat inside `$SCRATCH`, and `coder-deepseek` ran six read-only Python scripts over it. Its session export shows that every script printed aggregates only (file, record, model and marker counts, sizes). No message text, tool input or path reached the model. The snapshot was then moved out of `$SCRATCH`. `reviewer-codex` ran no command on it (checked in its rollout). |

## Decisions taken by the user (2026-11-03)

1. The feature gives performance suggestions about monitored agent sessions. It does not optimize Vibra itself.
2. MVP scope is D1 to D3, Claude Code only.
3. D6 (model mismatch) is deferred and is not planned for V2.
4. Suggestions appear as a Top 3 section inside the existing Usage Report (⌘U). There is no separate window.

## Evidence

All figures come from scripts in `$SCRATCH/probe/` or `tools/perf-oracle/`. They ran on a frozen
snapshot of this machine's `~/.claude/projects`, taken at `2026-11-03T21:55:32Z` (176 files, 463 MB,
files modified in the last 9 days). Outputs: `evidence-frozen.txt`, `calib-v05.txt`,
`d1-sensitivity.txt`, `cache-tiers.txt`, `drop-recovery.txt`. Sessions are keyed by file stem. No output
names a project. `calib-v05.txt` and `d1-sensitivity.txt` start with the blob hashes of the oracle files
and `dirty: False`, and were produced on the clean committed tree. `d1-sensitivity.txt` calls the
committed oracle's own `report()`.

The oracle tooling is committed to the branch under `tools/perf-oracle/`: `perf_oracle.py` (the
oracle), `oracle_selftest.py`, `compare.py` (the comparator), `compare_selftest.py` and
`make_synthetic_home.py` (a synthetic `VIBRA_HOME`). It reads synthetic data or a path given on the
command line, and holds no real data. Probe 3 checks that `git diff --quiet HEAD -- tools/perf-oracle`
holds and that the blobs equal these hashes:

```
0780d7e914959218fbd07509d96a52e1c1bfa332  tools/perf-oracle/perf_oracle.py
d57478bd2803133c0e36baecdb01a5f9491ad492  tools/perf-oracle/oracle_selftest.py
1b42b26c456921889c7eaadb3bf2a282c95d7328  tools/perf-oracle/compare.py
8040e20064c3f4713cc438ba48fc0b02b44ceb4c  tools/perf-oracle/compare_selftest.py
ef48fe56b3503f73f86c8de157c2f3c52e9ec05e  tools/perf-oracle/make_synthetic_home.py
```

`oracle_selftest.py` checks 32 synthetic cases with hand-computed results, including every
counterexample from rounds 1 to 4 and an end-to-end run of the oracle's entry point, pinned to
`TZ=America/Los_Angeles`, on a tree that crosses the 2026-11-01 DST change. `compare_selftest.py` checks 8
comparator cases, including its failure paths. Changing any of these files after this plan is approved
needs a new plan round. The tools run with `python3 -I -B`, so they leave no bytecode in the tree.

Scopes are stated per figure. "7-day files" means files modified in the 7 days before the snapshot.
"Whole snapshot" means all 176 files.

- **Duplicate response records** (7-day files, `evidence-frozen.txt`): 19,162 assistant records with
  usage, 9,373 distinct `message.id`s, 9,789 duplicates, all adjacent to the first record of their ID
  among assistant records with usage. 0 IDs appear in more than one file. Summing every record gives
  4,544,516,386 tokens. Keeping the last record per ID gives 2,137,062,638 (ratio 2.13). Both
  `Session.usage` and the Usage Report sum every record today. Whole snapshot: all 121 duplicate pairs
  whose usage differs differ only in `output_tokens`, and output never decreases.
- **File shape** (whole snapshot): 0 symlinks, 0 transcripts under a hidden directory, 0 lines that are
  not valid UTF-8, 0 files without a trailing newline.
- **Zero-usage records** (whole snapshot): 18, all with model `<synthetic>`, 12 in main-thread files.
- **Compaction** (whole snapshot, main-thread files, turns as defined below, `drop_recovery.py` and its
  output `drop-recovery.txt`): 23 `system/compact_boundary` markers have a following turn, and all 23
  coincide with a context drop. 0 markers have no drop, and 0 drops have no marker, a file's last turn
  included. An earlier 7-day probe (`compact_agreement.py`, which counted zero-usage records as turns)
  found 9 unmarked drops; those were the zero-usage `<synthetic>` records. All 23 markers drop to at
  most 0.361 of the previous context (that probe).
- **Subagents** (7-day files): 133 of 158 files are under a `subagents` directory. 0 `isSidechain`
  records sit in main-thread files.
- **Models** (whole snapshot): `claude-opus-5-5` 17,214 records, `claude-fable-5-1` 2,893,
  `claude-sonnet-5-5` 500, `claude-opus-4-8` 16, `<synthetic>` 18. `CostTable` has no rate for Fable.
  It prices every model whose name contains "opus" at one rate. Its rates were last verified on
  2026-09-19, and this run did not verify them again. Every dollar figure here inherits them.
- **Cache tiers** (whole snapshot, raw records, `cache-tiers.txt`): every usage carries a
  `cache_creation` object. 5-minute writes total 46,985,629 tokens and 1-hour writes 64,753,155. Both
  tiers are in use. `CostTable` has one cache-write rate, so every figure that includes cache writes is
  understated for 1-hour writes.
- **Calibration** (committed oracle, `now` pinned to the snapshot time, `calib-v05.txt`): Claude Code
  total in the window 1,931,896,094 tokens after folding. 17 sessions analyzed, 2 unpriced, 11 skipped as
  too small. D1 fired in 8 and was a lead in 7. D2 fired in 10 and was a lead in 4, every one dominated
  by `idleOver1h`. D3 fired in 1 and was a lead in 0. Both unpriced sessions matched a detector. No
  exposure exceeds 0.536 of its session's value. These numbers come from the data that chose the
  defaults. They are not an accuracy claim. D3 is expected to stay silent on this machine, because broad
  exploration here already runs in subagents. It has not been observed as a lead on real sessions.
- **D1 sensitivity** (`d1-sensitivity.txt`): a 100k floor with 20 turns above it gives 13 leads of 17. A
  200k floor with 50 turns gives 7. A 300k floor with 100 turns still gives 6. Long sessions here run
  above 200k for most turns, so D1 fires often. The report shows it once.

## Changes from the proposal

1. **Vibra double-counts Claude Code tokens today, and Task 1 fixes it first.** Claude Code writes one
   API response as several `assistant` records, one per content block, each repeating `message.id` and
   `usage`. The fix also changes the Usage Report: on the snapshot, Claude Code tokens drop by about half.
   Task 1 also fixes a second, separate defect it found on the way: the full-parse path
   (`discoverSessions`) reads only the first 2,000 lines of a transcript, for Claude Code and Codex.
2. **The proposal's D2 ratio uses the wrong denominator.** `cacheRead / (input + cacheRead)` leaves out
   `cacheCreation`, and `input_tokens` is near zero in Claude Code (50,939 of 2,137,062,638 tokens).
3. **The proposal's D1 and D3 thresholds fire on almost every session.** D1 and D3 are redefined and calibrated.
4. **Subagent transcripts are excluded from the detectors and still counted in the report.**
5. **One read serves the report and the suggestions.**
6. **Figures are estimated exposures, not savings.** D1 estimates what the prompt tokens above the floor
   cost. D2 estimates the write premium on context the previous turn held in cache. D3 is a conditional
   estimate whose assumptions are shown with it. All are at Vibra's `CostTable` rates, with 1-hour cache
   writes priced at its single write rate. None promises what an alternative would have cost, because
   the alternative (`/compact`, a subagent) has its own cost that the transcript cannot show.
7. **Thresholds are tunable through `defaults write`. The MVP has no Settings window controls.**

## Data shape

```swift
// Report/UsageSample.swift: three new fields, all defaulted.
public struct UsageSample: Sendable, Equatable {
    public let timestamp: Date?
    public let model: String?
    public let usage: TokenUsage
    public let toolNames: [String]   // `tool_use.name` values only; never `input`, never results
    public let project: String?      // last non-empty path component of `cwd`, cut at the adapter; nil for "/" or no cwd
    public let isSidechain: Bool     // any record of the response had `isSidechain: true`
}

// Report/UsageSampler.swift: how an adapter turns one source's records into additive samples.
public protocol UsageSampler: Sendable {
    var isSubagent: Bool { get }                            // the source is a subagent transcript
    mutating func add(_ lines: [String]) -> [UsageSample]   // samples that are final
    mutating func finish() -> [UsageSample]                 // at end of file
}
// AgentAdapter.usageSamples(from:) is deleted, and AgentAdapter gains
// `func makeUsageSampler(for source: URL) -> any UsageSampler`, so every old caller fails to compile
// until migrated. Codex returns a stateless sampler around its existing per-record parse. Claude Code
// returns `ClaudeUsageSampler`. OpenCode, Hermes, Cursor and VS Code use the default, which returns no
// samples (OpenCode and Hermes keep `reportsUndatedTotals`). `ReportIngest` calls only
// `makeUsageSampler(for:)`.
// The Codex sampler is stateful too: it keeps the model it read from `session_meta` (the only record
// `CodexCheckpoint` reads a model from) across `add` calls. Today's per-batch parse forgets it, so
// Codex tokens after line 2,000 of a rollout are reported as unpriced. Task 1 fixes that.
```

`ClaudeUsageSampler` holds the one fold for "one response, several records". It lives in
`ClaudeCodeAdapter.swift`. Its rules:

- `isSubagent` is true when a path component below the adapter's projects root is named `subagents`.
  It is false for the single-file test entry point, which has no root.
- Only `assistant` records with a `message.usage` object become records for the fold. Other records
  never make the pending response final early and never clear it.
- A record whose non-nil `message.id` equals the pending response's ID merges into it. The merge keeps
  the pending timestamp, or takes the new one when the pending one is nil. It takes the new usage, takes
  the new model and project when they are non-nil, appends the new tool names, and keeps `isSidechain`
  true once any record set it.
- A record with another ID makes the pending response final and becomes pending itself.
- A record with no ID makes the pending response final, and is final itself. Records with no ID never merge.
- `add(_ lines:)` parses each line and calls `add(record:timestamp:detail:)`. That second entry point is
  the fold. `detail: false` skips tool names and project, and is what the live path uses. There is one
  fold, and the only difference between the callers is whether those two fields are filled.

`ClaudeCheckpoint` (live polling) holds a `ClaudeUsageSampler` and `committed: TokenUsage`. It adds the
usage of every sample the sampler makes final to `committed`. `Session.usage` is `committed` plus the
pending usage. The checkpoint persists between polls, so a response split across two reads or two polls
still merges. `ClaudeCheckpoint.fold` already parses each record and its timestamp, and hands them to
`add(record:timestamp:detail: false)`. So the live path parses each line once, as today.

The full-parse path (`discoverSessions`, for Claude Code and Codex) stops calling `readLines`, which
returns only the first 2,000 lines (`maxLinesPerRead`). A helper reads batch after batch to the end of
the file and folds each batch, so memory stays per batch. `readLines` is then unused and is deleted.

```swift
// Report/ReportWindow.swift: the window, the file cutoff and the calendar of the report and the analyzer.
public struct ReportWindow: Sendable, Equatable {
    public let days: Int
    public let calendar: Calendar
    public let fileCutoff: Date   // now - (days + 1) x 86,400 s; files modified earlier are not read
    public let start: Date        // calendar start of day, days - 1 days before today
    public let today: Date        // calendar start of today
    public let now: Date
    public init(now: Date, days: Int, calendar: Calendar)
    public func day(of date: Date) -> Date
    public func contains(_ date: Date) -> Bool   // day(of: date) in start...today
}
// ReportBuilder.build(samplesByAgent:window:) replaces build(samplesByAgent:now:windowDays:).
// ReportBuilder.calendar is deleted; it buckets with window.day(of:).

// Report/ReportIngest.swift
public struct SourceSamples: Sendable {
    public let url: URL
    public let isSubagent: Bool          // sampler.isSubagent
    public let samples: [UsageSample]    // final samples; empty when the file holds no usage
}
public struct ReadStats: Sendable, Equatable, Codable {
    public let bytes: Int                              // bytes read, exact
    public let files: Int                              // JSONL files read, counted once each
}
public struct ReportInput: Sendable {
    public let sources: [AgentKind: [SourceSamples]]   // one entry per JSONL file read, empty or not
    public let undated: [AgentKind: [UsageSample]]     // OpenCode/Hermes session totals, as today
    public let read: ReadStats
    public var samplesByAgent: [AgentKind: [UsageSample]] { get }   // sources plus undated
}
// ReportIngest.collect(window:) -> ReportInput replaces collectSamples(now:), which is deleted.
```

Memory: `ReportInput` holds every final sample of the window until the report is built, as today's
`[AgentKind: [UsageSample]]` does. Folding roughly halves the sample count. Each sample now also holds
its tool names and a project string. Probe 4 measures peak resident memory against the baseline.

```swift
// Perf/Suggestion.swift: typed evidence only. Every string the user reads is built in ReportText.
public struct Suggestion: Sendable, Equatable, Codable {
    public enum RewriteCause: String, Sendable, Codable { case modelSwitch, idleOver1h, idleOver5m, other }
    public enum Finding: Sendable, Equatable, Codable {
        case contextCarry(segments: Int, turnsAboveFloor: Int, peakContext: Int, floorTokens: Int)
        case cacheRewrite(events: Int, rewrittenTokens: Int, dominantCause: RewriteCause)
        case explorationBurst(bursts: Int, burstTurns: Int)
    }
    public let sessionID: String        // transcript file name without extension
    public let project: String          // first non-nil `project` among the session's turns, else ""
    public let startedAt: Date?         // timestamp of the session's first in-window turn (not in the oracle; unit-tested)
    public let turns: Int               // in-window turns
    public let finding: Finding
    public let exposureUSD: Double?     // nil when the session is unpriced
    public let sessionValueUSD: Double? // nil when the session is unpriced
    public let isLead: Bool
}
public struct PerfReport: Sendable, Equatable, Codable {
    public let thresholds: PerfThresholds   // the values the analyzer used
    public let analyzedSessions: Int
    public let unpricedSessions: Int
    public let skippedSmallSessions: Int
    public let suggestions: [Suggestion]    // every fired suggestion, ordered by Finding case name, then sessionID
}
```

- `PerfAnalyzer.report(claudeSources: [SourceSamples], window: ReportWindow, thresholds: PerfThresholds)
  -> PerfReport` is pure. Callers pass `ReportInput.sources[.claudeCode]` only.
- `PerfThresholds` (in `Perf/PerfThresholds.swift`) has seven stored properties named as in the table
  below without the `perf.` prefix (`minTurns`, `d1MinTurnsAboveFloor`, `d1CarryFloorTokens`,
  `d2MinRewriteTokens`, `d3MinBurstTurns`, `leadMinUSD`, `leadMinShare`). It is `Codable` with exactly
  those bare names as keys, which are the oracle's keys. The `perf.` prefix belongs only to the
  `defaults write` keys. Task 1 writes the type, its defaults and its internal memberwise initializer.
  Task 2 adds `load(from: SettingsStore)`, which reads the keys through one free internal function,
  `clampedSetting(_ value: Any?, default: Double, range: ClosedRange<Double>) -> Double`, extracted from
  `VibraSettings` and built on its existing `numeric` rule. Integer keys are clamped, then rounded to the
  nearest integer. `VibraSettings.Limit` stays as it is, because `SettingsWindowController` uses it.
  `ReportWindowController` and `--report` call `load` when the report opens. The memberwise initializer
  is internal and used by tests.
- `ReportText` in `Report/ReportText.swift` is the one text renderer:
  `render(usage: UsageReport, perf: PerfReport, read: ReadStats, seconds: Double) -> String` and
  `evidenceLine(for: Suggestion) -> String`. The window and `--report` both call it. Its last line
  keeps today's read line with the file count added: "Read X MB from N files in Ys."
- `ReportJSON.encode(usage: UsageReport, window: ReportWindow, read: ReadStats, perf: PerfReport?) -> Data`
  in `Report/ReportJSON.swift` builds the `--report --json` object, so tests encode exactly what the CLI
  prints. `main.swift` only writes its output. Dates encode as ISO 8601. `VIBRA_NOW` (ISO 8601) pins
  `now` for `--report`. Neither prints message text. The schema:

  ```json
  {
    "schema": 1,
    "window": {"days": 7, "start": "<ISO 8601>", "now": "<ISO 8601>"},
    "read": {"bytes": 0, "files": 0},
    "agents": [{"agent": "claudeCode",
                "usage": {"input": 0, "output": 0, "cacheCreation": 0, "cacheRead": 0},
                "estimatedValue": 0.0, "unpricedTokens": 0}],
    "perf": "<PerfReport, encoded by its synthesized Codable conformance, or null>"
  }
  ```

  Task 1 writes `schema`, `window`, `read` and `agents`, with `perf` null. Both callers (the window and
  `--report`) pass `ReportInput.read` from the same ingest they report on, so `read` holds its exact
  values. Task 3 passes the `PerfReport`. A
  `Finding` encodes as
  `{"contextCarry": {"segments": 1, "turnsAboveFloor": 60, "peakContext": 250000, "floorTokens": 200000}}`.

## Detector rules

**Terms.** A *transcript* is a Claude Code source with `isSubagent == false`. A *turn* is a final sample
with `isSidechain == false` and `input + cacheCreation + cacheRead > 0`. That drops the zero-usage
`<synthetic>` records, output-only records and inline sidechain records. Those records still count in
the Usage Report's totals. Context `c = input + cacheCreation + cacheRead`. A turn is *in window* when
`ReportWindow.contains` its timestamp. Detection runs over every turn of the transcript. Counts and
dollar figures use in-window turns only. A session is analyzed when it has at least `minTurns` in-window
turns. Otherwise it counts as skipped.

**Segments.** A turn starts a new segment when the previous turn's context is at least 50,000 and its
own context is below half of it. On the snapshot this matches the 23 compaction markers exactly, with 0
extra drops and 0 missed markers (see Evidence). It is still a heuristic. A compaction that keeps more
than half the context would be missed, and its rewrite could then count as a D2 event.

**Pricing.** Each turn is priced at its own model's `CostTable` rate. Rates are dollars per million
tokens, so every product below is divided by 1,000,000. A session is *priced* when every in-window turn
has a rate. An unpriced session still runs the detectors, but `exposureUSD` and `sessionValueUSD` are
nil, and it is never a lead. `sessionValueUSD` is the sum of the in-window turns' API-equivalent value.
This all-or-nothing rule is deliberate: a partial figure would compare a priced exposure with a partly
priced session. On the snapshot it affects 2 of 17 analyzed sessions, and both are shown (see "What the
report shows").

| # | Fires when | Finding fields | Exposure (dollars, estimated) |
|---|---|---|---|
| D1 context carry | A segment has at least `d1MinTurnsAboveFloor` in-window turns with `c > d1CarryFloorTokens`. One suggestion per session covers every qualifying segment. | `segments`: qualifying segments. `turnsAboveFloor`: their in-window turns with `c > floor`. `peakContext`: max `c` over in-window turns of qualifying segments. `floorTokens`: the floor used. | Over those turns, the prompt tokens at positions `floor...c`, each priced by the band it falls in. The API lays a prompt out as the cache-read prefix, then the new cache writes, then uncached input, so the overlap with each band is priced at that band's rate. This estimates what the context above the floor cost, at Vibra's table rates. |
| D2 cache rewrite | A turn `i` in window, in the same segment as turn `i - 1`, with `held = cacheRead[i-1] + cacheCreation[i-1]` (what turn `i - 1` left in cache), `base = min(held, c[i])`, `missed = min(cacheCreation[i], max(0, base - cacheRead[i]))`, `missed >= d2MinRewriteTokens` and `missed >= 0.5 x base`. Each such turn is one event. | `events`. `rewrittenTokens`: sum of `missed`. `dominantCause`: the cause with the most rewritten tokens, ties broken by the fixed order modelSwitch, idleOver1h, idleOver5m, other. | Over events: `missed x (cacheCreationRate - cacheReadRate)` at turn `i`'s rate. This is the inferred write premium on context that the previous turn had in cache. Token identity is not proven by the usage fields, so the label says "inferred". |
| D3 exploration burst | A burst is a maximal run of at least `d3MinBurstTurns` consecutive turns in one segment, `first...last`, each with at least one tool call and every tool name in {Read, Grep, Glob}, with at least one burst turn in window. | `bursts`. `burstTurns`: in-window burst turns. | Per burst: `top = last + 1` when that turn exists in the same segment, else `last`. `growth = max(0, c[top] - c[first])`. Walking `j` from `top + 1` to the end of the segment, `still = max(0, min(still, c[j] - c[first]))`, starting from `growth`. For each `j >= last + 2` in window, `carried[j] += still`. Exposure is the sum of `carried[j] x cacheReadRate` at turn `j`'s rate. The running minimum alone keeps exposure at or below session value (tested). Turn `last + 1` is skipped. Only the last burst turn's results are a write there, so skipping the whole turn is a conservative choice. Growth may be measured on turns outside the window. Only in-window turns are priced. It assumes the growth came from the burst's tool results, and that once context falls back toward `c[first]`, that growth is gone for good. |

**D2 cause.** It is a correlation, never a proven cause. Models are compared as strings, a missing model
counting as a value. Precedence: `modelSwitch` when turn `i`'s model differs from turn `i - 1`'s, else
`idleOver1h` when the gap between the two turns' timestamps exceeds 3,600 s, else `idleOver5m` above
300 s, else `other`. So a missing timestamp gives `other` only when the models match. The timestamp of a
folded turn is that of its first record, which Claude Code writes when the first content block is done.
So the gap only approximates the interval the cache TTL counts from (inferred, not measured). The error
is the first block's generation time.

**Lead.** A suggestion is a lead when the session is priced, `sessionValueUSD > 0`, `exposureUSD > 0`,
`exposureUSD >= leadMinUSD`, and `exposureUSD >= leadMinShare x sessionValueUSD`.

**What the report shows.**

1. One line per detector that has at least one lead, at most 3 lines, ordered by the exposure of each
   line's evidence suggestion, largest first, ties broken by `Finding` case name. That ordering is for
   presentation only. Exposures are never summed across detectors, because D1 and D3 can price the same
   carried tokens. Each line gives the action, then `evidenceLine` for that detector's lead with the
   largest exposure, plus "also in N other sessions" when other sessions have a lead from the same
   detector (N counts them).
2. When no detector has a lead: "No priced pattern above the thresholds in N analyzed sessions", or,
   when no session was analyzed, "No Claude Code session in the last <days> days had enough turns to
   analyze."
3. Whenever an unpriced session matched a detector, whether or not there are leads: "K sessions use a
   model with no published rate. M of them matched a pattern, shown without a dollar figure." Then one
   line per detector matched in an unpriced session, in the fixed order D1, D2, D3: the action and the
   evidence line of the matching unpriced session with the most in-window turns (ties broken by
   `sessionID`), with "no published rate" in place of the figure, plus "also in N other unpriced
   sessions" when there are more. For D2 the action follows that session's dominant cause.
4. The block ends with "Estimated API-equivalent value at Vibra's table rates (last verified
   2026-09-19); 1-hour cache writes use the single write rate. Not a bill."

Evidence lines. `<date>` is `startedAt` as a local date ("Oct 30"). A project of `""` renders as
"unknown project".

- D1: "<project>, <date>, T turns above <floor>: the context above <floor> cost about $X." T is
  `turnsAboveFloor` and `<floor>` is `floorTokens` (for example "200k").
- D2 by dominant cause:
  - `modelSwitch`: "<project>, <date>: E times, context already in cache was written again, the largest part after a model switch (inferred). Write premium about $X."
  - `idleOver1h`: "... the largest part after a gap of over an hour (inferred) ..."
  - `idleOver5m`: "... the largest part after a gap of over 5 minutes (inferred) ..."
  - `other`: "... the largest part with no model switch or long gap (inferred) ..."
- D3: "<project>, <date>: B search bursts. If what they added stayed in context, re-sending it cost about $X."

**Action text** (owned by `ReportText`):

- D1: "Run /compact inside long tasks and /clear between tasks. Split unrelated work into separate sessions."
- D2 `modelSwitch`: "Pick the model before starting. A switch mid-session writes the cache again."
- D2 `idleOver1h` / `idleOver5m`: "Before a long break, consider /compact, or /clear if the task is done. After the cache expires, much of the context is written to cache again."
- D2 `other`: "Large parts of an already-cached prompt were written again. Check /context for tools or files that change between turns."
- D3: "@-mention the files you mean, or hand broad searches to a subagent so only its conclusion enters this session."

**Defaults and `defaults write` keys**, clamped like `VibraSettings`:

| Key | Default | Range |
|---|---|---|
| `perf.minTurns` | 10 | 3...1000 |
| `perf.d1MinTurnsAboveFloor` | 50 | 5...5000 |
| `perf.d1CarryFloorTokens` | 200000 | 20000...2000000 |
| `perf.d2MinRewriteTokens` | 30000 | 5000...2000000 |
| `perf.d3MinBurstTurns` | 3 | 2...50 |
| `perf.leadMinUSD` | 0.25 | 0...100 |
| `perf.leadMinShare` | 0.10 | 0...1 |

Fixed in code: the compaction constants (50,000 and 0.5) and D2's 0.5 share. The first two describe the
format. The third keeps D2 about rewrites rather than partial misses.

## Tasks

| # | Owner | Depends on | Files (literal; touch nothing else) | Acceptance |
|---|---|---|---|---|
| 1 | planner | none | `Sources/VibraCore/Report/UsageSample.swift`, `Sources/VibraCore/Report/UsageSampler.swift` (new), `Sources/VibraCore/Report/ReportWindow.swift` (new), `Sources/VibraCore/Report/ReportJSON.swift` (new), `Sources/VibraCore/Report/ReportIngest.swift`, `Sources/VibraCore/Report/ReportBuilder.swift`, `Sources/VibraCore/Adapters/AgentAdapter.swift`, `Sources/VibraCore/Adapters/ClaudeCodeAdapter.swift`, `Sources/VibraCore/Adapters/CodexAdapter.swift`, `Sources/VibraCore/Adapters/OpenCodeAdapter.swift`, `Sources/VibraCore/Perf/Suggestion.swift` (new), `Sources/VibraCore/Perf/PerfThresholds.swift` (new: the type, defaults, `Codable`, memberwise initializer), `Sources/VibraApp/ReportWindowController.swift`, `Sources/VibraApp/main.swift`, `Tests/VibraCoreTests/ClaudeUsageSamplerTests.swift` (new), `Tests/VibraCoreTests/UsageSampleTests.swift`, `Tests/VibraCoreTests/ReportBuilderTests.swift`, `Tests/VibraCoreTests/QueryAndHistoryTests.swift` (the `ReportBuilder.build` call site only) | `make test` green, every existing test included or migrated. `usageSamples(from:)` no longer exists. New tests, each run against both `Session.usage` (through `SessionIngest`) and `ReportIngest` output: three records with one ID and growing output give the last usage; the same pair split across batches (`maxLinesPerRead: 1`) still merges; the same pair split across two `SessionIngest.refresh()` calls, the second record appended in between, still merges; `recordsWithoutIDNeverMerge` (two adjacent records with no ID stay two); a user record between two records of one ID does not split them; a first record with no timestamp takes the second's; a zero-usage record contributes 0; an inline sidechain record counts in totals and has `isSidechain`; a property test over seeded random batch splits gives equal live and report totals. A 2,500-line transcript gives the same usage through `discoverSessions` as through `ReportIngest`, for Claude Code and for Codex. For the 2,500-line Codex rollout, a sample after line 2,000 carries the model from its `session_meta`, and the report's Codex line has `unpricedTokens == 0` and the `estimatedValue` written as arithmetic in the test. A `cwd` of `/a/SECRET/b/proj` yields `project == "proj"` and no sample field contains `SECRET`; a `cwd` of `/` yields nil. `isSubagent` is true for `<root>/<project>/<session>/subagents/<agent>.jsonl`, false for `<root>/<project>/<session>.jsonl` and for the single-file entry point, and a `subagents` component above `<root>` does not count. `ReportWindow` tests cover the DST change on 2026-11-01 in `America/Los_Angeles`. `ReportJSON` tests check the schema keys, ISO 8601 dates, exact `read.bytes` and `read.files` for a fixture tree (from `ReportIngest.collect` through `ReportJSON.encode`), and that the encoded `PerfThresholds` keys are exactly the oracle's seven bare names. `Vibra --report --json` on the synthetic home (probe 3a, any seat) and on the snapshot (probe 3b, planner only) passes `compare.py --total-only` against the committed oracle. |
| 2 | deepseek | 1 | `Sources/VibraCore/Perf/PerfThresholds.swift` (add `load(from:)` to the Task 1 type), `Sources/VibraCore/Perf/PerfAnalyzer.swift` (new), `Sources/VibraCore/Settings/VibraSettings.swift` (extract `clampedSetting` only; `Limit` unchanged), `Tests/VibraCoreTests/PerfAnalyzerTests.swift` (new) | `make test` green, existing `VibraSettings` tests included. Synthetic samples only: Task 2 never reads the snapshot. It may run the committed oracle and `make_synthetic_home.py` on synthetic data. For each detector, a positive case whose expected values are written in the test as arithmetic from the rules above. Required cases, mirroring `oracle_selftest.py`: new content is not D2; no cache writes means no D2; a first cache fill after uncached turns is not D2; an expired cache after 3 h is one `idleOver1h` event with exposure `100000 x (3.75 - 0.30) / 1e6`; a D2 turn with `input > 0` uses the `cacheCreation` cap; an unpriced D2 picks its dominant cause by tokens then by the fixed order; a missing timestamp with matching models gives `other`; `compactionIsNotARewrite` (12 turns at 229k, then a turn with `cacheCreation = 60000` and no reads, then turns at 60k: no D2); a burst with no later turns has exposure 0; a 3-turn Read burst followed by 7 turns at +90k gives `90000 x 6 x 0.30 / 1e6`; growth that drops before a later burst is not charged again (`7 x 50000 x 0.30 / 1e6`); an earlier burst's growth still in context is charged (`(5 x 20000 + 7 x 70000) x 0.30 / 1e6`); D3 exposure never exceeds session value; an output-only record is not a turn; an inline sidechain record is not a turn and does not split a segment; `burstTurns` counts in-window turns only; D1 with 60 turns at 250k gives `60 x 50000 x 0.30 / 1e6` and is a lead; D1 over a 150k read prefix, 60k writes and 40k input gives `60 x (10000 x 3.75 + 40000 x 3.0) / 1e6`; `leadNeedsShareOfSessionValue` (a priced D1 of $0.75 in a $26.55 session is not a lead); a priced suggestion with exposure 0 is never a lead, even with `leadMinUSD` 0; one unpriced in-window turn gives nil figures and no lead, while an unpriced turn outside the window does not; a zero-usage `<synthetic>` sample is neither a boundary nor a model switch; `project` comes from turns; `startedAt` is the first in-window turn's timestamp; repeated Bash is not D3; a session below `minTurns` counts as skipped; a subagent source is neither analyzed nor counted as skipped (counts asserted); a source whose samples are all sidechain samples has no turns and counts as skipped (counts asserted). A mixed-model D3 case prices later turns at their own rates. A threshold-loading test covers clamping, rounding of integer keys and a non-numeric value. |
| 3 | planner | 1, 2 | `Sources/VibraCore/Report/ReportText.swift` (new), `Sources/VibraCore/Report/ReportJSON.swift`, `Sources/VibraApp/ReportWindowController.swift`, `Sources/VibraApp/main.swift`, `Tests/VibraCoreTests/PerfPrivacyTests.swift` (new), `Tests/VibraCoreTests/ReportTextTests.swift` (new), `Makefile`, `tools/gate/mutate.sh` (new), `tools/gate/perf-bench.sh` (new), `tools/gate/baseline-vibra-now.patch` (new) | `make test` green. The Makefile checks each canary by its exact test name, so `canaryTokenNeverLeaks` and the new `perfPrivacySentinelsNeverLeak` each fail the run when absent. The canary fixture is raw JSONL lines with one sentinel each in message text, a thinking block, `tool_use.input`, a `tool_result` content block, `wireToolInputs`, and a parent component of `cwd`. Run with in-range small thresholds (`minTurns` 3, `d1MinTurnsAboveFloor` 5, `d1CarryFloorTokens` 20000, `d3MinBurstTurns` 2), it must produce a lead for each of D1, D2 and D3 (asserted) before asserting that no sentinel appears in any `UsageSample` field, in `ReportJSON.encode` output, in `ReportText.render` output (both called with the fixture's `ReportInput.read`), or in `evidenceLine(for:)` for every fired suggestion, and that `toolNames` equals the exact `name` values. Task 3 deletes `ReportWindowController.format` and the `--report` print block. `ReportText` tests cover the read line ("Read X MB from N files in Ys.") from a given `ReadStats`, both empty states, the unpriced block alone and alongside leads (including which unpriced session supplies each line and "also in N other unpriced sessions"), the one-line-per-detector rule with its ordering and tie-break, "also in N other sessions", the local date, "unknown project", and a D1 line with a non-default floor. The three `tools/gate/` files are reviewed in the code gate and pinned by its diff hash. |
| 4 | planner | 3 | `docs/features.md`, `docs/privacy.md`, `docs/ROADMAP.md`, `CHANGELOG.md`, this plan file | Docs say what each detector measures; that figures are estimated exposures at Vibra's table rates (last verified 2026-09-19), with 1-hour cache writes at the single write rate, and not savings; the `defaults write` keys; `--report --json` with its `schema` field and `VIBRA_NOW`; that `tool_use.name`, `message.id`, `isSidechain` and the last component of `cwd` are now read for the report (never tool inputs or results); that Claude Code totals drop by about half because of the Task 1 fix; that Fable has no published rate in `CostTable`; and that D3 has not yet been observed as a lead on real sessions. Before the merge, the plan's Run info keeps no local paths. |

Task 1 is the shared foundation. It is built and committed alone before Task 2 is dispatched. Task 3
starts after Task 2 is done.

## Probes at the code gate (saved to `$SCRATCH/probes-rN.txt`)

1. `make test`: the test count, `OK: tests executed`, and both canary names.
2. `make bench`: `PASS: an unchanged refresh reads zero bytes`.
3. Oracle comparison, every command under `TZ=America/Los_Angeles` and `python3 -I -B`. First
   `git diff --quiet HEAD -- tools/perf-oracle` must hold, `git hash-object` of each file must equal the
   blob hashes in Evidence, and both self-tests must pass.
   - 3a, any seat may run it: `make_synthetic_home.py <dir> --now 2026-11-03T21:00:00Z` writes a
     synthetic `VIBRA_HOME`. `Vibra --report --json` and `perf_oracle.py` run on it with that `now`, and
     `compare.py` compares them. The synthetic home fires every D2 cause, a D1 lead, a D3 lead and an
     unpriced D1. It also holds an inline sidechain record, a line that is not valid UTF-8, an
     unterminated last line and the `compactionIsNotARewrite` shape.
   - 3b, planner only: the same on the frozen snapshot, with `now` at its time. Both raw JSON files stay
     in the planner-only directory.
   - `compare.py` compares the thresholds, the Claude Code total and the three session counts exactly,
     and every fired suggestion by (`sessionID`, detector): finding fields, `turns`, `isLead` and
     `project` exactly, dollar figures strictly within half a cent. It rejects duplicate keys. It prints
     counts and mismatches by file stem only, and withholds project values.
4. `tools/gate/perf-bench.sh`. The baseline is a throwaway worktree of `60a61b8` with
   `tools/gate/baseline-vibra-now.patch` applied. The patch touches two files and adds two things:
   `Sources/VibraCore/Report/ReportIngest.swift` counts the files it reads, and
   `Sources/VibraApp/main.swift` honours `VIBRA_NOW` in `--report` and prints a final line
   `read-exact bytes=<n> files=<n>`. The timed runs are `--report` on both sides, so both render text. The
   branch's exact counts come from one extra, untimed `--report --json` run per side check
   (`read.bytes`, `read.files`). Baseline and
   branch run 3 times each, interleaved, on the same snapshot copy and `VIBRA_NOW`. It records `--report`
   wall time, bytes read and peak resident memory (`/usr/bin/time -l`), and `make bench`'s cold refresh
   time, with min, median and max. The comparison counts only when both sides report the same exact bytes
   read and the same number of files. It fails when the branch median exceeds the baseline's by more than 15% in time, or by more
   than 50 MB in peak memory.
5. `tools/gate/mutate.sh`, in a throwaway `git worktree`, never in the shared checkout. It applies each
   mutation, runs `make test`, and checks that the named test fails:
   - remove the lead-share comparison: `leadNeedsShareOfSessionValue`;
   - remove the segment check in D2: `compactionIsNotARewrite`;
   - let records with no ID merge in `ClaudeUsageSampler`: `recordsWithoutIDNeverMerge`;
   - copy `tool_use.input` into `toolNames`: `perfPrivacySentinelsNeverLeak`.

## Not doing

- Codex, OpenCode, Hermes, Cursor and VS Code detectors (V2). D4 to D8 (V2). D6 (deferred).
- A separate Performance window, `--query --perf`, and Settings window controls for thresholds.
- Adding a Fable rate or a 1-hour cache-write rate to `CostTable`, or re-verifying its rates. No
  published rate was verified in this run.
- Reading tool inputs, tool results, message text or file contents. No network. No hooks or plugins.
- Changing `Session` fields. Task 1 changes how `usage` is summed, not its shape.

## Round-1 objections → changes

Seats: `codex` (C1 to C5), `deepseek` (D1 to D4). Planner's own review via `pstack:interrogate`
(Reviewer A opus @high, B fable @high, C sonnet @medium), labelled P-A, P-B, P-C. Those findings inform
the planner's vote only.

| Objection (who) | Change |
|---|---|
| D2 counts new content as a rewrite (C1, P-A2) | D2 now measures `missed = min(c[i-1], c[i]) - cacheRead[i]`. Codex's case gives `missed = 0`, and it is a Task 2 negative. |
| Compaction exclusion is a heuristic; causes are correlations (C1) | The Segments paragraph labels it a heuristic, gives the measured 23 of 23 agreement and the 9 unmarked drops, and states the failure case. Causes are worded as correlations. |
| D1 and D3 figures are not savings; units; per-turn rates (C2) | Figures are now exposures, defined by what was paid, with "at least" stated for D1. Every rate is per million, divided by 1,000,000. Every term uses its own turn's rate. A mixed-model D3 test is in Task 2. |
| `sessionValueUSD` and unpriced policy undefined; false empty state (C3, D2, P-A4, P-B2) | One rule: a session is priced only when every in-window turn has a rate. Otherwise its figures are nil and it never leads. Leads need `sessionValueUSD > 0`. Three empty states, including unpriced sessions. Tests for an unpriced in-window turn and an unpriced out-of-window turn. |
| Oracle comparisons cannot run; oracle disagrees with the rules (C4, D1, P-A1, P-B1) | Added `--report --json` with exact integers and `VIBRA_NOW`. Rewrote the oracle (`perf_oracle.py`): UTC parsing, the `ReportBuilder` window per turn, one row per (session, detector) keyed by file stem, report total including subagents. `compare.py` defines the key and the tolerance and compares all fired suggestions. Only the planner runs it. |
| Canary can pass vacuously; misses tool results; not enforced by `make test` (C5, D3, P-C2, P-A8) | The canary moved to Task 3, where it covers the adapter, the analyzer and the renderer. It must fire D1, D2 and D3 first. Sentinels sit in text, thinking, tool input, tool result, `wireToolInputs` (a real top-level field, measured) and `cwd`. The Makefile enforces it by name. The grep probe is replaced by `mutate.sh`. |
| Live fold undefined for nil IDs and non-assistant records; collapsed `model`/`cwd` undefined (D4, P-C6, P-B3) | `ResponseFold` rules are written once and used by both paths. Each case is a Task 1 test. |
| The dedup rule is implemented twice (P-A6, P-B3, P-C6) | One `ResponseFold`, used by `ClaudeCheckpoint` and `ReportIngest`. `collapsingRepeatedResponses` is dropped. |
| Collapse after a whole file is accumulated breaks the memory design (P-C7) | `ReportIngest` folds per batch and holds one pending sample. |
| Cross-file duplicate IDs not measured (P-A5, P-B12, P-C1) | Measured: 0 of 9,373 IDs appear in more than one file. Folding stays per file. |
| "Last record is final" rests on 3 examples (P-A5) | Measured over all 121 differing pairs: only `output_tokens` differs, never decreasing. |
| Zero-usage `<synthetic>` records break segments and causes (P-A3, P-B4) | Measured 18 (12 main-thread). Turns require `c > 0`. A Task 2 negative covers it. |
| Window semantics undefined (P-B5, P-C5, D1) | Detection runs over the whole transcript. Counts and dollars use in-window turns. One `ReportWindow` is shared by the builder and the analyzer. |
| D1's trigger and estimate measure different things (P-A13, P-B7) | D1 is now gated on turns above the floor, the same quantity it prices. Defaults recalibrated (`d1-sensitivity.txt`). |
| D3 cannot surface (P-A13, P-B6, P-C9) | Kept, because the user chose D1 to D3. The plan states that D3 is expected to stay silent on this machine (1 fired, 0 leads), so a silent oracle run is not read as a failure. |
| Top 3 repeats one action and implies additive figures (P-A12, P-C4) | One line per detector, worst lead as evidence, "also in N other sessions". Figures are never summed. |
| Strings inside `Suggestion`; unused contract fields (P-A11, P-B10, P-B11) | `Suggestion` carries a typed `Finding`. `ReportText` owns every string. `agent`, `severity`, `firstAt`, `lastAt` and `metric` were removed. |
| Duplicate renderers (P-A10, P-B9) | One `ReportText.render`, used by the window and `--report`. Both old formatters are deleted. |
| `PerfThresholds` would copy the clamping helper (P-A9, P-B8, P-C10) | Task 2 extracts one reader from `VibraSettings` and reuses it. |
| Task 3 written during Task 2 breaks the shared build (P-A7) | Task 3 starts after Task 2 is done. |
| Subagent filter decided by path inside the analyzer (P-C8) | `isSubagent` is set once at ingest on `SourceSamples`. |
| D2 idle figures are not avoidable (P-C3) | The figures are exposures, not savings. The idle action names `/compact` and `/clear`. The plan does not claim the rewrite was avoidable. |
| Gap includes generation time (P-A14) | The gap is start to start, which is the interval the cache TTL counts from. Folding keeps the first timestamp. |
| Seats ran the oracle on real data (D1f) | The snapshot moved to a planner-only directory. Only the planner runs the oracle. See the data incident in Run info. |
| No held-out validity measure (P-C9) | Not adopted. Without hand labels from the user, a held-out split on one machine's 17 sessions measures the same thing again. The plan labels the numbers as development numbers. |
| 1-hour cache tier priced at one write rate (P-C10, D note) | Documented in Task 4. It is out of the MVP. |

## Round-2 objections → changes

| Objection (who) | Change |
|---|---|
| D2 never checks `cacheCreation`; a session with no cache writes fires (codex 1) | `missed` is capped by `cacheCreation[i]`. The no-cache-write case is an oracle self-test and a Task 2 case. |
| D2 rule text lacks the cap the oracle has (deepseek 2) | The table now states `missed = min(cacheCreation[i], ...)`. The `input > 0` case is a Task 2 case. |
| D2 action is unconditional (codex 1) | The idle action says "consider" and "much of the context". The evidence line states the gap as a correlation. |
| D3 assumes every increment persists; exposure can exceed session value (codex 2) | D3 is now per burst: net growth, charged to a later turn only up to `c[j] - c[first]`, capped at `c[j]`. On codex's alternating case the exposure is 0. A test asserts exposure never exceeds session value. Both assumptions are shown with the figure. |
| D3 plan formula and oracle differ; start index; window (deepseek 1) | The table states the aggregate formula, `top`, the `last + 2` start and why, the caps, and that growth may use out-of-window turns while only in-window turns are priced. The oracle implements exactly this, checked by self-tests. |
| D1 lower bound not shown in the UI (codex 2, deepseek note) | The D1 evidence line says "at least $X (priced at the cache-read rate)". |
| Oracle disagrees with the plan: output-only turns, nil first timestamp, out-of-window burst turns (codex 3) | Oracle fixed (turn means `c > 0`; `burstTurns` counts in-window turns). The plan's fold rule now takes the first non-nil timestamp, matching the oracle. All three are self-tests. |
| Oracle edited after the numbers were produced (deepseek 3) | The oracle is frozen and read-only. Its sha256 and command are in `oracle-freeze.txt` and in this plan. Calibration and sensitivity were regenerated from it. Probe 3 checks the hash first. |
| Raw `cwd` in samples makes the canary impossible (codex 4) | `UsageSample` stores only `project`, the last path component, cut at the adapter. A Task 1 test proves a parent component never reaches a sample. The canary keeps that sentinel. |
| `ReportBuilder.build` change breaks `QueryAndHistoryTests` (deepseek 4) | `QueryAndHistoryTests.swift` is in Task 1's list, for that call site only. |
| Generic `Limit` breaks `SettingsWindowController` (deepseek 5) | `Limit` stays as it is. Task 2 extracts a free `clampedSetting` function. |
| The canary can pass without the renderer (deepseek 6) | The canary runs with small thresholds and must produce a lead for each detector. It also checks `ReportText.evidenceLine(for:)` for every fired suggestion. |
| `PerfAnalyzer` loses the agent (deepseek note) | The parameter is `claudeSources`, and callers pass `.claudeCode` sources only. |
| `ReportWindow` lacks `days`; `samplesByAgent` and undated; empty files; `isSubagent` root (deepseek notes) | `ReportWindow.days` added. `samplesByAgent` includes undated samples. One `SourceSamples` per file read, empty or not. `isSubagentSource` is relative to the projects root. |
| Hidden directories (deepseek note) | Measured: no transcript sits under a hidden directory, and the snapshot has no symlinks. |
| `--report --json` schema not pinned (deepseek note) | The schema is written in "Data shape". |

## Round-3 objections → changes

Seats: `codex` (C1 to C4), `deepseek` (D1, D2). Planner's own review via `pstack:interrogate` on v0.3
(P-A opus @high, P-B fable @high, P-C sonnet @medium).

| Objection (who) | Change |
|---|---|
| D2 treats a first cache fill after uncached turns as a rewrite (C1) | `base` now uses `held = cacheRead[i-1] + cacheCreation[i-1]`, what the previous turn left in cache. The first-fill case is an oracle self-test and a Task 2 case. D2 is labelled "inferred" in the table and in the evidence line. |
| Blanket "every figure is what the session paid" contradicts D3 (C1, deepseek note) | Removed. The block ends with "API-equivalent value at list price, not a bill", and D3's line states its condition. |
| D1 evidence hard-codes 200k; renderer cannot see the floor; "N turns" ambiguous (C2, D1, P-A3) | `Finding.contextCarry` carries `floorTokens`. The line interpolates it and names `turnsAboveFloor`. `ReportTextTests` renders a non-default floor. |
| `compare.py` prints project names (C3, P-A2) | It prints "(values withheld)" for a project mismatch. `compare_selftest.py` proves it on a synthetic failure. Frozen again. |
| Project selection differs between plan and oracle; comparator drops duplicate keys (C4, P-A2, P-C2) | `project` is the first non-nil among turns, in both. `cwd` of `/` gives nil in both. The comparator rejects duplicate keys, tested. |
| No test fails when the lead-share comparison is removed (D2) | Task 2 adds `leadNeedsShareOfSessionValue` ($0.75 in a $26.55 session is not a lead). It is an oracle self-test too. `mutate.sh` names it. |
| `peakContext` and the D2 tie-break undefined (P-A1, P-C2) | A "Finding fields" column defines every field. The dominant cause ranks by tokens, then a fixed order, so unpriced sessions need no dollar ranking. |
| D3 cap is pointwise, so dropped growth is charged again (P-A4) | A running minimum per burst. Reviewer A's case gives 0.105, an oracle self-test and a Task 2 case. |
| D1 "at least" when the exact figure is computable (P-A5) | D1 prices the above-floor positions by band: read prefix, then writes, then input. It is now exact, and so an upper bound on what dropping that context could save. Self-test included. |
| The fold leaks into the shared ingest and sample type; raw Claude samples stay public (P-A6, P-C7) | The fold lives in `ClaudeUsageSampler` behind the adapter. `AgentAdapter.makeUsageSampler()` is what `ReportIngest` calls. Claude no longer implements `usageSamples(from:)`, so its non-additive raw samples never leave the file. `responseID` is gone from `UsageSample`. |
| Live path does more work per record; not measured (P-A7, P-C5) | The checkpoint hands its already-parsed record to the sampler and skips tool names and project. Probe 4 compares cold refresh time with `main`, with a pass bar. |
| Seats cannot reproduce the gate; the oracle's entry point is untested (P-C1, P-A8) | `make_synthetic_home.py` writes a synthetic tree that fires every D2 cause, a D1 lead, a D3 lead and an unpriced D1. Probe 3a runs on it, and any seat may run it. The oracle's window is one function, and a self-test runs its entry point end to end on a synthetic tree. |
| Empty state says "no pattern" when an unpriced session matched (P-A9) | "No priced pattern …", plus the unpriced count, how many matched, and their lines without a figure. |
| Two calendars (P-A10) | `ReportWindow` holds the calendar and `day(of:)`. `ReportBuilder.calendar` is deleted. |
| New canary name contains the old one's grep substring (P-A11) | The new test is `perfPrivacySentinelsNeverLeak`, and the Makefile matches both names exactly. |
| Gap is not exactly start to start (P-A12, P-C11) | Stated as the first record's timestamp, an approximation, labelled inferred. |
| Thresholds read from real preferences during the probe (P-A13) | Probe 3 checks that no `perf.*` key is set. |
| No pass criterion for time; memory unmeasured (P-C6) | Probe 4 fails on more than 15% time or 50 MB peak memory over `main`. |
| Unpriced is all-or-nothing (P-C3) | Kept, deliberately: a partial figure would compare a priced exposure with a partly priced session, and codex asked for the strict rule in round 1. The plan says so, measures it (2 of 17), and shows those sessions' patterns without a figure. |
| 1-hour cache tier (P-C4, deepseek round-2 note) | Measured: both tiers in use (`cache-tiers.txt`). D2's premium is understated for 1-hour writes, stated in Evidence and Task 4. The gap labels stay correlations. |
| `isSubagentSource` relies on layout; `isSidechain` exists (P-C9) | Not adopted in round 3. Superseded in round 4: `isSidechain` is now read per record (see the round-4 table). |
| Evidence scopes mixed (P-C8) | Each figure now names its scope. |
| Parity edges: non-UTF-8, `/`, half-cent rounding (P-C10) | The oracle drops lines that are not valid UTF-8, as `IncrementalLineReader` does (0 such lines measured). `/` gives nil. Dollars compare within half a cent. |
| Fixed D1/D2/D3 order is not a ranking (P-C12) | Lines are ordered by their evidence suggestion's exposure, for presentation only. |
| Memory claim (P-A13) | Corrected: `ReportInput` holds every final sample until the report is built. Probe 4 measures peak memory. |
| Integer keys from `clampedSetting` (deepseek note, P-A13) | Clamped, then rounded to the nearest integer. Tested. |
| Cross-poll live case (deepseek note) | Added to Task 1. |
| Empty-state "7 days" hard-coded; empty project (deepseek notes) | The day count comes from `ReportWindow.days`. An empty project renders as "unknown project". |
| The round-3 prompt named only the round-1 reply files | A planner error in the prompt. The round-2 files sat in `$SCRATCH` and the round-2 table listed every change. |
| The "frozen" oracle changed after its hashes were recorded (P-B1) | True, and the same failure as deepseek round-2 objection 3. The read-only file mode was a convention. The tooling is now committed under `tools/perf-oracle/` and pinned by git blob hash in Evidence. Probe 3 checks the blobs. Any change after approval needs a new plan round. All numbers were regenerated from the committed files. |
| D2 fires on a first cache fill (P-B2) | Fixed with `held` (same as codex 1). |
| `peakContext` undefined (P-B3) | Defined in the "Finding fields" column. |
| "Most often" is a count claim, but dominance is not by count (P-B4) | Dominance is by rewritten tokens, and the line says "the largest part". The tie order is fixed. |
| Lead-share mutation has no failing test (P-B5) | `leadNeedsShareOfSessionValue` (same as deepseek 2). |
| The window has three definitions (P-B6) | `ReportWindow` holds the calendar, `day(of:)` and `fileCutoff`. `ReportBuilder.calendar` is deleted. |
| The canary cannot reach the CLI's JSON (P-B7) | `ReportJSON.encode` lives in core. `main.swift` only prints it, and the canary checks its output. |
| Subagent exclusion keyed on a directory name only (P-B8, P-C9) | Two reviewers asked. A source is a subagent source by path or when an assistant record carries `isSidechain: true`. It costs nothing on the existing parse. The oracle does the same. Tested in Task 1 and in the oracle's end-to-end test. |
| Unterminated tail and non-object lines (P-B9) | The oracle ignores an unterminated last line and skips non-object lines, as Swift does. Self-test included. Measured: 0 snapshot files lack a trailing newline. |
| D3 per-burst caps (P-B10) | Superseded in round 4: the joint cap was shown to be a no-op and deleted. The running minimum bounds exposure. The self-test value `(5 x 20000 + 7 x 70000) x 0.30 / 1e6` stands. |
| `last + 1` reasoning (P-B11) | Reworded: skipping it is conservative. |
| `responseID` has no consumer after the fold (P-B12) | Removed from `UsageSample` (see P-A6). |
| Small spec holes: N in "also in", ordering, zero-exposure lead, file entry point, who loads thresholds, total-only comparison, who deletes the formatters (P-B13) | N counts other sessions with a lead from the same detector. Suggestions are ordered by `Finding` case name. A lead needs exposure above 0. `isSubagentSource` is false for the file entry point. The window controller and `--report` load thresholds. `compare.py --total-only` serves Task 1, tested. Task 3 deletes the formatters. |

## Round-4 objections → changes

Seats: `codex` rejected (C1, C2). `deepseek` approved v0.4, with non-blocking notes (D-n). Planner's own
review via `pstack:interrogate` on v0.4 (P-A opus @high, P-B fable @high, P-C sonnet @medium).

| Objection (who) | Change |
|---|---|
| D1 called "exact" and an upper bound on savings, while 1-hour writes use the single write rate (C1, D-n) | D1 is now "estimated at Vibra's table rates". The display footer states the table date and the single-write-rate approximation. "Exact" and "upper bound" are gone. Changes item 6 and the Cache tiers bullet say which figures it affects. |
| The probe 4 baseline cannot honour `VIBRA_NOW` (C2, P-A7, P-C1) | The baseline is a throwaway worktree of `60a61b8` plus `tools/gate/baseline-vibra-now.patch`, which adds only `VIBRA_NOW`. The comparison counts only when both sides read the same bytes. Runs are interleaved. |
| The committed oracle was edited in the shared tree during the round (P-A1) | Both seats had replied before the edits (ledger times). From now on oracle changes are committed before a round is sent. Probe 3 also requires `git diff --quiet HEAD -- tools/perf-oracle`. The tools run with `-I -B`, so no bytecode appears in the tree. |
| `isSidechain` at file grain drops a whole main session (P-B1, P-A4) | Per record now. A sidechain sample counts in totals but is never a turn. An all-sidechain file has no turns and counts as skipped. `sawSidechain` and `isSubagentSource` are gone from the protocols. The sampler's `isSubagent` is the path rule only. Oracle self-tests cover the inline record and the all-sidechain file. |
| Mutation 2 (D2 segment check) is vacuous; scripts unowned and unpinned (P-B2, P-A6, P-C1) | `compactionIsNotARewrite` uses a post-compaction write of 60k, above both D2 bars, so only the segment rule keeps it out. The synthetic home has the same shape. Every mutation names its failing test. `mutate.sh`, `perf-bench.sh` and the baseline patch are Task 3 files under `tools/gate/`, reviewed in the code gate. `mutate.sh` runs in a throwaway worktree. |
| One dip splits a segment; the 9 unmarked drops were unchecked (P-B3) | Measured: with turns as defined, 0 unmarked drops remain, and the 23 markers match the 23 drops exactly. The earlier 9 were zero-usage `<synthetic>` records (`drop-recovery.txt`). The rule is unchanged. |
| Thresholds not in the JSON (P-B4) | `PerfReport.thresholds` is encoded, and `compare.py` checks it against the oracle's. The `defaults read` step is gone. |
| D3 joint cap is a no-op (P-A2) | Deleted from the rule and the oracle. The running minimum alone bounds exposure, and the existing property test checks it. |
| Unpriced sessions said to be shown, but hidden when leads exist; vacuous empty-state variant (P-A3, D-n) | The unpriced block shows whenever an unpriced session matched, leads or not. The impossible variant is gone. `ReportTextTests` covers it alongside leads. |
| `usageSamples(from:)` stays and returns `[]` for Claude (P-A5, P-C7) | Deleted from the protocol. Every adapter goes through `makeUsageSampler(for:)`. Old callers fail to compile. `CodexAdapter.swift` and `OpenCodeAdapter.swift` are in Task 1's list. |
| Three protocol additions for one adapter (P-C4, P-B8) | One: `makeUsageSampler(for:)`, with `isSubagent` on the sampler. `add(_ lines:)` is parse plus the single fold. |
| Full-parse path truncates at 2,000 lines (P-C5) | A real defect in Claude Code and Codex `discoverSessions`. Task 1 replaces `readLines` with a per-batch helper and tests a 2,500-line transcript for both. |
| Rates unverified (P-C6) | Stated in Evidence, in the display footer and in Task 4. Re-verifying rates stays out of scope. |
| No date to find the session (P-C2) | `Suggestion.startedAt`, rendered as a local date in every evidence line. |
| Synthetic home misses this round's rules (P-C3) | It now holds an inline sidechain record, a line that is not valid UTF-8, an unterminated last line and the `compactionIsNotARewrite` shape. |
| D3 unvalidated on real data (P-C7) | Evidence and Task 4 say it has not been observed as a lead on real sessions. It stays priced. Its rules are pinned by self-tests. |
| JSON schema version, docs for the new CLI surface (P-C8) | `"schema": 1`. Task 4 documents `--report --json` and `VIBRA_NOW`. |
| "The one calendar" overclaims (P-C9) | Narrowed to the report and the analyzer. |
| `modelSwitch` action names MCP servers (P-C10) | Removed. |
| Top-3 ordering tie-break; `TZ` not pinned; naive timestamps and non-numeric usage (P-B5 to P-B7, P-A10) | Ties break by `Finding` case name. Probes and self-tests run under `TZ=America/Los_Angeles`, and the DST check compares the full offset. The oracle rejects timestamps with no zone and reads usage values like `jsonInt`. Both are self-tests. |
| Canary thresholds outside the ranges (P-A9) | The canary uses in-range values. The memberwise initializer is internal and used by tests. |
| Evidence cites a stale artifact; no calibration driver (P-A8) | `calib_summary.py` prints the blob hashes and its command, then the summary (`calib-v05.txt`). `d1_sensitivity.py` calls the committed `report()`. |
| `isSidechain` missing from the privacy docs (P-A11) | Added to Task 4. |
| Plan carries local paths into a public repo (P-B9) | `$SCRATCH` is named without its path, and Task 4 strips any local path before the merge. The data-incident row stays, as the record of what happened. |
| Smaller notes from deepseek: ISO 8601 dates, half-cent wording, `--now` invocation, subagent counts, joint-cap case, stale round-3 row, oracle docstring | Dates encode as ISO 8601. "Strictly within half a cent". The probe pins `--now <value>`. Task 2 asserts subagent counts. The running-minimum case with an earlier burst's remaining growth is listed. The round-3 row is marked superseded. The docstring no longer names a plan version. |
| `Suggestion` repeats per-session fields (P-B10) | Kept. The flat list is what the comparator keys on. |

## Round-5 objections → changes

Seats: `codex` (C1) and `deepseek` (D1) both rejected, each with one objection. Planner's own review via
`pstack:interrogate` on v0.5 (P-A opus @high, P-B fable @high, P-C sonnet @medium), briefed to report
blocking defects only.

| Objection (who) | Change |
|---|---|
| Task 1 cannot compile: `PerfReport.thresholds` needs `PerfThresholds`, a Task 2 type (D1, P-A1, P-B1) | Task 1 writes `Perf/PerfThresholds.swift` with the type, its defaults, `Codable` and the memberwise initializer. Task 2 adds only `load(from:)` and the `clampedSetting` extraction, in the same file, after Task 1. |
| `PerfThresholds` JSON keys ambiguous; the gate compares them exactly (C1, P-A1, P-B2, P-C2, D note) | The keys are the seven bare names, which the plan lists. `perf.` belongs only to `defaults write`. A `ReportJSON` test asserts the exact encoded keys. |
| The Codex sampler keeps today's per-batch model loss (P-A2, P-C1) | A real defect: Codex tokens after line 2,000 of a rollout are unpriced in today's report. The Codex sampler keeps the last model across batches, following `session_meta` and `turn_context` as `CodexCheckpoint` does. The 2,500-line Codex test asserts the model, `unpricedTokens == 0` and the value. |
| Unpriced block: which session supplies each line is unspecified (P-B3) | The matching unpriced session with the most in-window turns, ties by `sessionID`, in the fixed order D1, D2, D3, plus "also in N other unpriced sessions". Tested. |
| The marker-agreement figure has no producing script; last turn skipped (P-A3, P-B4) | `drop_recovery.py` now computes the agreement itself, includes a file's last turn and skips sidechain records. Regenerated: 23 markers with a drop, 0 without, 0 unmarked drops. |
| `calib-v05.txt` and `d1-sensitivity.txt` ran before the commit (P-A3, P-C note, D note) | Both re-run on the clean committed tree. Each starts with the blob hashes and `dirty: False`, with identical numbers. |
| Probe 4 cannot check exact bytes against the baseline (P-B5) | The baseline patch prints the exact byte count and the file count. The plan says the patch adds those two things and `VIBRA_NOW`, nothing else. The comparison requires both to match. |
| `startedAt` is not in the oracle (D note) | Stated on the field. It is covered by the Task 2 and Task 3 unit tests only. |
| All-sidechain file count not covered by the Swift acceptance (D note) | Task 2 asserts that such a source counts as skipped. |
| Round-3 P-B10 row still describes the joint cap (D note) | Marked superseded. |
| `readLines` left behind (D note) | Deleted in Task 1 once both full-parse paths fold per batch. |
| `--now` invocation (D note) | Already pinned in probe 3a as `--now <value>`. |

## Round-6 objections → changes

Seats: `codex` approved v0.6. `deepseek` rejected it with one objection. Planner's panel not re-run on
v0.6: its diff only resolved round-5 findings (deviation from the interrogate cadence, recorded here).

| Objection (who) | Change |
|---|---|
| Probe 4 needs exact bytes and files from both sides, but only the baseline prints them (deepseek 1) | `ReportInput.filesRead` added. `ReportJSON` gains `"read": {"bytes", "files"}`, exact, tested. The branch side of probe 4 reads them from `--report --json`. The baseline patch prints `read-exact bytes=<n> files=<n>`. |
| `ReportText` read line unspecified (deepseek note) | It keeps today's line with the file count: "Read X MB from N files in Ys." |
| `CodexCheckpoint` reads the model only from `session_meta` (deepseek note) | The plan now says `session_meta` only. |
| Baseline patch files not named (deepseek note) | `ReportIngest.swift` (file count) and `main.swift` (`VIBRA_NOW`, the read line). |

## Round-7 objections → changes

| Objection (who) | Change |
|---|---|
| The `read` values have no path into `ReportJSON.encode` or `ReportText.render` (codex 1, deepseek 1) | `ReadStats { bytes, files }` lives on `ReportInput`. `ReportJSON.encode(usage:window:read:perf:)` and `ReportText.render(usage:perf:read:seconds:)` take it explicitly, and both callers pass `ReportInput.read` from the same ingest. A `ReportJSON` test runs a fixture tree from `collect` to `encode`. A `ReportText` test covers the read line. The canary passes the fixture's `read`. |
| Probe 4 times JSON on one side and text on the other (deepseek note) | Both timed runs are text `--report`. The branch's exact counts come from an extra untimed `--report --json` run. |

## Plan gate record

The plan gate passed on plan v0.8, commit `99ed4ab`, after 8 rounds.

| Seat | Final verdict | On |
|---|---|---|
| `reviewer-codex` (GPT-6.1-Sol, high) | `PLAN-APPROVED` | v0.8, `99ed4ab` (round 8) |
| `coder-deepseek` (DeepSeek V4.1 Flash) | `PLAN-APPROVED` | v0.8, `99ed4ab` (round 8) |
| planner (`claude`, claude-opus-5-5) | `PLANNER (claude): PLAN-APPROVED` | v0.8, `99ed4ab` |

Rejections by round: codex R1 to R5 and R7, deepseek R1 to R3 and R5 to R7. Codex approved v0.6 and
deepseek approved v0.4; both approvals were superseded by later changes and re-confirmed on v0.8.
`pstack:interrogate` (opus @high, fable @high, sonnet @medium) ran on v0.1, v0.3, v0.4 and v0.5. It was
not re-run on v0.6 to v0.8, whose diffs only resolved round-5 to round-7 findings (a recorded deviation
from the cadence). Accepted non-blocking note (deepseek R8): probe 4's 15% time bar covers the added
analysis and rendering as well as the read. The exact bytes-and-files guard is what isolates the read.

## Outcome

**Shipped on `feat/perf-suggestions`** (not merged or pushed): Tasks 1 to 4 on top of `BASE` `c4b318c`.
Final reviewed revision `a3aae3f` (diff hash of `git diff c4b318c` over the 32 implementation paths),
head `c19c3a3`.

**Code gate.** Unanimous after 2 rounds.

| Seat | Round 1 (`ac54d9d`) | Round 2 (`a3aae3f`, final) |
|---|---|---|
| `reviewer-codex` | `IMPL-APPROVED` | `IMPL-APPROVED` |
| `coder-deepseek` | `IMPL-APPROVED` | `IMPL-APPROVED` |
| planner (`claude`) | | `PLANNER (claude): IMPL-APPROVED` on `a3aae3f`, base `c4b318c` |

Round 2 was a confirmation round for one commit (`c19c3a3`) made from round-1 notes. `pstack:interrogate`
(opus @high, fable @high, sonnet @medium) ran on the round-1 diff; it found no correctness or privacy
defect. It was not re-run on round 2, whose 67 lines only resolved its own and the seats' notes (a
recorded deviation from the cadence).

**Who wrote what.** Task 1 and Task 3: planner-owned subagents (Fable) in their own worktrees, reviewed
and verified by the planner before merge. Task 2: `coder-deepseek`. Task 4 and the fixes `c3db411`,
`512cadc`, `c19c3a3`: the planner.

**Probes at `c19c3a3`** (saved in the run's scratch directory as `probes-r1.txt`, `probes-r2.txt`,
`mutate-r2.txt`):

1. `make test SWIFT_BUILD_SYSTEM=native`: 254 tests in 35 suites passed; both canaries passed.
2. `make bench` on the frozen snapshot: PASS 3 times of 3 (an unchanged refresh reads 0 bytes). On the
   live home it failed intermittently because agents were writing during the run.
3. Oracle comparison, tooling clean at the pinned blobs, both self-tests passing. 3a synthetic home:
   61,034,916 tokens, 7 of 7 suggestions, 6 of 6 leads, MATCH. 3b frozen snapshot: 1,931,896,094 tokens,
   19 of 19 suggestions, 11 of 11 leads, MATCH.
4. `perf-bench.sh`, 3 interleaved runs each on the snapshot (473,058,916 bytes, 166 files, equal on both
   sides): `--report` median 7.98 s against 7.91 s baseline, peak RSS 518 MB against 518 MB, PASS. The
   first run, at `c3db411`, failed at 21.65 s against 8.30 s. A process sample traced it to ISO 8601
   formatter construction for every line in `ClaudeUsageSampler.add(_:)`, fixed in `512cadc`.
5. `mutate.sh`: all 4 mutations caught, each by its named test.

**What review caught.** Plan gate (8 rounds): the D2 formula fired on new content and on first cache
fills; D3 charged growth that had already dropped; the oracle disagreed with the plan in several places
and was once edited after its freeze (fixed by committing and pinning it); a real data incident (round 1,
see Run info); two build breaks in task ownership; and the Codex model loss after line 2,000. Code gate:
non-blocking notes only; the planner's own probe 4 caught the 2.6x report regression before review.

**Deviations from the plan, accepted at the code gate.** An opt-in `SWIFT_BUILD_SYSTEM` Makefile
variable (the default swiftbuild backend of this Swift 6.4 Command Line Tools toolchain cannot load the
Swift Testing macro plugin, on the base commit too); `ReportJSON.encode` throws; the default sampler is
`EmptyUsageSampler`; one batch loop `foldLineBatches`; ReportText presentation choices listed in the
round-1 implementation notes; a third empty state for no Claude Code sessions at all.

**Known follow-ups (non-blocking, recorded at the code gate).**

- With only subagent transcripts in the window, the empty state says "No Claude Code sessions" under a
  usage total that includes them. Word it "No Claude Code main-thread sessions", with a test.
- The window runs build and analysis on the main actor (probe 4 bounds the cost); move them off it.
- The `Finding`-to-name mapping is switched in three places; give `Finding` one `detector` property.
- `parseISODate` builds formatters per call on the live path too (unchanged from `main`); cache them.
- `PerfAnalyzer.analyze` is one long function; `foldLineBatches` belongs on `IncrementalLineReader`, and
  `SessionIngest` keeps its own copy of the loop.
- The report carries two "not a bill" sentences; a 1.5M floor renders "1500k"; "from 1 files"; the JSON
  window has no time zone; CLI diagnostics now read whole transcripts.
- The fold merges only adjacent records of one response; that held for every repeat measured.
- `make test` without the variable still fails on this toolchain.

**Seat dispositions.** `coder-deepseek` and `reviewer-codex`: left attached for the user.

## Dispatch ledger

Every dispatch of the run: time, ID, seat, evidence, event.

```
2026-11-03T21:40:12Z	deepseek-plan-r1	deepseek	plan v0.1	sent
2026-11-03T21:40:12Z	codex-plan-r1	codex	plan v0.1	sent
2026-11-03T21:40:54Z	deepseek-plan-r1	deepseek	plan v0.1	delivered
2026-11-03T21:40:54Z	codex-plan-r1	codex	plan v0.1	delivered
2026-11-03T21:44:30Z	codex-plan-r1	codex	plan v0.1	verdict PLAN-REJECTED
2026-11-03T22:01:56Z	deepseek-plan-r1	deepseek	plan v0.1	verdict PLAN-REJECTED
2026-11-03T22:07:41Z	deepseek-plan-r2	deepseek	plan v0.2	sent
2026-11-03T22:07:41Z	codex-plan-r2	codex	plan v0.2	sent
2026-11-03T22:08:01Z	deepseek-plan-r2	deepseek	plan v0.2	delivered
2026-11-03T22:08:01Z	codex-plan-r2	codex	plan v0.2	delivered
2026-11-03T22:12:30Z	codex-plan-r2	codex	plan v0.2	verdict PLAN-REJECTED
2026-11-03T22:19:02Z	deepseek-plan-r3	deepseek	plan v0.3	sent
2026-11-03T22:19:02Z	codex-plan-r3	codex	plan v0.3	sent
2026-11-03T22:19:21Z	deepseek-plan-r3	deepseek	plan v0.3	delivered
2026-11-03T22:19:21Z	codex-plan-r3	codex	plan v0.3	delivered
2026-11-03T22:20:05Z	deepseek-plan-r2	deepseek	plan v0.2	verdict PLAN-REJECTED
2026-11-03T22:22:13Z	codex-plan-r3	codex	plan v0.3	verdict PLAN-REJECTED
2026-11-03T22:24:46Z	deepseek-plan-r3	deepseek	plan v0.3	verdict PLAN-REJECTED
2026-11-03T22:34:35Z	deepseek-plan-r4	deepseek	plan v0.4	sent
2026-11-03T22:34:35Z	codex-plan-r4	codex	plan v0.4	sent
2026-11-03T22:34:55Z	deepseek-plan-r4	deepseek	plan v0.4	delivered
2026-11-03T22:34:55Z	codex-plan-r4	codex	plan v0.4	delivered
2026-11-03T22:38:00Z	codex-plan-r4	codex	plan v0.4 839fb6a	verdict PLAN-REJECTED
2026-11-03T22:42:45Z	deepseek-plan-r4	deepseek	plan v0.4 839fb6a	verdict PLAN-APPROVED
2026-11-03T22:52:04Z	deepseek-plan-r5	deepseek	plan v0.5	sent
2026-11-03T22:52:04Z	codex-plan-r5	codex	plan v0.5	sent
2026-11-03T22:52:26Z	deepseek-plan-r5	deepseek	plan v0.5 2276132	delivered
2026-11-03T22:52:26Z	codex-plan-r5	codex	plan v0.5 2276132	delivered
2026-11-03T22:55:40Z	codex-plan-r5	codex	plan v0.5 2276132	verdict PLAN-REJECTED
2026-11-03T22:57:23Z	deepseek-plan-r5	deepseek	plan v0.5 2276132	verdict PLAN-REJECTED
2026-11-03T23:01:36Z	deepseek-plan-r6	deepseek	plan v0.6	sent
2026-11-03T23:01:36Z	codex-plan-r6	codex	plan v0.6	sent
2026-11-03T23:01:44Z	deepseek-plan-r6	deepseek	plan v0.6 35cbeeb	delivered
2026-11-03T23:01:44Z	codex-plan-r6	codex	plan v0.6 35cbeeb	delivered
2026-11-03T23:04:34Z	codex-plan-r6	codex	plan v0.6 35cbeeb	verdict PLAN-APPROVED
2026-11-03T23:06:10Z	deepseek-plan-r6	deepseek	plan v0.6 35cbeeb	verdict PLAN-REJECTED
2026-11-03T23:06:28Z	deepseek-plan-r7	deepseek	plan v0.7	sent
2026-11-03T23:06:28Z	codex-plan-r7	codex	plan v0.7	sent
2026-11-03T23:06:36Z	deepseek-plan-r7	deepseek	plan v0.7 62b4ed6	delivered
2026-11-03T23:06:36Z	codex-plan-r7	codex	plan v0.7 62b4ed6	delivered
2026-11-03T23:08:22Z	deepseek-plan-r7	deepseek	plan v0.7 62b4ed6	verdict PLAN-REJECTED
2026-11-03T23:09:39Z	codex-plan-r7	codex	plan v0.7 62b4ed6	verdict PLAN-REJECTED
2026-11-03T23:09:51Z	deepseek-plan-r8	deepseek	plan v0.8	sent
2026-11-03T23:09:51Z	codex-plan-r8	codex	plan v0.8	sent
2026-11-03T23:09:59Z	deepseek-plan-r8	deepseek	plan v0.8 99ed4ab	delivered
2026-11-03T23:09:59Z	codex-plan-r8	codex	plan v0.8 99ed4ab	delivered
2026-11-03T23:11:50Z	deepseek-plan-r8	deepseek	plan v0.8 99ed4ab	verdict PLAN-APPROVED
2026-11-03T23:40:20Z	planner-task1	planner	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 head a69a22a: 202 tests native, 3a+3b total MATCH, bench 3/3 PASS frozen	done succeeded
2026-11-03T23:40:36Z	deepseek-task2-a1	deepseek	plan v0.8, base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1, on a69a22a	sent
2026-11-03T23:40:56Z	deepseek-task2-a1	deepseek	plan v0.8, base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1, on a69a22a	delivered
2026-11-03T23:43:24Z	codex-plan-r8	codex	plan v0.8 99ed4ab	verdict PLAN-APPROVED
2026-11-03T23:47:42Z	deepseek-task2-a1	deepseek	232 tests native; names present; scope 4 files; committed 6641281	done succeeded
2026-11-04T00:16:00Z	deepseek-impl-r1	deepseek	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 rev ac54d9d0b696c96fcf14e5d1d5ef8703b4ef81e7	sent
2026-11-04T00:16:00Z	codex-impl-r1	codex	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 rev ac54d9d0b696c96fcf14e5d1d5ef8703b4ef81e7	sent
2026-11-04T00:16:08Z	deepseek-impl-r1	deepseek	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 rev ac54d9d0b696c96fcf14e5d1d5ef8703b4ef81e7	delivered
2026-11-04T00:16:08Z	codex-impl-r1	codex	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 rev ac54d9d0b696c96fcf14e5d1d5ef8703b4ef81e7	delivered
2026-11-04T00:21:18Z	codex-impl-r1	codex	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 rev ac54d9d0b696c96fcf14e5d1d5ef8703b4ef81e7	verdict IMPL-APPROVED
2026-11-04T00:25:01Z	deepseek-impl-r1	deepseek	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 rev ac54d9d0b696c96fcf14e5d1d5ef8703b4ef81e7	verdict IMPL-APPROVED
2026-11-04T00:31:36Z	deepseek-impl-r2	deepseek	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 rev a3aae3f0a1e0c82e2a31d3e0809883b2c16744c5	sent
2026-11-04T00:31:36Z	codex-impl-r2	codex	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 rev a3aae3f0a1e0c82e2a31d3e0809883b2c16744c5	sent
2026-11-04T00:31:45Z	deepseek-impl-r2	deepseek	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 rev a3aae3f0a1e0c82e2a31d3e0809883b2c16744c5	delivered
2026-11-04T00:31:45Z	codex-impl-r2	codex	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 rev a3aae3f0a1e0c82e2a31d3e0809883b2c16744c5	delivered
2026-11-04T00:34:39Z	codex-impl-r2	codex	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 rev a3aae3f0a1e0c82e2a31d3e0809883b2c16744c5	verdict IMPL-APPROVED
2026-11-04T00:36:16Z	deepseek-impl-r2	deepseek	base c4b318c8fd0cfd9e24fe642b8fb1f312abededc1 rev a3aae3f0a1e0c82e2a31d3e0809883b2c16744c5	verdict IMPL-APPROVED
2026-11-04T00:36:44Z	planner-task3	planner	254 tests native; 3a/3b MATCH; probe 4 PASS; mutate 4/4	done succeeded
2026-11-04T00:36:44Z	planner-task4	planner	docs reviewed in code gate r1 and r2	done succeeded
2026-11-04T00:36:55Z	seat:deepseek	deepseek	-	disposition left
2026-11-04T00:36:55Z	seat:codex	codex	-	disposition left
```
