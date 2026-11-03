# Plan: performance suggestions for Claude Code sessions (MVP)

Status: draft v0.4, 2026-11-03. Source proposal: `Vibra_Perf_Optimization_Proposal_2026-11-03.md`
(copied to `$SCRATCH/proposal.md`). This plan replaces the proposal's section 4.1 and its section 6
MVP row where they disagree. "Changes from the proposal" says why. Each review round's objections and
their resolutions are in the tables at the end.

## Run info

| Item | Value |
|---|---|
| Roster | standard. Planner `claude` (Claude Code, claude-opus-5-5). Coder and reviewer `coder-deepseek` (OpenCode, `deepseek/deepseek-flash`, footer "DeepSeek V4.1 Flash"). Third judge `reviewer-codex` (Codex CLI 0.166.0, GPT-6.1-Sol, reasoning high). |
| Gates | Plan gate and code gate are unanimous across all three seats. |
| Branch | `feat/perf-suggestions`, cut from `main` at `60a61b8`. |
| Review base | `BASE` is recorded here when Step 5 starts. |
| Scratch | `$SCRATCH` = `/private/tmp/claude-501/-Users-jianwang/ed4a9617-ddf5-401a-85cd-bde5b7fa7ab3/scratchpad/fleet-lRT3pJ`. |
| Checkout | One shared working tree. Owners write disjoint files. Task 3 starts only after Task 2 is done, so no half-written file breaks another owner's build. |
| Data rule | The repo is public. Seats read the repo, `$SCRATCH` and synthetic fixtures only. They never read `~/.claude` or the frozen snapshot. The snapshot of real transcripts lives in a planner-only directory outside `$SCRATCH`. Seats see aggregate counts with no project names. |
| Data incident, round 1 | In round 1 the snapshot sat inside `$SCRATCH`, and `coder-deepseek` ran six read-only Python scripts over it. Its session export shows that every script printed aggregates only (file, record, model and marker counts, sizes). No message text, tool input or path reached the model. The snapshot was then moved out of `$SCRATCH`. `reviewer-codex` ran no command on it (checked in its rollout). |

## Decisions taken by the user (2026-11-03)

1. The feature gives performance suggestions about monitored agent sessions. It does not optimize Vibra itself.
2. MVP scope is D1 to D3, Claude Code only.
3. D6 (model mismatch) is deferred and is not planned for V2.
4. Suggestions appear as a Top 3 section inside the existing Usage Report (⌘U). There is no separate window.

## Evidence

All figures come from scripts in `$SCRATCH/probe/`. They ran on a frozen snapshot of this machine's
`~/.claude/projects`, taken at `2026-11-03T21:55:32Z` (176 files, 463 MB, files modified in the last 9
days, no symlinks, no transcript under a hidden directory, no line that is not valid UTF-8, no file
without a trailing newline). Outputs are
saved as `evidence-frozen.txt`, `oracle-freeze.txt`, `d1-sensitivity.txt` and `cache-tiers.txt`.
Sessions are keyed by file stem. No output names a project.

The oracle tooling is committed to the branch under `tools/perf-oracle/`, so the freeze is a git fact,
not a file mode: `perf_oracle.py` (the oracle), `oracle_selftest.py`, `compare.py` (the comparator),
`compare_selftest.py` and `make_synthetic_home.py` (a synthetic `VIBRA_HOME`). It reads synthetic data
or a path given on the command line, and holds no real data. Probe 3 checks these git blob hashes
before it runs:

```
ac18496dd2a230b4013d84d0932faa341ad8d75c  tools/perf-oracle/perf_oracle.py
8a30ea8309e05b347e6326bd67e8b520bfc36669  tools/perf-oracle/oracle_selftest.py
5acb4381ccfa9407cc927e7e0f66ac119a9ba562  tools/perf-oracle/compare.py
698612e14dceff7b6a22a6d26c21736a9272f5ce  tools/perf-oracle/compare_selftest.py
36329e889e3dae3f4f710ab7e2c8dffa4ba1ee00  tools/perf-oracle/make_synthetic_home.py
```

