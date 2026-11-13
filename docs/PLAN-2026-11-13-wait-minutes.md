# Plan: minutes your agents waited on you (research direction C)

Version: v0.5. Status: draft for the plan gate, round 4. Date: 2026-11-13.

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
| Review base | `BASE=e75aa84` (plan gate passed; Step 5 started 2026-11-13). Layout: one shared working tree, coder-deepseek in its own pane |
| Data rule | Repo is public. Seats read the repo and `$SCRATCH` only, never `~/.claude`, `~/.codex`, `~/Library` or any transcript. Probes over real transcripts are run by the planner only and print counts and durations only. Nothing in a Sol prompt comes from a transcript |
| Toolchain floor | CI builds on Swift 6.1.2 (the repo's floor). Code must compile there |

## Local measurements (planner-only probes, counts and durations only)

Scripts and outputs: `docs/research/2026-11-12/probe/`, run 2026-11-13 10:31
UTC, window 30 days by file modification time. They are previews with a looser
rule than the spec below (wrapper detection approximated by a leading `<`, no
date window per wait), not results.

| Measure | Value | Source |
|---|---|---|
| Claude Code transcripts on disk, oldest | 39.5 days | `claude-record-types-30d.txt`; Claude Code keeps about 30 days, so no pre-Vibra baseline exists |
| Attended Claude Code sessions (at least one typed prompt) | 221 | `wait-turn-30d.txt` |
| Turn waits closed by a typed prompt | 764, of which 80 longer than 2 h | `wait-turn-30d.txt` |
| Sessions whose transcript ends on an open wait | 204 | `wait-turn-30d.txt` |
| Turn wait seconds, p25 / p50 / p75 (capped at 2 h) | 158 / 596 / 3268 | `wait-turn-30d.txt` |
| Blocked minutes per attended session, p25 / p50 / p75 | 0 / 0 / 84 | `wait-turn-30d.txt` |
| Claude Code tool results answered by the human (`permissionDecision.source` starting `user`) | 66 in 33 sessions: 54 `AskUserQuestion`, 12 `Bash` | `wait-prompt-30d.txt` |
| `AskUserQuestion` results by decision | 47 accept, 7 reject, 6 with no `permissionDecision` | `wait-prompt-30d.txt` |
| Tool results decided by config (classifier, mode, rule) | about 38,000 | `permission-decision-30d.txt` |
| Codex prompts that look typed, by session kind | attended 322 (45 sessions), subagent 333 (150 sessions), exec 13 | `wait-prompt-30d.txt` (`codex_subagent_probe.py`) |
| Claude Code user records History drops as wrapper-only, by leading tag | `task-notification` 846, `command-name` 100, `command-message` 63, `local-command-stdout` 52, `bash-input` 32, `bash-stdout` 32 | `wait-rule-30d.txt` |
| Claude Code slash-command records: leading `<command-name>` / `<command-message>`, and whether a `<command-name>` element is present | 100 / 63, all 163 with the element; `<bash-input>` 32 | `command-records-30d.txt` |
| Prompts that pass History's rule and still start with a tag | Claude Code: `artifact-content-authored-by-others` 1 (of 980). Codex attended: `task-notification` 9, `heartbeat` 7, `user_shell_command` 3, `command-name` 2, `command-message` 2, `realtime_delegation` 2, `local-command-stdout` 1 (of 178) | `wait-rule-30d.txt` |
| Codex turns started by an automation (`turn_trigger` `automation_heartbeat_…`) | 18 of 374 `task_started` | `wait-rule-30d.txt` |
| Codex turn waits folded under the v0.5 Codex rules, wrapper list and human-command rule (preview; History rule approximated) | 132 closed (3 of them by a `<user_shell_command>`); cleared by an assistant `message` 15, `reasoning` 1, `turn_aborted` 2, an automation `task_started` 1; 19 open at end | `wait-rule-30d.txt` |
| Codex human prompts with no `task_started` since the last `task_complete` | 0 (a turn's prompt is written after its `task_started`) | `wait-rule-30d.txt` |
| Codex automation prompts, by leading tag | `heartbeat` 18 of 18 (v0.3 run of the same probe; in v0.4 `heartbeat` is a wrapper, so they no longer pass) | `wait-rule-30d.txt` at commit `52ed678` |
| Claude Code transcripts with no human prompt but human-answered dialogs (dispatch-only fleet seats) | 4 transcripts, 6 dialogs | `wait-rule-30d.txt` |
| Assistant `stop_reason` values, Claude Code main thread | `tool_use` 43,435, `end_turn` 2,934, `stop_sequence` 33, none 9, `refusal` 1 | `wait-rule-30d.txt` |
| The same record in more than one file | Claude Code end_turn `uuid`s: 0. Codex prompts (time and text hash): 1 | `wait-rule-30d.txt` |
| Subagent-file user or assistant records without `isSidechain: true` | 0 (the probe prints only non-zero counts) | `wait-rule-30d.txt` |

Three readings shape the spec:

1. **Permission prompts are rare here.** The owner runs Claude Code in auto
   mode (8,326 of 8,448 `permission-mode` records say `auto`, `claude-record-shapes-30d.txt`), so the
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
4. **History's wrapper lists are incomplete, and some human actions are not
   questions.** Injected text with tags outside the lists passes as typed
   (the counts above), so those tags join the lists (task 3). Slash commands
   (`<command-name>`, 100) and `!` shell runs (`<bash-input>`, 32;
   Codex `<user_shell_command>`, 3) are the human acting but are not
   questions; for waits they count as human activity (below).
5. **Codex automation turns are not the human's.** `CodexCheckpoint` already
   says so (`turn_trigger` starting `automation` makes the turn's end
   `.settled`); the wait rule uses the same predicate.

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

/// Epoch milliseconds read from a record's timestamp string (see "Time").
public typealias EpochMs = Int64

/// One interval in which a session waited on the human. Times only.
public struct HumanWait: Sendable, Equatable {
    public let kind: WaitKind
    public let start: EpochMs
    public let end: EpochMs
    /// nil for `.turn`; `.unknown` when the result carries no decision.
    public let answer: WaitAnswer?
}

/// One transcript's waits. Never carries text, a path or an id.
public struct WaitFold: Sendable, Equatable {
    /// In the order the closing record appeared in the file.
    public var waits: [HumanWait] = []
    /// Times of human prompts and human commands (see "The human's prompt").
    public var humanEvents: [EpochMs] = []
    /// At least one human prompt (not only commands) in the whole transcript.
    public var hasHumanPrompt = false
    /// Start of a turn wait still open when the transcript ends.
    public var openSince: EpochMs?
}

public protocol WaitExtractor {
    mutating func fold(_ lines: [String])
    func finish() -> WaitFold
}
```

`AgentAdapter` gains `func waitExtractor() -> (any WaitExtractor)?`, default
nil; Claude Code and Codex return theirs. `WaitIngest` (an actor modelled on
`HistoryIngest`) reads every source `adapter.sources()` returns whose path
ends in `.jsonl` and which was modified at or after the window start minus
one day: for Claude Code every `.jsonl` under `.claude/projects` (subagent
files included), for Codex only files named `rollout-*.jsonl` under
`.codex/sessions`. The oracle enumerates the same set. It reads each from byte zero, one extractor per
source, and returns `[(agent: AgentKind, fold: WaitFold)]`. It keeps nothing.

### The human's prompt

A **human prompt** is a record that `ClaudeHistoryExtractor` or
`CodexHistoryExtractor` turns into a `QuestionRecord`, whose normalized text
does not satisfy `isFleetDispatch`, and which is not in a Codex automation
turn (below). The wait extractor composes the History extractor (feeding it
one line at a time, so prompts keep their position among the other records),
so there is one definition of "the human typed".

A **human command** is the human acting without asking a question: a Claude
Code `type == "user"` record that touches wait state, yields no History
record, has no `tool_result` block, and whose text (the string content, or
the joined `text` blocks), after trimming, either starts with
`<command-name>` or `<command-message>` and contains a
`<command-name>…</command-name>` element (a slash command or skill; a record
that only quotes the element further in, such as a notification, does not
qualify; Claude Code writes a custom command or skill with `<command-message>`
first and a built-in with `<command-name>` first, and all 163 measured
records of either form carry the element, `command-records-30d.txt`), or
starts with `<bash-input>` (a `!` shell run); or, outside an
automation turn, a Codex user `message` with an `input_text` block that is
exactly one `<user_shell_command>` element and which yields no History
record. It is not a question, so History still drops it.

**Classification is exclusive, in this order**: a record that yields a
History record is a dispatch prompt (its text satisfies `isFleetDispatch`, or
it is in a Codex automation turn) or else a human prompt; only a record that
yields no History record can be a human command. So a dispatch whose text
also holds a `<command-name>` element is a dispatch prompt and nothing else.

A **dispatch prompt** is a History record whose text satisfies
`isFleetDispatch`: a fleet planner, not a human, wrote it. In a Codex turn
whose `task_started` has `turn_attribution.turn_trigger` starting with
`automation`, every History record counts as a dispatch prompt (an
automation, not a human, started the turn).

One predicate each, shared rather than copied: `isFleetDispatch` (exists);
`codexSourceIsSubagent(_ payload:)`, called by `CodexCheckpoint`, History and
the wait extractor; `codexTurnIsAutomation(_ payload:)`, called by
`CodexCheckpoint` and the wait extractor. Task 3 extracts both from
`CodexCheckpoint`. History gets no automation-turn state: the 18 automation
prompts measured all arrive wrapped in `<heartbeat>`, which the wrapper list
now drops.

History changes (task 3), each with a test:

- `CodexHistoryExtractor` treats a session whose first `session_meta` has a
  subagent `source` (`codexSourceIsSubagent`) as unattended, like
  `originator == "codex_exec"`: it yields no questions.
- `ClaudeHistoryExtractor.wrapperTags` gains
  `artifact-content-authored-by-others`; `CodexHistoryExtractor.wrapperTags`
  gains `heartbeat`, `task-notification`, `user_shell_command`,
  `command-name`, `command-message`, `command-args`, `local-command-stdout`
  (the tags measured above). `realtime_delegation` stays a prompt: it carries
  what the person said in a realtime session. Whether the Claude-style tags
  seen in Codex prompts (16 records) were injected or pasted by the person
  was not established; the pilot write-up says so.

These change the History window and `--history-stats`; the CHANGELOG says so
in user terms ("Codex History no longer lists prompts its subagents received,
or injected heartbeat, notification and shell-command text").

A source is **eligible** when it holds at least one human prompt anywhere.
An ineligible source contributes nothing, whatever commands or dialogs it
holds: no waits, no session. This keeps scheduled, `sdk-cli`, `codex_exec`
and subagent transcripts out, as History does. It also leaves out a fleet
seat whose transcript holds only dispatch prompts, with its dialogs (4 such
Claude Code transcripts with 6 human-answered dialogs in 30 days, a known
limit).

### Time

A record's time is read from its `timestamp` string, never from a parsed
`Date`, so both implementations do integer arithmetic only. The string must
match `^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.(\d+))?(Z|[+-]\d{2}:\d{2})$`
and be a valid date-time; then `ms = (UTC epoch seconds of the whole-second
part, offset applied) × 1000 + the first three fraction digits, right-padded
with zeros` (digits after the third are dropped). Every timestamp in the
probe has three fraction digits and `Z` (16,719 Claude Code and 7,946 Codex
records sampled, `timestamp-format.txt`). A record whose timestamp is missing or does not match
**does not touch wait state**.

### Which records touch wait state

The composed History extractor is fed every line, as today, and applies its
own rules. For the wait rules below, a record is skipped (changes no state,
opens or closes nothing) when it has no valid time, or, for Claude Code, when
`isSidechain == true` or `isMeta == true`.

### Claude Code waits

For each record that touches wait state, in file order, with state
`open: EpochMs? = nil`, `openResponse: String? = nil` (the `message.id` of the
response that opened `open`), `dispatched = false`, and
`uses: [toolUseID: (at: EpochMs, name: String)]`:

- `type == "assistant"`, with `rid = message.id` (absent: a new response):
  - when `rid != nil` and `rid == openResponse`: a later record of the same
    response (Claude Code writes one record per content block). If its
    `message.stop_reason == "end_turn"`, `open = this record's time` (the turn
    ended at its last block); otherwise nothing changes.
  - otherwise, if `message.stop_reason == "end_turn"` and not `dispatched`:
    `open = this record's time`, `openResponse = rid`; else `open = nil`,
    `openResponse = nil`.
  - each `tool_use` block in `message.content` sets `uses[id] = (time, name)`
    only when `id` has not been seen before in this transcript (the first
    appearance wins, also after its result consumed it).
