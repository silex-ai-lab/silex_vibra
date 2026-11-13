# Plan: minutes your agents waited on you (research direction C)

Version: v0.1. Status: draft for the plan gate, round 1. Date: 2026-11-13.

## What the owner asked for

"Build a plan for project C in `docs/research/2026-11-12/` (minutes waited),
execute it after it passes. Codex's reviewer seat runs GPT-6.1 Sol on Bedrock."

Direction C in `docs/research/2026-11-12/research-literature.md`: from local
transcripts, compute per-session "blocked-on-human" minutes (from a finished
turn or a prompt to the human, to the human's next event), and time-to-answer
as a function of how many prompts came earlier in the session (a habituation
curve). Then compare a week with Vibra's notifications off against a week with
them on, reported as median and IQR with session counts, as an n=1 pilot. The
previous plan (`docs/PLAN-2026-11-12-release-and-test-integrity.md`, "The
pick") deferred this metric to "the next plan".

## Run record

| Item | Value |
|---|---|
| Fleet | orca-agent-fleet, standard roster, transport Orca (own handle `term_a7c1…` resolved, runtime reachable, Orca 1.4.248) |
| Planner | Claude Code 2.1.323, `claude-opus-5-5`, calling pane |
| reviewer-claude | Claude Code started with `claude --model fable --permission-mode default --add-dir $SCRATCH` (Fable, a model other than the planner's), Orca pane |
| reviewer-sol (in place of reviewer-codex) | GPT-6.1 Sol on Amazon Bedrock (`us.openai.gpt-6.1-sol`, profile `silex-sol-us-geo`, US Geo, Responses API, `store=False`), one bounded call per round through `$SCRATCH/sol-review.py` (the adapter that served round 2 of the previous run). Replacement authorized by the owner in the request. It cannot open the repo, so every prompt inlines the plan, the source files it judges and, at the code gate, the full diff and probe output. Spend goes to the owner's standing $50/day Sol ledger (USD 3.71 spent today before this run) |
| coder-deepseek | OpenCode 2.0.20, `deepseek/deepseek-flash` (DeepSeek V4.1 Flash), balance USD 37.02 at preflight. Codes, never votes |
| Why not coder `sol` | Sol holds a reviewer seat this run, and the skill forbids a coder from filling a reviewer seat in a run where it writes code. The fallback order's next coder is `deepseek` |
| Gates | Both reviewers' literal approvals plus the planner's written sign-off |
| Branch | `feat/wait-stats` from `origin/main` at `eb08b6c` |
| `$SCRATCH` | `/var/folders/x3/8mdzc51d11j_z0l1mt77lpmr0000gn/T//fleet-kC4dbe` |
| Review base | Recorded when the plan gate passes |
| Data rule | Repo is public. Seats read the repo and `$SCRATCH` only, never `~/.claude`, `~/.codex`, `~/Library` or any transcript. Probes over real transcripts are run by the planner only and print counts and durations only. Nothing in a Sol prompt comes from a transcript |
| Toolchain floor | CI builds on Swift 6.1.2 (the repo's floor). Code must compile there |

## Local measurements (planner-only probes, counts and durations only)

Scripts and outputs: `docs/research/2026-11-12/probe/`, run 2026-11-13 10:31
UTC, window 30 days by file modification time. They are previews with a looser
rule than the spec below (wrapper detection approximated by a leading `<`, no
date window per wait), not results.

| Measure | Value | Source |
|---|---|---|
| Claude Code transcripts on disk, oldest | 39.4 days | `rectypes` run in the planner's scratchpad; Claude Code keeps about 30 days, so no pre-Vibra baseline exists |
| Attended Claude Code sessions (at least one typed prompt) | 221 | `wait-turn-30d.txt` |
| Turn waits closed by a typed prompt | 764, of which 80 longer than 2 h | `wait-turn-30d.txt` |
| Sessions whose transcript ends on an open wait | 204 | `wait-turn-30d.txt` |
| Turn wait seconds, p25 / p50 / p75 (capped at 2 h) | 158 / 596 / 3268 | `wait-turn-30d.txt` |
| Blocked minutes per attended session, p25 / p50 / p75 | 0 / 0 / 84 | `wait-turn-30d.txt` |
| Claude Code tool results answered by the human (`permissionDecision.source` starting `user`) | 66 in 33 sessions: 54 `AskUserQuestion`, 12 `Bash` | `wait-prompt-30d.txt` |
| `AskUserQuestion` results by decision | 47 accept, 7 reject, 6 with no `permissionDecision` | `wait-prompt-30d.txt` |
| Tool results decided by config (classifier, mode, rule) | about 38,000 | `permission-decision-30d.txt` |
| Codex prompts that look typed, by session kind | attended 322 (45 sessions), subagent 333 (150 sessions), exec 13 | `wait-prompt-30d.txt` (`codex_subagent_probe.py`) |

Three readings shape the spec:

1. **Permission prompts are rare here.** The owner runs Claude Code in auto
   mode (8,218 of 8,331 `permission-mode` records say `auto`), so the
   classifier answers almost every tool call. 12 human-answered `Bash` prompts
   in 30 days cannot carry a habituation curve. Questions the agent asks with
   `AskUserQuestion` (54) are the larger mid-turn wait, and their result time
   is the answer time, with no tool run time in it. So the spec has three wait
   kinds: `turn`, `question`, `approval`.
2. **Codex records no approval prompts.** Its rollout files carry
   `approval_policy` but no prompt or decision events, and
   `request_user_input_async` does not block the turn. Codex gets turn waits
   only.
3. **History counts Codex subagent prompts as the human's.** Codex writes a
   rollout file per subagent (`session_meta.source` is an object with a
   `subagent` key: the approval guardian, spawned threads), and its `user`
   messages come from the parent agent. `CodexHistoryExtractor` excludes only
   `codex_exec`, so the History window shows those as questions today (333
   typed-looking prompts in 150 such files). The wait metric reuses the
   History rule for "the human typed", so the rule is fixed once, for both.

## The pick

**A measurement, not a new surface.** `Vibra --wait-stats` prints, per agent,
how long sessions waited on the human, from local transcripts, as counts and
durations only. A Python oracle implements the same spec independently and
must agree with it on the owner's data. The 30-day result is written up as an
n=1 pilot. The notifications on/off comparison runs afterwards as an owner
protocol over two dated weeks, with the same command.

Why no UI in this run: a figure on the menu or in Session Details is a claim
to every user, and its definition (what counts as waiting, the 2 h cap, what
an open wait means) has not met real data yet. The pilot decides whether a
surface earns its place; that is the next plan.

### Considered and not picked

| Candidate | Why not now |
|---|---|
| "Waited on you" in the menu or Session Details | After the pilot (above) |
| Approval habituation curve as the headline | 12 human-answered permission prompts in 30 days on the owner's machine. The curve is computed (per kind, per ordinal bucket) but reported only with its n |
| Logging Vibra's notification state inside Vibra | macOS owns the authorization; the owner's dated weeks are enough for an n=1 pilot and add no stored state |
| Codex question waits from `request_user_input_async` | Asynchronous: the turn does not wait on it |
| Waits for the other four agents | Their stores do not record a prompt-answer pair Vibra reads today |

## Specification

### Foundation types (task 1)

```swift
public enum WaitKind: String, Sendable, CaseIterable { case turn, question, approval }
public enum WaitAnswer: String, Sendable { case accept, reject, unknown }

/// One interval in which a session waited on the human. Dates only.
public struct HumanWait: Sendable, Equatable {
    public let kind: WaitKind
    public let start: Date
    public let end: Date
    /// nil for `.turn`; `.unknown` when the result carries no decision.
    public let answer: WaitAnswer?
}

/// One transcript's waits. Never carries text, a path or an id.
public struct WaitFold: Sendable, Equatable {
    public var waits: [HumanWait] = []
    /// Times of the human's typed prompts (History's rule, minus fleet dispatches).
    public var humanPrompts: [Date] = []
    /// Start of a turn wait still open when the transcript ends.
    public var openSince: Date?
}

public protocol WaitExtractor {
    mutating func fold(_ lines: [String])
    func finish() -> WaitFold
}
```

`AgentAdapter` gains `func waitExtractor() -> (any WaitExtractor)?`, default
nil; Claude Code and Codex return theirs. `WaitIngest` (an actor modelled on
`HistoryIngest`) reads every JSONL source of those adapters modified at or
after the window start minus one day, from byte zero, one extractor per
source, and returns `[(agent: AgentKind, fold: WaitFold)]`. It keeps nothing.

### The human's prompt

A **human prompt** is a record that `ClaudeHistoryExtractor` or
`CodexHistoryExtractor` turns into a `QuestionRecord`, whose normalized text
does not satisfy `isFleetDispatch`. The wait extractor composes the History
extractor (feeding it one line at a time, so prompts keep their position among
the other records), so there is one definition of "the human typed".

A **dispatch prompt** is such a record whose text does satisfy
`isFleetDispatch`: a fleet planner, not a human, wrote it.

History change (task 3): `CodexHistoryExtractor` treats a session whose first
`session_meta` has `source` as a JSON object containing the key `subagent` as
unattended, like `originator == "codex_exec"`: it yields no questions. This
changes the History window and `--history-stats` for Codex.

A source with no human prompt contributes nothing: no waits, no session.

### Claude Code waits

Records with `isSidechain == true` are skipped entirely. For each remaining
record, in file order, with state `open: Date? = nil`, `dispatched = false`,
`uses: [toolUseID: (at: Date, name: String)]`:

- `type == "assistant"`: if `message.stop_reason == "end_turn"` and not
  `dispatched`, `open = record timestamp`; otherwise `open = nil`. Each
  `tool_use` block in `message.content` adds `uses[id] = (record timestamp, name)`.
- `type == "user"` with `tool_result` blocks: for each block whose
  `tool_use_id` is in `uses`:
  - name `AskUserQuestion`: a `.question` wait from the use's time to this
    record's timestamp;
  - otherwise, when `permissionDecision.source` is a string starting with
    `user`: an `.approval` wait over the same interval;
  - otherwise nothing.

  `answer` is `.accept` when `permissionDecision.decision == "accept"`,
  `.reject` when `"reject"`, `.unknown` otherwise.
- A human prompt: when `open != nil`, a `.turn` wait from `open` to the
  prompt's timestamp; then `open = nil`, `dispatched = false`.
- A dispatch prompt: `open = nil`, `dispatched = true`.

At the end, `openSince = open`.

An approval wait includes the approved tool's own run time, because the
result is written after the tool runs and no record marks the moment of the
answer. A rejected approval and every question wait have no run time in them.
Written in `docs/features.md`.

### Codex waits

State `open: Date? = nil`, `dispatched = false`. In file order:

- `event_msg` with `payload.type == "task_complete"`: if not `dispatched`,
  `open = record timestamp`.
- `event_msg` with `payload.type == "turn_aborted"`: `open = nil`.
- `response_item` with `payload.type` in `function_call`, `custom_tool_call`,
  `reasoning`, or `message` with `role == "assistant"`: `open = nil` (the
  agent worked without a human prompt).
- A human prompt and a dispatch prompt: as for Claude Code.

No `.question` or `.approval` waits. At the end, `openSince = open`.

### Window and arithmetic

- `--days N` (integer, at least 1, default 30): the window is
  `[now − N × 86,400 s, now]`. `--from YYYY-MM-DD --to YYYY-MM-DD`: from local
  midnight of `from` to local midnight of the day after `to`. Both forms
  together, one of `--from`/`--to` alone, a bad date or `from > to`: a usage
  message on stderr, exit 2.
- A wait is **in the window** when its `end` is. A source is an **attended
  session in the window** when at least one human prompt is in the window.
  Only attended sessions' waits are counted.
- Durations are integer milliseconds, `ms(t) = round(t.timeIntervalSince1970 × 1000)`.
  A wait's **capped duration** is `min(max(end − start, 0), 7,200,000)`. The
  cap is the default attention decay (2 h), after which Vibra's menu stops
  calling a finished session "your turn". A wait is **over cap** when
  `end − start > 7,200,000`.
- **Blocked time** of a session: the length of the union of
  `[start, start + capped duration]` over its in-window waits of every kind.
  A session with no waits has 0.
- **Ordinal**: a source's `.question` and `.approval` waits, sorted by
  `(start, end, file order)`, are numbered from 1 across both kinds. Buckets:
  `1`, `2-3`, `4-7`, `8+`. Ordinals are assigned over the whole transcript
  before the window filter, so a window does not renumber.
- **Quantiles** (type 7): over values sorted ascending, `h = (n − 1) × p`,
  `q = x[⌊h⌋] + (h − ⌊h⌋) × (x[⌊h⌋+1] − x[⌊h⌋])` (the second term is 0 when
  `⌊h⌋ = n − 1`), for p = 0.25, 0.5, 0.75. Seconds print as `⌊q / 1000⌋`,
  minutes as `⌊q / 60000⌋`, totals as `⌊sum / 60000⌋`.

### Output of `Vibra --wait-stats`

One line per key, `<key> n=<count>` or with the listed fields, groups in this
order, keys sorted as strings within a group, a line printed only when its n
is at least 1. `<A>` is `claudeCode` or `codex`.

```
sessions agent=<A> n=<attended sessions>
open agent=<A> n=<attended sessions whose transcript ends on an open turn wait>
waits agent=<A> kind=turn n=<k>
waits agent=<A> kind=<question|approval> answer=<accept|reject|unknown> n=<k>
over_cap agent=<A> kind=<kind> n=<k>
seconds agent=<A> kind=<kind> p25=<s> p50=<s> p75=<s> n=<k>
seconds agent=<A> kind=<question|approval> ordinal=<1|2-3|4-7|8+> p25=<s> p50=<s> p75=<s> n=<k>
blocked agent=<A> p25_min=<m> p50_min=<m> p75_min=<m> total_min=<m> n=<attended sessions>
```

stderr gets one line, `read <bytes> bytes in <seconds> s`. Nothing else is
printed: no id, path, cwd, prompt or tool text.

### Privacy

Prompt text exists only inside the composed History extractor, as today, and
is dropped after the dispatch check. Tool input is never read; only the tool
`name`, `id`, `tool_use_id`, `permissionDecision.source` and `.decision` and
timestamps are. A new canary `waitSentinelsNeverLeak` feeds both extractors
records whose prompt text, tool input, tool result, cwd, session id and file
path carry sentinels, asserts at least one wait of each Claude kind and one
Codex turn wait were produced, and asserts no sentinel reaches the
`--wait-stats` text. It joins `CANARIES` in the Makefile.

### Pilot write-up (task 7)

`docs/research/2026-11-12/wait-pilot.md`: the frozen-window output of both
implementations, the agreement result, the method and limits (n=1, one
machine, auto mode, the 2 h cap, run time inside approvals, an open final
wait is not counted, one person waits on several sessions at once so session
minutes overlap in wall time), and what it says about a UI surface. Every
number in it comes from the command output quoted there.

### Notifications on/off protocol (task 9, owner, after merge)

Vibra keeps running in both weeks; only its banners change, so the menu-bar
state stays a cue in both and the comparison isolates the notification.

1. Week A, notifications on: System Settings → Notifications → Vibra → Allow
   Notifications on. Dates recorded here.
2. Week B, off: the same switch off. Dates recorded here.
3. The planner runs `Vibra --wait-stats --from <A first> --to <A last>` and
   the same for B, and records both outputs and the differences in p50 and
   IQR of `turn` seconds and `blocked` minutes, with n. Labelled an n=1 pilot;
   workload differs between weeks and nothing here is a causal claim.

## Tasks

| # | Owner | Task | Depends on | Acceptance |
|---|---|---|---|---|
| 1 | planner | Foundation: the types above, `AgentAdapter.waitExtractor()` default nil, `WaitIngest`, `--wait-stats` argument parsing and window, printing nothing yet | — | `make test` count equals the count measured just before the change; `Vibra --wait-stats --days 1` exits 0; each bad-argument case above exits 2 |
| 2 | planner | Oracle first: `tools/wait-oracle/wait_oracle.py` implements the spec from the transcripts directly (its own History rule, including the task 3 change), with `oracle_selftest.py` | — | `oracle_selftest.py` passes, with cases for every rule bullet above; the frozen-window output (`--from 2026-10-14 --to 2026-11-12`) recorded here before task 4 starts |
| 3 | deepseek | Codex subagent sessions are unattended in `CodexHistoryExtractor` | 1 | `QueryAndHistoryTests`: a `source: {"subagent": {"other": "guardian"}}` session and a `thread_spawn` session yield no questions; `source: "cli"` and `"vscode"` still do; `make test` green |
| 4 | deepseek | `ClaudeWaitExtractor` and `CodexWaitExtractor` per spec; adapters return them | 1, 3 | `WaitExtractorTests` (synthetic fixtures): turn wait end_turn → prompt; tool_use then end_turn of the same message; an assistant `tool_use` record after end_turn clears the wait; a wrapper-only user record (`<task-notification>`) is not a prompt; `isMeta` and sidechain records ignored; dispatch prompt clears and its turn opens nothing; a human prompt after a dispatched turn re-arms; `AskUserQuestion` question waits with accept, reject, and no decision; `Bash` with `source: user_temporary` an approval, with `source: config` nothing; two tool_use blocks answered separately give two waits; an unknown `tool_use_id` gives nothing; open final wait sets `openSince`; a source with no human prompt gives an empty fold; Codex task_complete → prompt; `turn_aborted` clears; a `function_call`, `reasoning` or assistant `message` after task_complete clears; `item_completed` and `task_started` do not clear; `codex_exec` and subagent sessions empty; `make test` green |
| 5 | deepseek | `WaitStats.format` per "Window and arithmetic" and "Output"; `--wait-stats` prints it | 4 | `WaitStatsTests`: quantiles for n = 1, 2, 4, 5 against hand-computed values; floor printing; cap and over_cap at exactly 7,200,000 ms (not over) and 7,200,001 (over); union of overlapping and nested intervals; a session with no waits counts as 0; window membership by `end`, attended by prompt; ordinal assigned before the window filter; bucket boundaries 1, 2, 3, 4, 7, 8; line order and omission of n=0 lines; `make test` green |
| 6 | deepseek | Privacy canary `waitSentinelsNeverLeak`; Makefile `CANARIES` | 4, 5 | The canary passes; the planner's mutation run (the stats line includes the session id; the extractor keeps the prompt text in an output field) turns it red, recorded here |
| 7 | planner | Agreement and pilot: `diff <(Vibra --wait-stats --from 2026-10-14 --to 2026-11-12) <(wait_oracle.py --from 2026-10-14 --to 2026-11-12)` on the owner's data; `wait-pilot.md` | 5, 2 | Both built first, then run back to back in both orders. Every line except `open` is fixed for a window ending yesterday (waits, prompts and ordinals in it are in the past); `open` can change for a session still live today, so an `open` difference must flip with the run order to count as drift. Any other difference is a defect, fixed in whichever of Swift or the oracle disagrees with the spec |
| 8 | planner | Docs: CHANGELOG, `docs/features.md` (`--wait-stats`, definitions, limits), `docs/privacy.md` (what is read), `plan/STATUS.md`, literature report direction C gains a "Status" line pointing at the pilot | 7 | `tools/readme-anchors.sh` exits 0; every number in new text names its command output in `wait-pilot.md` |
| 9 | owner, then planner | Notifications on/off protocol | merge | Both weeks' outputs recorded here; gates nothing in this run |

## File ownership

- **planner:** `Sources/VibraCore/Waits/HumanWait.swift`,
  `Sources/VibraCore/Waits/WaitIngest.swift`,
  `Sources/VibraCore/Adapters/AgentAdapter.swift`, `Sources/VibraApp/main.swift`
  (task 1, then the `--wait-stats` print line goes to deepseek in task 5);
  `tools/wait-oracle/*`; this plan; `docs/research/2026-11-12/*`;
  `CHANGELOG.md`, `docs/features.md`, `docs/privacy.md`, `plan/STATUS.md`.
- **deepseek:** `Sources/VibraCore/History/QuestionRecord.swift` (task 3 only);
  `Sources/VibraCore/Waits/WaitExtractors.swift`,
  `Sources/VibraCore/Waits/WaitStats.swift`,
  `Sources/VibraCore/Adapters/ClaudeCodeAdapter.swift` and
  `Sources/VibraCore/Adapters/CodexAdapter.swift` (the `waitExtractor()` line
  only); `Sources/VibraApp/main.swift` (task 5, the print line only);
  `Tests/VibraCoreTests/QueryAndHistoryTests.swift`,
  `Tests/VibraCoreTests/WaitExtractorTests.swift`,
  `Tests/VibraCoreTests/WaitStatsTests.swift`,
  `Tests/VibraCoreTests/WaitPrivacyTests.swift`; `Makefile` (task 6, the
  `CANARIES` line only).
- One shared working tree. DeepSeek tasks run one at a time in the order 3, 4,
  5, 6; task 3 starts after task 1 is committed, task 4 after task 2's output
  is recorded. Nothing in `tools/wait-oracle/` changes while a review round is
  open.