Every oracle-derived number below comes from those blobs (`calib-v04.txt`, `d1-sensitivity.txt`).
`oracle_selftest.py` checks 27 synthetic cases with hand-computed results, including every
counterexample from rounds 1 to 3 and an end-to-end run of the oracle's entry point on a synthetic tree
that crosses the 2026-11-01 DST change. `compare_selftest.py` checks 7 comparator cases, including its
failure paths. Changing any of these files after this plan is approved needs a new plan round.

Scopes are stated per figure. "7-day files" means files modified in the 7 days before the snapshot.
"Whole snapshot" means all 176 files.

- **Duplicate response records** (7-day files, `evidence-frozen.txt`): 19,162 assistant records with
  usage, 9,373 distinct `message.id`s, 9,789 duplicates, all adjacent to the first record of their ID among
  assistant records with usage. 0 IDs appear in more than one file. Summing every record gives
  4,544,516,386 tokens. Keeping the last record per ID gives 2,137,062,638 (ratio 2.13). Both
  `Session.usage` and the Usage Report sum every record today. Whole snapshot (`record_shapes.py`): all
  121 duplicate pairs whose usage differs differ only in `output_tokens`, and output never decreases.
- **Zero-usage records** (whole snapshot): 18, all with model `<synthetic>`, 12 in main-thread files.
- **Compaction** (7-day files): 25 `system/compact_boundary` markers. All 23 markers with a following
  assistant turn coincide with a context drop to at most 0.361 of the previous context. 9 further drops
  below half have no marker. 0 markers come without a drop.
- **Subagents** (7-day files): 133 of 158 files are under a `subagents` directory. 0 `isSidechain` records
  in main-thread files.
- **Models** (whole snapshot): `claude-opus-5-5` 17,214 records, `claude-fable-5-1` 2,893,
  `claude-sonnet-5-5` 500, `claude-opus-4-8` 16, `<synthetic>` 18. `CostTable` has no rate for Fable.
- **Cache tiers** (whole snapshot, raw records, `cache-tiers.txt`): every usage carries a
  `cache_creation` object. 5-minute writes total 46,985,629 tokens and 1-hour writes 64,753,155. Both
  tiers are in use. `CostTable` has one cache-write rate, so D2's premium is understated for 1-hour writes.
- **Calibration** (committed oracle, `now` pinned to the snapshot time, `calib-v04.txt`): Claude Code
  total in the window 1,931,896,094 tokens after folding. 17 sessions analyzed, 2 unpriced, 11 skipped as
  too small. D1 fired in 8 and was a lead in 7. D2 fired in 10 and was a lead in 4, every one dominated
  by `idleOver1h`. D3 fired in 1 and was a lead in 0. Both unpriced sessions matched a detector. No
  exposure exceeds 0.536 of its session's value. These numbers come from the data that chose the
  defaults. They are not an accuracy claim. D3 is expected to stay silent on this machine, because broad
  exploration here already runs in subagents.
- **D1 sensitivity** (`d1-sensitivity.txt`): a 100k floor with 20 turns above it gives 13 leads of 17. A
  200k floor with 50 turns gives 7. A 300k floor with 100 turns still gives 6. Long sessions here run
  above 200k for most turns, so D1 fires often. The report shows it once.

## Changes from the proposal

1. **Vibra double-counts Claude Code tokens today, and Task 1 fixes it first.** Claude Code writes one
   API response as several `assistant` records, one per content block, each repeating `message.id` and
   `usage`. The fix also changes the Usage Report: on the snapshot, Claude Code tokens drop by about half.
2. **The proposal's D2 ratio uses the wrong denominator.** `cacheRead / (input + cacheRead)` leaves out
   `cacheCreation`, and `input_tokens` is near zero in Claude Code (50,939 of 2,137,062,638 tokens).