- `type == "user"` with `tool_result` blocks: for each block whose
  `tool_use_id` is a key of `uses`, remove it from `uses` (a result is
  consumed once; a repeated result for the same id yields nothing), then:
  - name `AskUserQuestion`: a `.question` wait from the use's time to this
    record's time;
  - otherwise, when the record's top-level `permissionDecision.source` is a
    string starting with `user`: an `.approval` wait over the same interval;
  - otherwise nothing.

  `answer` is `.accept` when the record's top-level
  `permissionDecision.decision == "accept"`, `.reject` when `"reject"`,
  `.unknown` otherwise. A record with several `tool_result` blocks handles
  each block in order, all with that record's one `permissionDecision`.
- A human prompt or a human command: when `open != nil`, a `.turn` wait from
  `open` to its time; then `open = nil`, `openResponse = nil`,
  `dispatched = false`.
- A dispatch prompt: `open = nil`, `openResponse = nil`, `dispatched = true`.

At the end, `openSince = open`.

`dispatched` suppresses only turn waits. A fleet seat's own turn end is read
by the planner, not a person, but a question or permission dialog in a seat
blocks until a person answers it (the fleet skills send a Claude Code seat's
dialogs to the human), so in an eligible transcript those stay counted.
A transcript with only dispatch prompts is not eligible (above). Both pinned
by tests.