3. **The proposal's D1 and D3 thresholds fire on almost every session.** D1 and D3 are redefined and calibrated.
4. **Subagent transcripts are excluded from the detectors and still counted in the report.**
5. **One read serves the report and the suggestions.**
6. **Figures are exposures, not savings.** D1 is the exact cost of the prompt tokens above the floor. D2
   is the write premium on context the previous turn held in cache. D3 is a conditional estimate whose
   assumptions are shown with it. None promises what an alternative would have cost, because the
   alternative (`/compact`, a subagent) has its own cost that the transcript cannot show.
7. **Thresholds are tunable through `defaults write`. The MVP has no Settings window controls.**

## Data shape

```swift
// Report/UsageSample.swift: two new fields, both defaulted, so Codex/OpenCode/Hermes are unchanged.
public struct UsageSample: Sendable, Equatable {
    public let timestamp: Date?
    public let model: String?
    public let usage: TokenUsage
    public let toolNames: [String]   // `tool_use.name` values only; never `input`, never results
    public let project: String?      // last non-empty path component of `cwd`, cut at the adapter; nil for "/" or no cwd
}

// Report/UsageSampler.swift: how an adapter turns one source's records into additive samples.
public protocol UsageSampler: Sendable {
    mutating func add(_ lines: [String]) -> [UsageSample]   // samples that are final
    mutating func finish() -> [UsageSample]                 // at end of file
}
// AgentAdapter gains `func makeUsageSampler() -> any UsageSampler`. The default wraps the existing
// stateless `usageSamples(from:)`, so Codex is unchanged. Claude Code returns `ClaudeUsageSampler`, and
// it no longer implements `usageSamples(from:)`: its raw per-record samples are not additive, so they
// never leave `ClaudeCodeAdapter.swift`. `ReportIngest` calls only `makeUsageSampler()`.
// AgentAdapter also gains `func isSubagentSource(_ url: URL) -> Bool`, default false. Claude Code returns
// true when a path component below its projects root is named `subagents`, and false for the
// single-file test entry point, which has no root.
// UsageSampler also has `var sawSidechain: Bool { get }`, default false. ClaudeUsageSampler sets it when
// an assistant record has `isSidechain == true`. A source is a subagent source when either signal holds.
```

`ClaudeUsageSampler` holds the one fold for "one response, several records". It lives in
`ClaudeCodeAdapter.swift`. Its rules:

- Only `assistant` records with a `message.usage` object become records for the fold. Other records
  never make the pending response final early and never clear it.
- A record whose non-nil `message.id` equals the pending response's ID merges into it. The merge keeps
  the pending timestamp, or takes the new one when the pending one is nil. It takes the new usage, takes
  the new model and project when they are non-nil, and appends the new tool names.
- A record with another ID makes the pending response final and becomes pending itself.
- A record with no ID makes the pending response final, and is final itself. Records with no ID never merge.

`ClaudeCheckpoint` (live polling) holds a `ClaudeUsageSampler` and `committed: TokenUsage`. It adds the
usage of every sample the sampler makes final to `committed`. `Session.usage` is `committed` plus the
pending usage. The checkpoint persists between polls, so a response split across two reads or two polls
still merges. `ClaudeCheckpoint.fold` already parses each record and its timestamp. It hands the parsed
record to the sampler (`add(record:timestamp:)`) instead of the line, and the live path skips tool names
and project, which it never uses. So the live path parses each line once, as today.

```swift
// Report/ReportWindow.swift: the one definition of the window, and the one calendar.
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
    public let isSubagent: Bool
    public let samples: [UsageSample]   // final samples; empty when the file holds no usage
}
public struct ReportInput: Sendable {
    public let sources: [AgentKind: [SourceSamples]]   // one entry per JSONL file read, empty or not
    public let undated: [AgentKind: [UsageSample]]     // OpenCode/Hermes session totals, as today
    public let bytesRead: Int
    public var samplesByAgent: [AgentKind: [UsageSample]] { get }   // sources plus undated
}
// ReportIngest.collect(window:) -> ReportInput replaces collectSamples(now:), which is deleted.
```