An approval wait includes the approved tool's own run time, because the
result is written after the tool runs and no record marks the moment of the
answer. A rejected approval and every question wait have no run time in them.
Written in `docs/features.md`.

### Codex waits

State `open: EpochMs? = nil`, `dispatched = false`, `automation = false`. For
each record that touches wait state, in file order:

- `event_msg` with `payload.type == "task_started"`:
  `automation = codexTurnIsAutomation(payload)`; when true, `open = nil` and
  `dispatched = true`.
- `event_msg` with `payload.type == "task_complete"`: if not `dispatched`,
  `open = record time`; then `automation = false`.
- `event_msg` with `payload.type == "turn_aborted"`: `open = nil`,
  `automation = false`.
- `response_item` with `payload.type` in `function_call`, `custom_tool_call`,
  `reasoning`, or `message` with `role == "assistant"`: `open = nil` (the
  agent worked without a human prompt).
- A human prompt or human command (none can occur while `automation`, since
  such records are dispatch prompts), and a dispatch prompt: as for Claude
  Code.

`automation` covers one turn, from its `task_started` to its `task_complete`
or `turn_aborted`. Codex writes a turn's user message after that turn's
`task_started` (measured: 0 exceptions), so the next human turn's prompt is
read with `automation` already reset by its own `task_started`.

No `.question` or `.approval` waits. At the end, `openSince = open`.

### Window and arithmetic

- The window is a half-open interval `[lo, hi)` of epoch milliseconds.
  `--from YYYY-MM-DD --to YYYY-MM-DD`: `lo` is local midnight starting `from`,
  `hi` is local midnight starting the day after `to`, in the process's time
  zone (`TZ` honoured), computed by the platform calendar so a DST day is 23
  or 25 hours (Swift `Calendar(identifier: .gregorian)` with `TimeZone.current`;
  Python `datetime(y, m, d).astimezone()` per `zoneinfo`/`time.mktime`).
  `--days N` (integer, at least 1, default 30): `hi = now + 1`,
  `lo = now − N × 86,400,000`, where `now` is the clock or `VIBRA_NOW` (ISO
  8601, as `--report` reads it). Dates must match `^\d{4}-\d{2}-\d{2}$` and be
  real calendar dates. Both forms together, one of `--from`/`--to` alone, a
  bad date, `from > to`, or a bad `N`: a usage message on stderr, exit 2.
  Agreement runs (task 7) use `--from/--to` only.
- A wait is **in the window** when `lo ≤ end < hi`. An eligible source is a
  **session in the window** when it has a human event (prompt or command) or
  a wait in the window. Every in-window wait of an eligible source is
  counted, so a dialog answered inside the window counts even when the
  session's prompts all came before it.
- A wait's duration is `end − start` in integer ms. Its **capped duration** is
  `min(max(end − start, 0), 7,200,000)`. The cap is the default attention
  decay (2 h), after which Vibra's menu stops calling a finished session "your
  turn". A wait is **over cap** when `end − start > 7,200,000`.
- **Blocked time** of a session: the length, in ms, of the union of the
  half-open intervals `[start, start + capped duration)` over its in-window
  waits of every kind. A session with no waits has 0.
- **Ordinal**: a source's `.question` and `.approval` waits, sorted stably by
  `(start, end)` from their order in `WaitFold.waits`, are numbered from 1
  across both kinds. Buckets: `1`, `2-3`, `4-7`, `8+`. Ordinals are assigned
  over the whole transcript before the window filter, so a window does not
  renumber.
- **Quantiles** (type 7): over values sorted ascending, `h = (n − 1) × p`,
  `q = x[⌊h⌋] + (h − ⌊h⌋) × (x[⌊h⌋+1] − x[⌊h⌋])` (the second term is 0 when
  `⌊h⌋ = n − 1`), for p = 0.25, 0.5, 0.75. Seconds print as `⌊q / 1000⌋`,
  minutes as `⌊q / 60000⌋`, totals as `⌊sum / 60000⌋`.

### Output of `Vibra --wait-stats`

Seven groups, printed in this order, each a separate group even where two
share a first word. Within a group, lines are sorted by their **key**, the
text before the first ` p25=` or ` n=`, compared byte-wise (all ASCII). A line
is printed only when its n is at least 1. Every line ends in one `\n`; with
no lines the output is empty. `<A>` is `claudeCode` or `codex`.

1. `sessions agent=<A> n=<sessions in the window>`
2. `open agent=<A> n=<sessions in the window whose transcript ends on an open turn wait>`
3. `waits agent=<A> kind=turn n=<k>` and
   `waits agent=<A> kind=<question|approval> answer=<accept|reject|unknown> n=<k>`
4. `over_cap agent=<A> kind=<kind> n=<k>`
5. `seconds agent=<A> kind=<kind> p25=<s> p50=<s> p75=<s> n=<k>`: quantiles of
   the capped durations of the in-window waits of that kind (an over-cap wait
   enters at 7,200,000)
6. `seconds agent=<A> kind=<question|approval> ordinal=<1|2-3|4-7|8+> p25=<s> p50=<s> p75=<s> n=<k>`
7. `blocked agent=<A> scope=all unit=min p25=<m> p50=<m> p75=<m> total=<m> n=<sessions in the window>`
   and the same with `scope=within_cap`, which leaves over-cap waits out of
   the union, so the pilot shows how much of the total the cap carries.
   `total` is `⌊sum of the sessions' blocked ms / 60000⌋`.

stderr gets one line, `read <bytes> bytes in <seconds> s`. Nothing else is
printed: no id, path, cwd, prompt or tool text.

### Known limits (written in `docs/features.md`)

- An approval wait includes the approved tool's run time.
- A turn wait still open when the transcript ends is not counted (`open`
  counts those sessions).
- A turn that ends with `stop_reason` `stop_sequence`, `refusal`,
  `max_tokens` or none (43 such records in the probe) opens no wait.
- A background `<task-notification>` that restarts the agent after
  `end_turn` clears the wait; the wait then starts at the later `end_turn`.
- A transcript copied into a second file (resume or fork) counts its waits in
  both; measured once in 30 days (`wait-rule-30d.txt`).
- One person waits on several sessions at once, so session minutes overlap in
  wall time and do not add up to the person's time.
- The cap is 2 h; `scope=within_cap` shows what the cap carries.
- A session driven only by slash commands has no human prompt and is not
  eligible; nor is a fleet seat with only dispatch prompts, whose dialogs are
  then not counted (4 transcripts, 6 dialogs in 30 days).
- An interrupted turn (Claude Code interrupt, Codex `turn_aborted`) opens no
  wait, although the agent then waits.
- A prompt queued while the agent works can close a wait of about zero
  seconds.

### Privacy

Prompt text exists only inside the composed History extractor, as today, and
is dropped after the dispatch check; a record that yields no History record
has its text searched only for a leading `<command-name>`,
`<command-message>` or `<bash-input>` tag and a `<command-name>` element
(Claude Code) or for one whole `<user_shell_command>` block
(Codex), and is then dropped. Tool input is never read; only the tool
`name`, `id`, `tool_use_id`, `permissionDecision.source` and `.decision` and
timestamps are. A new canary `waitSentinelsNeverLeak` feeds both extractors
records whose prompt text, tool input, tool result, cwd, session id and file
path carry sentinels, asserts at least one wait of each Claude kind and one
Codex turn wait were produced, and asserts no sentinel reaches the
`--wait-stats` text. It joins `CANARIES` in the Makefile. `oracle_selftest.py` runs the same
sentinel check on the oracle's output, since the oracle reads transcripts too
and its output is quoted in a public write-up.

### Shared fixtures (task 2)