Memory: `ReportInput` holds every final sample of the window until the report is built, as today's
`[AgentKind: [UsageSample]]` does. Folding roughly halves the sample count. Each sample now also holds
its tool names and a project string. Probe 4 measures peak resident memory against `main`.

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
    public let turns: Int               // in-window turns
    public let finding: Finding
    public let exposureUSD: Double?     // nil when the session is unpriced
    public let sessionValueUSD: Double? // nil when the session is unpriced
    public let isLead: Bool
}
public struct PerfReport: Sendable, Equatable, Codable {
    public let analyzedSessions: Int
    public let unpricedSessions: Int
    public let skippedSmallSessions: Int
    public let suggestions: [Suggestion]   // every fired suggestion, ordered by Finding case name, then sessionID
}
```

- `PerfAnalyzer.report(claudeSources: [SourceSamples], window: ReportWindow, thresholds: PerfThresholds)
  -> PerfReport` is pure. Callers pass `ReportInput.sources[.claudeCode]` only.
- `PerfThresholds.load(from: SettingsStore)` reads the keys below through one free internal function,
  `clampedSetting(_ value: Any?, default: Double, range: ClosedRange<Double>) -> Double`, extracted from
  `VibraSettings` and built on its existing `numeric` rule. Integer keys are clamped, then rounded to the
  nearest integer. `VibraSettings.Limit` stays as it is, because `SettingsWindowController` uses it.
  `ReportWindowController` and `--report` call `load` when the report opens.
- `ReportText` in `Report/ReportText.swift` is the one text renderer:
  `render(usage: UsageReport, perf: PerfReport, bytes: Int, seconds: Double) -> String` and
  `evidenceLine(for: Suggestion) -> String`. The window and `--report` both call it. Task 3 deletes the
  existing `ReportWindowController.format` and the `--report` print block.
- `ReportJSON.encode(usage: UsageReport, window: ReportWindow, perf: PerfReport?) -> Data` in
  `Report/ReportJSON.swift` builds the `--report --json` object, so tests encode exactly what the CLI
  prints. `main.swift` only writes its output.
- `Vibra --report --json` prints one JSON object, so the gate can compare exact values. `VIBRA_NOW`
  (ISO 8601) pins `now` for `--report`. Neither prints message text. The schema:

  ```json
  {
    "window": {"days": 7, "start": "<ISO 8601>", "now": "<ISO 8601>"},
    "agents": [{"agent": "claudeCode",
                "usage": {"input": 0, "output": 0, "cacheCreation": 0, "cacheRead": 0},
                "estimatedValue": 0.0, "unpricedTokens": 0}],
    "perf": "<PerfReport, encoded by its synthesized Codable conformance>"
  }
  ```

  Task 1 writes `window` and `agents` (with `perf` nil). Task 3 passes the `PerfReport`. A `Finding` encodes as
  `{"contextCarry": {"segments": 1, "turnsAboveFloor": 60, "peakContext": 250000, "floorTokens": 200000}}`.

## Detector rules

**Terms.** A *transcript* is a Claude Code source with `isSubagent == false`. A *turn* is a final sample
with `input + cacheCreation + cacheRead > 0`. That drops the zero-usage `<synthetic>` records and
output-only records. Context `c = input + cacheCreation + cacheRead`. A turn is *in window* when
`ReportWindow.contains` its timestamp. Detection runs over every turn of the transcript. Counts and
dollar figures use in-window turns only. A session is analyzed when it has at least `minTurns` in-window
turns. Otherwise it counts as skipped.

**Segments.** A turn starts a new segment when the previous turn's context is at least 50,000 and its
own context is below half of it. This is a heuristic, not a format guarantee. On the snapshot it matches
all 23 compaction markers that have a following turn, and it adds 9 drops that have no marker. Those are
context reductions too. A compaction that keeps more than half the context would be missed, and its
rewrite could then count as a D2 event.

**Pricing.** Each turn is priced at its own model's `CostTable` rate. Rates are dollars per million
tokens, so every product below is divided by 1,000,000. A session is *priced* when every in-window turn
has a rate. An unpriced session still runs the detectors, but `exposureUSD` and `sessionValueUSD` are
nil, and it is never a lead. `sessionValueUSD` is the sum of the in-window turns' API-equivalent value.
This all-or-nothing rule is deliberate: a partial figure would compare a priced exposure with a partly
priced session. On the snapshot it affects 2 of 17 analyzed sessions, and both are reported (see Empty
states).

| # | Fires when | Finding fields | Exposure (dollars) |
|---|---|---|---|
| D1 context carry | A segment has at least `d1MinTurnsAboveFloor` in-window turns with `c > d1CarryFloorTokens`. One suggestion per session covers every qualifying segment. | `segments`: qualifying segments. `turnsAboveFloor`: their in-window turns with `c > floor`. `peakContext`: max `c` over in-window turns of qualifying segments. `floorTokens`: the floor used. | Over those turns, the exact price of the prompt tokens at positions `floor...c`. The API lays a prompt out as the cache-read prefix, then the new cache writes, then uncached input, so the overlap with each band is priced at its rate. This is what the context above the floor cost, and so an upper bound on what dropping it could have saved. |
| D2 cache rewrite | A turn `i` in window, in the same segment as turn `i - 1`, with `held = cacheRead[i-1] + cacheCreation[i-1]` (what turn `i - 1` left in cache), `base = min(held, c[i])`, `missed = min(cacheCreation[i], max(0, base - cacheRead[i]))`, `missed >= d2MinRewriteTokens` and `missed >= 0.5 x base`. Each such turn is one event. | `events`. `rewrittenTokens`: sum of `missed`. `dominantCause`: the cause with the most rewritten tokens, ties broken by the fixed order modelSwitch, idleOver1h, idleOver5m, other. | Over events: `missed x (cacheCreationRate - cacheReadRate)` at turn `i`'s rate. This is the inferred write premium on context that the previous turn had in cache. Token identity is not proven by the usage fields, so the label says "inferred". |
| D3 exploration burst | A burst is a maximal run of at least `d3MinBurstTurns` consecutive turns in one segment, `first...last`, each with at least one tool call and every tool name in {Read, Grep, Glob}, with at least one burst turn in window. | `bursts`. `burstTurns`: in-window burst turns. | Per burst: `top = last + 1` when that turn exists in the same segment, else `last`. `growth = max(0, c[top] - c[first])`. Walking `j` from `top + 1` to the end of the segment, `still = max(0, min(still, c[j] - c[first]))`, starting from `growth`. For each `j >= last + 2` in window, `carried[j] += still`. Then `carried[j]` is capped at `c[j]` minus the lowest `c[first]` among the bursts that added to it, and exposure is the sum of `carried[j] x cacheReadRate` at turn `j`'s rate. Turn `last + 1` is skipped. Only the last burst turn's results are a write there, so skipping the whole turn is a conservative choice. Growth may be measured on turns outside the window. Only in-window turns are priced. It assumes the growth came from the burst's tool results, and that once context falls back toward `c[first]`, that growth is gone for good. |

**D2 cause.** It is a correlation, never a proven cause. Models are compared as strings, a missing model
counting as a value. `modelSwitch` when turn `i`'s model differs from turn `i - 1`'s, else `idleOver1h`
when the gap between the two turns' timestamps exceeds 3,600 s, else `idleOver5m` above 300 s, else
`other`. A missing timestamp gives `other`. The timestamp of a folded turn is that of its first record,
which Claude Code writes when the first content block is done. So the gap only approximates the
interval the cache TTL counts from (inferred, not measured). The error is the first block's
generation time.

**Lead.** A suggestion is a lead when the session is priced, `sessionValueUSD > 0`, `exposureUSD > 0`,
`exposureUSD >= leadMinUSD`, and `exposureUSD >= leadMinShare x sessionValueUSD`.

**What the report shows.** One line per detector that has at least one lead, at most 3 lines, ordered by
the exposure of each line's evidence suggestion, largest first. That ordering is for presentation only.
Exposures are never summed across detectors, because D1 and D3 can price the same carried tokens. Each
line gives the action, then `evidenceLine` for that detector's lead with the largest exposure, plus
"also in N other sessions" when other sessions have a lead from the same detector (N counts them). A project of `""` renders as "unknown project".

- D1: "<project>, T turns above <floor>: the context above <floor> cost $X." T is `turnsAboveFloor` and
  `<floor>` is `floorTokens` (for example "200k").
- D2 by dominant cause:
  - `modelSwitch`: "<project>: E times, context already in cache was written again, the largest part after a model switch (inferred). Write premium $X."
  - `idleOver1h`: "... the largest part after a gap of over an hour (inferred) ..."
  - `idleOver5m`: "... the largest part after a gap of over 5 minutes (inferred) ..."
  - `other`: "... the largest part with no model switch or long gap (inferred) ..."
- D3: "<project>: B search bursts. If what they added stayed in context, re-sending it cost about $X."

The block ends with "API-equivalent value at list price, not a bill." Empty states, with the window's
day count interpolated:

- no analyzed session: "No Claude Code session in the last <days> days had enough turns to analyze."
- analyzed sessions and no lead: "No priced pattern above the thresholds in N analyzed sessions."
- either case with unpriced sessions adds: "K sessions use a model with no published rate. M of them
  matched a pattern, shown without a dollar figure." Then one line per detector matched in an unpriced
  session: the action and its evidence line with "no published rate" in place of the figure.

**Action text** (owned by `ReportText`):

- D1: "Run /compact inside long tasks and /clear between tasks. Split unrelated work into separate sessions."
- D2 `modelSwitch`: "Pick the model and MCP servers before starting. A switch mid-session writes the cache again."
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
| 1 | planner | none | `Sources/VibraCore/Report/UsageSample.swift`, `Sources/VibraCore/Report/UsageSampler.swift` (new), `Sources/VibraCore/Report/ReportWindow.swift` (new), `Sources/VibraCore/Report/ReportJSON.swift` (new), `Sources/VibraCore/Report/ReportIngest.swift`, `Sources/VibraCore/Report/ReportBuilder.swift`, `Sources/VibraCore/Adapters/AgentAdapter.swift` (`makeUsageSampler`, `isSubagentSource` and the protocol doc), `Sources/VibraCore/Adapters/ClaudeCodeAdapter.swift`, `Sources/VibraCore/Perf/Suggestion.swift` (new), `Sources/VibraApp/ReportWindowController.swift`, `Sources/VibraApp/main.swift`, `Tests/VibraCoreTests/ClaudeUsageSamplerTests.swift` (new), `Tests/VibraCoreTests/UsageSampleTests.swift`, `Tests/VibraCoreTests/ReportBuilderTests.swift`, `Tests/VibraCoreTests/QueryAndHistoryTests.swift` (the `ReportBuilder.build` call site only) | `make test` green, every existing test included. New tests, each run against both `Session.usage` and `ReportIngest` output: three records with one ID and growing output give the last usage; the same pair split across batches (`maxLinesPerRead: 1`) still merges; the same pair split across two `SessionIngest.refresh()` calls, the second record appended in between, still merges; two adjacent records with no ID never merge; a user record between two records of one ID does not split them; a first record with no timestamp takes the second's; a zero-usage record contributes 0; a property test over seeded random batch splits gives equal live and report totals. A `cwd` of `/a/SECRET/b/proj` yields `project == "proj"` and no sample field contains `SECRET`; a `cwd` of `/` yields nil. `isSubagentSource` is true for `<root>/<project>/<session>/subagents/<agent>.jsonl`, false for `<root>/<project>/<session>.jsonl` and for the single-file entry point, and a `subagents` component above `<root>` does not count. A file beside the main transcript whose assistant records carry `isSidechain: true` gives `SourceSamples.isSubagent == true`. `ReportWindow` tests cover the DST change on 2026-11-01 in `America/Los_Angeles`. `Vibra --report --json` on the synthetic home (probe 3a, any seat) and on the snapshot (probe 3b, planner only) passes `compare.py --total-only` against the committed oracle. |
| 2 | deepseek | 1 | `Sources/VibraCore/Perf/PerfThresholds.swift` (new), `Sources/VibraCore/Perf/PerfAnalyzer.swift` (new), `Sources/VibraCore/Settings/VibraSettings.swift` (extract `clampedSetting` only; `Limit` unchanged), `Tests/VibraCoreTests/PerfAnalyzerTests.swift` (new) | `make test` green, existing `VibraSettings` tests included. Synthetic samples only: Task 2 never reads the snapshot. It may run the frozen oracle and `make_synthetic_home.py` on synthetic data. For each detector, a positive case whose expected values are written in the test as arithmetic from the rules above. Required cases, mirroring `oracle_selftest.py`: new content is not D2; no cache writes means no D2; a first cache fill after uncached turns is not D2; an expired cache after 3 h is one `idleOver1h` event with exposure `100000 x (3.75 - 0.30) / 1e6`; a D2 turn with `input > 0` uses the `cacheCreation` cap; an unpriced D2 picks its dominant cause by tokens then by the fixed order; a missing timestamp gives `other`; a burst with no later turns has exposure 0; a 3-turn Read burst followed by 7 turns at +90k gives `90000 x 6 x 0.30 / 1e6`; growth that drops before a later burst is not charged again (`7 x 50000 x 0.30 / 1e6`); D3 exposure never exceeds session value; an output-only record is not a turn; `burstTurns` counts in-window turns only; D1 with 60 turns at 250k gives `60 x 50000 x 0.30 / 1e6` and is a lead; D1 over a 150k read prefix, 60k writes and 40k input gives `60 x (10000 x 3.75 + 40000 x 3.0) / 1e6`; a priced D1 of $0.75 in a $26.55 session is not a lead (named `leadNeedsShareOfSessionValue`, the test `mutate.sh` must turn red); one unpriced in-window turn gives nil figures and no lead, while an unpriced turn outside the window does not; a zero-usage `<synthetic>` sample is neither a boundary nor a model switch; `project` comes from turns; a compaction drop is neither D1 nor D2; repeated Bash is not D3; a session below `minTurns` counts as skipped; a subagent source is skipped; a priced suggestion with exposure 0 is never a lead, even with `leadMinUSD` 0. A mixed-model D3 case prices later turns at their own rates. A threshold-loading test covers clamping, rounding of integer keys and a non-numeric value. |
| 3 | planner | 1, 2 | `Sources/VibraCore/Report/ReportText.swift` (new), `Sources/VibraCore/Report/ReportJSON.swift`, `Sources/VibraApp/ReportWindowController.swift`, `Sources/VibraApp/main.swift`, `Tests/VibraCoreTests/PerfPrivacyTests.swift` (new), `Tests/VibraCoreTests/ReportTextTests.swift` (new), `Makefile` | `make test` green. The Makefile checks each canary by its exact test name, so `canaryTokenNeverLeaks` and the new `perfPrivacySentinelsNeverLeak` each fail the run when absent. The canary fixture is raw JSONL lines with one sentinel each in message text, a thinking block, `tool_use.input`, a `tool_result` content block, `wireToolInputs`, and a parent component of `cwd`. Run with small `PerfThresholds` (for example a 1k floor and 2 turns), it must produce a lead for each of D1, D2 and D3 (asserted) before asserting that no sentinel appears in any `UsageSample` field, in `ReportJSON.encode` output, in `ReportText.render` output, or in `evidenceLine(for:)` for every fired suggestion, and that `toolNames` equals the exact `name` values. Task 3 deletes `ReportWindowController.format` and the `--report` print block. `ReportText` tests cover the three empty states, the unpriced lines, the one-line-per-detector rule and its ordering, "also in N other sessions", "unknown project", and a D1 line with a non-default floor. |
| 4 | planner | 3 | `docs/features.md`, `docs/privacy.md`, `docs/ROADMAP.md`, `CHANGELOG.md`, this plan file | Docs say what each detector measures, that figures are exposures at API list price and not savings, the `defaults write` keys, that `tool_use.name`, `message.id` and the last component of `cwd` are now read for the report (never tool inputs or results), that Claude Code totals drop by about half because of the Task 1 fix, that Fable has no published rate in `CostTable`, and that 1-hour cache writes are priced at the single cache-write rate. |

Task 1 is the shared foundation. It is built and committed alone before Task 2 is dispatched. Task 3
starts after Task 2 is done.

## Probes at the code gate (saved to `$SCRATCH/probes-rN.txt`)

1. `make test`: the test count, `OK: tests executed`, and both canary names.
2. `make bench`: `PASS: an unchanged refresh reads zero bytes`.
3. Oracle comparison. First `git hash-object` of each file in `tools/perf-oracle/` must equal the blob
   hashes in Evidence, and both self-tests must pass. `defaults read ai.silexlab.vibra` must show no `perf.*` key, so `--report` runs
   on the defaults the oracle uses.
   - 3a, any seat may run it: `make_synthetic_home.py` writes a synthetic `VIBRA_HOME`. `Vibra --report
     --json` and `perf_oracle.py` run on it with `VIBRA_NOW=2026-11-03T21:00:00Z`, and `compare.py`
     compares them. The synthetic home fires every D2 cause, a D1 lead, a D3 lead and an unpriced D1.
   - 3b, planner only: the same on the frozen snapshot, with `now` at its time. Both raw JSON files stay
     in the planner-only directory.
   - `compare.py` compares the Claude Code total exactly, the three session counts exactly, and every
     fired suggestion by (`sessionID`, detector): finding fields, `turns`, `isLead` and `project`
     exactly, dollar figures within half a cent. It rejects duplicate keys. It prints counts and
     mismatches by file stem only, and withholds project values.
4. `perf-bench.sh`, on `main` and on the branch, 3 runs each, same snapshot and `VIBRA_NOW`, with min,
   median and max: `--report` wall time, bytes read and peak resident memory (`/usr/bin/time -l`), and
   `make bench`'s cold refresh time. It fails when the branch median exceeds `main`'s by more than 15% in
   time, or by more than 50 MB in peak memory.
5. `mutate.sh`: applies each mutation, runs `make test`, checks that the named test fails, restores the
   file. The mutations remove the lead-share comparison (`leadNeedsShareOfSessionValue`), remove the
   segment check in D2, let records with no ID merge in `ClaudeUsageSampler`, and copy `tool_use.input`
   into `toolNames`.

## Not doing

- Codex, OpenCode, Hermes, Cursor and VS Code detectors (V2). D4 to D8 (V2). D6 (deferred).
- A separate Performance window, `--query --perf`, and Settings window controls for thresholds.
- Adding a Fable rate or a 1-hour cache-write rate to `CostTable`. No published rate was verified in this run.
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
| `isSubagentSource` relies on layout; `isSidechain` exists (P-C9) | Not adopted. Measured 0 `isSidechain` records in main-thread files. A second signal would need a per-sample field for a case not seen. |
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
| D3 per-burst caps (P-B10) | Carry is also capped jointly at `c[j]` minus the lowest burst base. With the running minimum, the reviewer's case is already bounded. A self-test pins the expected value (`(5 x 20000 + 7 x 70000) x 0.30 / 1e6`). |
| `last + 1` reasoning (P-B11) | Reworded: skipping it is conservative. |
| `responseID` has no consumer after the fold (P-B12) | Removed from `UsageSample` (see P-A6). |
| Small spec holes: N in "also in", ordering, zero-exposure lead, file entry point, who loads thresholds, total-only comparison, who deletes the formatters (P-B13) | N counts other sessions with a lead from the same detector. Suggestions are ordered by `Finding` case name. A lead needs exposure above 0. `isSubagentSource` is false for the file entry point. The window controller and `--report` load thresholds. `compare.py --total-only` serves Task 1, tested. Task 3 deletes the formatters. |