`Tests/VibraCoreTests/Fixtures/waits/` holds synthetic transcripts laid out
as a `VIBRA_HOME` tree (`.claude/projects/…`, `.codex/sessions/…`, fake ids,
paths and text) and, per scenario, the expected `--wait-stats --from … --to …`
output written by hand from this spec (`expected-<scenario>.txt`, with its
`TZ` in the file name when it matters). The oracle's selftest and the Swift
tests (task 5) both run every scenario against the same files and compare
byte for byte. The implementations share no code, only these files.
Scenarios cover at least: wrappers, pasted content, scheduled and `sdk-cli`
sessions, `isMeta` and sidechain records, dispatch prompts, one response
written as several records, repeated `tool_use` ids and duplicate results,
a record without a timestamp, a `subagents/` file, a slash command, a Codex
automation turn followed by a human turn (and the aborted variant), a
dispatch-only transcript with a dialog (contributes nothing), a session whose
prompt precedes the window and whose dialog answer falls inside it (counted),
a `<command-message>`-first slash command, a non-`rollout-` Codex file
(ignored), an open human turn wait followed by a dispatch whose text holds a
`<command-name>` element (no closed wait, no human event, and the dispatched
turn's end opens nothing),
a tool_use id repeated after its result consumed it plus a duplicate result,
half-open window edges (`end == lo`,
`end == hi`), a DST transition day (`TZ=America/Los_Angeles`, 2026-11-01),
and both agents in one tree so line order across agents and kinds is pinned.

### Agreement on a frozen snapshot (task 7)

Live transcripts change between two runs, so the correctness gate runs on a
snapshot. The planner copies, with `cp -p` and the layout kept, every Claude
Code and Codex JSONL file modified at or after `from − 1 day` into a tree in
the planner's private scratchpad (not `$SCRATCH`, which a reviewer seat can
read), makes it read-only, and runs both programs with `VIBRA_HOME=<tree>`,
the same `TZ` and the same `--from/--to`. The diff must be empty, with no
exceptions. A live run is recorded as a supplementary diagnostic only. The
snapshot is never committed or sent anywhere, and is deleted after the run.

### Pilot write-up (task 7)

`docs/research/2026-11-12/wait-pilot.md`: the frozen-window output of both
implementations, the agreement result, the method and limits (n=1, one
machine, auto mode, and every item in "Known limits"), blocked minutes with
and without over-cap waits, which tag-led prompts still pass History after
task 3 (and that the origin of the Claude-style tags in Codex was not
established), and what it says about a UI surface. Every
number in it comes from the command output quoted there.

### Notifications on/off protocol (task 9, owner, after merge)

Vibra keeps running in both weeks and only its banners change, so the
menu-bar state stays a cue in both. By design only Vibra's banners differ.
Not controlled: workload and which projects are active, the order of the
weeks, and other cues that stay on (Claude Code's and Codex's own
notifications, terminal bells, Orca's cards). Two sequential weeks cannot
separate the banner's effect from these; the comparison is descriptive.

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
| 2 | planner | Oracle first: `tools/wait-oracle/wait_oracle.py` implements the spec from the transcripts directly (its own History rule, including the task 3 change; reads `VIBRA_HOME`, `TZ`, `VIBRA_NOW` like Vibra), `oracle_selftest.py`, and the shared fixtures with their hand-written expected outputs | — | `oracle_selftest.py` passes every shared scenario byte for byte, plus unit cases for each rule bullet; a mutation of each of: the same-response rule, the automation-turn rule, the human-command rule, result consumption, the `isMeta` skip, the half-open window, the cap boundary, fails it (recorded); the sentinel scenario prints no sentinel |
| 3 | deepseek | History changes: Codex subagent sessions unattended; the wrapper-tag additions; `codexSourceIsSubagent` and `codexTurnIsAutomation` extracted, with `CodexCheckpoint` calling them | 1 | `QueryAndHistoryTests`: a `source: {"subagent": {"other": "guardian"}}` session and a `thread_spawn` session yield no questions; `source: "cli"` and `"vscode"` still do; the decision is taken from the first `session_meta` and survives a later `session_meta` and a batch split between the meta record and the prompts; each added tag, as the whole block, yields no question (Claude and Codex), and the same tag mid-text does not drop typed text; existing `CodexAdapterTests` for subagent and automation sessions pass unchanged; `realtime_delegation` still yields a question; `make test` green. Then the planner reruns `wait_rule_probe.py` with both lists as shipped and records how many tag-led prompts still pass History |
| 4 | deepseek | `ClaudeWaitExtractor` and `CodexWaitExtractor` per spec; adapters return them | 1, 3 | `WaitExtractorTests` (synthetic records): turn wait end_turn → prompt; one response as several records (text then tool_use with the same `message.id`, or several end_turn blocks) opens once at the last end_turn block; a new response id after end_turn clears; a wrapper-only user record (`<task-notification>`) is not a prompt; `isMeta`, sidechain and timestamp-less records change nothing; timestamp `ms` from the string (`.5`, `.123456`, `+02:00` offset); dispatch prompt clears and its turn opens nothing; a human prompt after a dispatched turn re-arms; a slash command in both forms (`<command-name>` first, and `<command-message>` first with a `<command-name>` element after it) and a `!` run (`<bash-input>`) close an open wait and are not questions; a `<local-command-stdout>` record does not close it; a Codex `<user_shell_command>` closes it; a Codex automation `task_started` clears an open wait and its prompt and `task_complete` open nothing; the sequence automation `task_started` → `task_complete` → user `task_started` → human prompt → `task_complete` → human prompt gives exactly one turn wait (from the second `task_complete`) and the session is eligible; the same with `turn_aborted` ending the automation turn; a transcript whose only prompts are dispatches yields an empty fold even with an `AskUserQuestion` answered in it; a tool_use id repeated after its result consumed it, then a second result, yields one wait; a `<task-notification>` after end_turn followed by agent records and a new end_turn starts the wait at the later end_turn; `stop_sequence` and `max_tokens` turn ends open nothing; a user record with two `tool_result` blocks gives two waits with the same answer; an `AskUserQuestion` and a user-approved `Bash` inside a dispatched turn still count; question waits with accept, reject and no decision; `Bash` with `source: user_temporary` an approval, with `source: config` nothing; two tool_use blocks answered separately give two waits; a repeated tool_use id keeps its first time; a duplicate result yields nothing; an unknown `tool_use_id` gives nothing; open final wait sets `openSince`; a source with no human prompt gives an empty fold; Codex task_complete → prompt; `turn_aborted` clears; a `function_call`, `reasoning` or assistant `message` after task_complete clears; `item_completed` and `task_started` do not clear; `codex_exec` and subagent sessions empty; `make test` green |
| 5 | deepseek | `WaitStats.format` per "Window and arithmetic" and "Output"; `--wait-stats` prints it | 4, 2 | `WaitStatsTests`: every shared fixture scenario byte for byte (run through `WaitIngest` with the fixture tree and an injected time zone); quantiles for n = 1, 2, 4, 5 against hand-computed values; floor printing; cap and over_cap at exactly 7,200,000 ms (not over) and 7,200,001 (over); union of overlapping, touching and nested intervals; `scope=within_cap` leaves an over-cap wait out; a session with no waits counts as 0; window membership by `end`; a session in the window by a human event or a wait in it (a session with only a dialog answer in the window counts); both half-open edges; ordinal assigned before the window filter; bucket boundaries 1, 2, 3, 4, 7, 8; line order and omission of n=0 lines; empty output; `make test` green |
| 6 | deepseek | Privacy canary `waitSentinelsNeverLeak`; Makefile `CANARIES` | 4, 5 | The canary passes; the planner's mutation run (the stats line includes the session id; the extractor keeps the prompt text in an output field) turns it red, recorded here |
| 7 | planner | Agreement on a frozen snapshot, then the pilot write-up `wait-pilot.md` | 5, 2 | On the snapshot ("Agreement on a frozen snapshot"), `diff <(VIBRA_HOME=<tree> Vibra --wait-stats --from 2026-10-14 --to 2026-11-12) <(VIBRA_HOME=<tree> wait_oracle.py --from 2026-10-14 --to 2026-11-12)` is empty under the same `TZ`. Any difference is a defect, fixed in whichever disagrees with the spec, and gains a shared fixture. The live run is recorded beside it as a diagnostic |
| 8 | planner | Docs: CHANGELOG, `docs/features.md` (`--wait-stats`, definitions, limits), `docs/privacy.md` (what is read), `plan/STATUS.md`, CHANGELOG states the History change in user terms, literature report direction C gains a "Status" line pointing at the pilot | 7 | `tools/readme-anchors.sh` exits 0; every number in new text names its command output in `wait-pilot.md` |
| 9 | owner, then planner | Notifications on/off protocol | merge | Both weeks' outputs recorded here; gates nothing in this run |

## File ownership

- **planner:** `Sources/VibraCore/Waits/HumanWait.swift`,
  `Sources/VibraCore/Waits/WaitIngest.swift`,
  `Sources/VibraCore/Adapters/AgentAdapter.swift`, `Sources/VibraApp/main.swift`
  (task 1, then the `--wait-stats` print line goes to deepseek in task 5);
  `tools/wait-oracle/*`, `Tests/VibraCoreTests/Fixtures/waits/*` (task 2;
  read-only for deepseek); this plan; `docs/research/2026-11-12/*`;
  `CHANGELOG.md`, `docs/features.md`, `docs/privacy.md`, `plan/STATUS.md`.
- **deepseek:** `Sources/VibraCore/History/QuestionRecord.swift` (task 3 only);
  `Tests/VibraCoreTests/CodexAdapterTests.swift` (task 3, only if a moved
  predicate needs a new test);
  `Sources/VibraCore/Waits/WaitExtractors.swift`,
  `Sources/VibraCore/Waits/WaitStats.swift`,
  `Sources/VibraCore/Adapters/ClaudeCodeAdapter.swift` (the `waitExtractor()`
  line only), `Sources/VibraCore/Adapters/CodexAdapter.swift` (task 3: the two
  predicates and `CodexCheckpoint` calling them; task 4: the `waitExtractor()`
  line); `Sources/VibraApp/main.swift` (task 5, the print line only);
  `Tests/VibraCoreTests/QueryAndHistoryTests.swift`,
  `Tests/VibraCoreTests/WaitExtractorTests.swift`,
  `Tests/VibraCoreTests/WaitStatsTests.swift`,
  `Tests/VibraCoreTests/WaitPrivacyTests.swift`; `Makefile` (task 6, the
  `CANARIES` line only).
- One shared working tree. DeepSeek tasks run one at a time in the order 3, 4,
  5, 6; task 3 starts after task 1 is committed, task 4 after task 2's selftest
  passes and the shared fixtures are committed. Nothing in `tools/wait-oracle/` changes while a review round is
  open.

## Round-1 objections → changes

| Objection (who) | Change |
|---|---|
| Dispatch suppresses only turn waits, so a question or approval inside dispatched work is counted (sol 1) | **Disagree, kept as is, with a test.** A Claude Code seat's question or permission dialog blocks until a person answers it; the fleet skills send those dialogs to the human. Only the seat's turn end is read by the planner. Spec text added under "Claude Code waits"; task 4 pins an `AskUserQuestion` and a user-approved `Bash` inside a dispatched turn as counted |
| One response written as several records can shorten or duplicate waits; tool uses never consumed (sol 2) | `openResponse` added: a later record of the same `message.id` never clears and moves `open` to its own end_turn block; a new id is a new response. `uses` keeps the first appearance; a result consumes its id, and a duplicate result yields nothing. Task 4 and the shared fixtures cover each |
| `isMeta` and timestamp-less records have no contract; `permissionDecision` location unstated (sol 3) | New "Which records touch wait state": no valid time, `isMeta`, or sidechain → no state change; the History extractor still sees every line. `permissionDecision` named as the user record's top-level field |
| Byte-for-byte semantics incomplete: rounding ties, duration and union coordinates, window edges, time zone, date validation, final newline, ordering of the two `seconds` families (sol 4) | New "Time": ms read from the timestamp string with integer arithmetic (no parsed `Date`), so no rounding. Durations and union endpoints in those ms. Window is half-open `[lo, hi)`, local midnights by the platform calendar under `TZ`, `VIBRA_NOW` honoured; strict date regex. Sort by key (text before ` p25=`/` n=`), byte-wise; every line ends in `\n`. `blocked` fields renamed (`unit=min p25=…`) so its key sorts cleanly. Shared fixtures include half-open edges, a DST day and both agents |
| Live reads are not a frozen dataset (sol 5) | New "Agreement on a frozen snapshot": a read-only `cp -p` snapshot in the planner's private scratchpad, both programs on it through `VIBRA_HOME`, same `TZ`; the diff must be empty with no exceptions. The live run is only a diagnostic |
| "The comparison isolates the notification" overclaims (sol 6) | Replaced by: two sequential uncontrolled weeks cannot separate the notification from workload or order; the comparison is descriptive |
| Non-blocking: first `session_meta` decision should survive later metadata and chunking (sol) | Folded into task 3's acceptance |
| Non-blocking: shared synthetic fixtures for oracle and Swift (sol) | New "Shared fixtures" section; the planner writes them with the oracle in task 2 and the expected outputs by hand; task 5 runs every scenario in Swift |
| Codex automation turns ignored; the repo already has the rule in `CodexCheckpoint` (claude 1) | New Codex rule on `task_started`: an automation turn clears `open`, sets `dispatched`, and its History records are dispatch prompts. `codexTurnIsAutomation` (and `codexSourceIsSubagent`) are extracted from `CodexCheckpoint` and shared by it, History and the wait extractor (task 3). Task 4 pins the automation cases. Measured: 18 automation turns in 30 days |
| The prompt rule was never measured; injected tags may end waits early; Codex record order and cross-file duplicates unmeasured (claude 2a-c) | Ran the three probes before round 2 (`wait_rule_probe.py`, `wait-rule-30d.txt`), rows added under "Local measurements". (a) Tags passing History: one Claude Code tag and seven Codex tags, all added to the wrapper lists in task 3 with tests. (b) Codex preview: 152 waits closed, 2 cleared by `turn_aborted`, 0 by agent records, 37 open. (c) Duplicates: 0 Claude Code end_turn uuids and 1 Codex prompt in two files; **no dedupe rule**: one case in 30 days, and per-source extractors have no cross-source state; written as a known limit with its count |
| Slash commands and `!` runs: the wait before them is dropped or overstated (claude 2, limit) | Rather than a limit, they now count: a **human command** (`<command-name>`, `<bash-input>`, Codex `<user_shell_command>`) closes a wait and marks the session attended, without becoming a History question. Task 4 pins it, and that `<local-command-stdout>` does not close |
| Byte agreement: window ends, timestamps, which value feeds `seconds`, `permissionDecision` location and several blocks, `uses` repeats, numbered groups (claude 3a-f) | (a, b, e) were already in v0.2 from sol 4 and sol 2. (c) `seconds` uses capped durations with over-cap at 7,200,000; `total` is the floor of summed ms. (d) Several `tool_result` blocks each take the record's one decision. (f) The output is now seven numbered groups, the two `seconds` shapes separate |
| "Isolates the notification" (claude 4) | Removed (sol 6); the uncontrolled differences are now listed by name |
| Non-blocking: blocked minutes with and without over-cap waits (claude 1) | `blocked … scope=within_cap` added; the pilot reports both |
| Non-blocking: snapshot for task 7 (claude 2) | Done (sol 5) |
| Non-blocking: oracle sentinel check (claude 3) | Added to Privacy and task 2 |
| Non-blocking: subagent files without `isSidechain` (claude 4) | Measured 0 such records; the `isSidechain` skip stays the rule, and the shared fixtures include a subagent file |
| Non-blocking: other `stop_reason` values, `<task-notification>` restarts (claude 5, 6) | In "Known limits", with counts; task 4 pins both |
| Non-blocking: share the Codex subagent predicate (claude 7); CHANGELOG in user terms (claude 8) | Both done (task 3, task 8) |

## Round-2 objections → changes

| Objection (who) | Change |
|---|---|
| History's automation exclusion was promised but not specified (sol 1) | Narrowed: History gets the subagent rule and the wrapper tags only; `codexTurnIsAutomation` is shared by `CodexCheckpoint` and the wait extractor. Measured reason History needs no automation state: all 18 automation prompts arrive wrapped in `<heartbeat>`, now a wrapper. CHANGELOG wording changed to match |
| `automation` never resets, contradicting the re-arm test (sol 2) | `automation` now ends at the turn's `task_complete` or `turn_aborted`; the record order the rule relies on (a turn's prompt after its `task_started`) measured with 0 exceptions. Task 4 pins the full automation → human sequence and the aborted variant with the expected single wait |
| Eligibility drops the fleet dialogs the disagreement says stay counted; dialog answers do not make a session attended (sol 3) | Scope made explicit: a source is eligible with a human prompt anywhere; an eligible source is a session in the window when it has a human event **or a wait** there, and all its in-window waits count. Dispatch-only seat transcripts are not eligible, stated as a known limit with its measured size (4 transcripts, 6 dialogs in 30 days). Fixtures for both cases |
| Non-blocking: the Codex preview was not a v0.3 fold (sol) | The probe now folds Codex under the v0.4 rules and wrapper list; the row is relabelled and its numbers replaced |
| Non-blocking: repeated id after consumption plus a duplicate result (sol) | Added to the shared fixtures and to task 4 |
| Claude Code human command matched only a leading `<command-name>`, missing custom commands and skills written `<command-message>` first (claude r2 1) | Measured (`command-records-30d.txt`): 100 `<command-name>`-first and 63 `<command-message>`-first records, all 163 carrying a `<command-name>` element. The rule now matches a record that contains that element, or starts with `<bash-input>`. Task 4 and the fixtures cover both forms |
| Non-blocking: name the source set (claude r2 1) | Spec names it: `adapter.sources()` `.jsonl` paths; Codex only `rollout-*.jsonl`. A non-`rollout-` Codex file joins the fixtures |
| Non-blocking: rerun the tag census after task 3 (claude r2 2) | Added to task 3's acceptance as a planner step |
| Non-blocking: origin of Claude-style tags in Codex unknown; `realtime_delegation` is the person (claude r2 3) | `realtime_delegation` removed from the wrapper additions and pinned as a question; the write-up states the other tags' origin was not established |
| Non-blocking: more limits; precedence; fleet-seat sentence (claude r2 4-6) | Added to "Known limits"; one human event when a record is both; a Codex `<user_shell_command>` counts only outside an automation turn; the fleet-seat case is stated under eligibility (also sol r2 3) |

## Round-3 objections → changes

| Objection (who) | Change |
|---|---|
| A dispatch containing a `<command-name>` element is both a dispatch and a human command (sol r3 1) | Classification made exclusive: a record that yields a History record is a dispatch prompt or else a human prompt; only a record that yields no History record can be a human command. Shared fixture added for the dispatch-with-command case |
| Non-blocking: the probe kept `realtime_delegation` as a wrapper and skipped command closure (sol r3) | Probe corrected (`realtime_delegation` stays a prompt; a Codex `<user_shell_command>` closes a wait) and rerun; the preview row's numbers replaced |
| Non-blocking: Privacy said only the leading tag is read (sol r3) | Reworded to what is searched: a `<command-name>` element and a leading `<bash-input>`, or one whole `<user_shell_command>` block |
| Non-blocking: a record that only quotes `<command-name>` would count as a command (claude r3 1) | The record must also start with `<command-name>` or `<command-message>` (163 of 163 measured do) |
| Non-blocking: task 5 still said "attended by prompt" (claude r3 2) | Task 5 now names the v0.4 rule (a human event or a wait in the window) and pins the dialog-only case |
| Non-blocking: say which tag-led Codex prompts remain (claude r3 3) | The pilot write-up lists them after the task 3 rerun |


## Plan gate record

Round 4 reviewed v0.5 at `2dcedb3` (`$SCRATCH/interdiff-plan-r4.txt`).

| Round | reviewer-claude (`claude-fable-5-2`) | reviewer-sol (`us.openai.gpt-6.1-sol`) |
|---|---|---|
| 1 (v0.1 `fe32277`) | PLAN-REJECTED, 4 blocking | PLAN-REJECTED, 6 blocking |
| 2 (v0.3 `52ed678`) | PLAN-REJECTED, 1 blocking | PLAN-REJECTED, 3 blocking |
| 3 (v0.4 `15a651b`) | PLAN-APPROVED | PLAN-REJECTED, 1 blocking |
| 4 (v0.5 `2dcedb3`) | **PLAN-APPROVED** (`$SCRATCH/claude-plan-r4.md`) | **PLAN-APPROVED** (`$SCRATCH/sol-plan-r4.md`) |

Sol spend for the four plan rounds: USD 0.062, 0.108, 0.100, 0.0925 (from
each call's returned usage, `$SCRATCH/sol-plan-r*.log`). reviewer-claude ran
in auto permission mode from round 1 on (chosen at its first permission
dialog); `git status` after every round showed no change by it.

Round-4 non-blocking notes, carried into implementation, changing no rule,
test or acceptance in the approved plan:

- Shared fixtures gain a wrapper-only notification that quotes a
  `<command-name>` element after its leading tag (no command) (sol 1).
- At task 7 the probe counts `<user_shell_command>` closures separately, and
  the execution record corrects the preview row's "3 of them by a
  `<user_shell_command>`" to what it measures (sol 2).
- Preview rows quote an earlier run of the live probe (for example the
  stop-reason row says `tool_use` 43,435 and `end_turn` 2,934). They are
  previews; task 7's snapshot governs every reported number, and the pilot
  write-up quotes only its own outputs (claude 1).

PLANNER (claude): PLAN-APPROVED, plan v0.5 at `2dcedb3`. Both reviewers'
literal approvals were read in their reply files.
