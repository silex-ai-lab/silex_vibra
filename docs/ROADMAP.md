# vibra roadmap

Every step carries a **Goal**, the **Critical decisions** settled for it, and
an **Acceptance** check. Decisions are recorded with their reasoning because
the reasoning is what stays useful after the code changes.

Built independently from public feature descriptions and from the agents' own
on-disk formats. No decompilation, no copied code or assets.

Reviewed by a DeepSeek seat and a Codex seat. Where they rejected a draft, the
objection is recorded rather than quietly fixed.

Current state: see [STATUS.md](STATUS.md).

| Phase | Step | State |
|---|---|---|
| 0 | P0.1 Stop re-parsing the world | **Done** 2026-09-20 |
| 0 | P0.2 Bounded-memory parsing | **Done** 2026-09-20 |
| 0 | P0.3 OpenCode permission column | **Cut** — already implemented |
| 0b | P0b.1 Make the notifier testable | **Done** 2026-09-20 |
| 1 | P1.1 Terminal jump-back | **Done (v1)** 2026-09-20 |
| 1 | P1.2 Usage figures stay local | **Decided** — no network, ever |
| 1 | P1.3 Weekly report card | **Done** 2026-09-20 |
| 2 | P2.1 Auto-detect installed agents | Not started |
| 2 | P2.2 More adapters | Not started |
| 3 | P3.1 Developer ID signing | Blocked on a user decision |
| 3 | P3.2 Sparkle auto-update | Not started |
| 3 | P3.3 Homebrew cask | Not started |

---

# Phase 0 — Correctness and cost — **DONE**

## P0.1 — Stop re-parsing the world every 2 seconds

**Goal.** Make steady-state polling cost approximately nothing, so vibra can
run all day instead of being quit after an hour.

The app sustained ~97% CPU and 626 MB RSS. `SessionStore` polled every 2.0s and
each refresh fully re-parsed 488 JSONL files totalling 339 MB.

### Critical decisions

**Incremental parse contract, not just incremental triggering.** The first
draft claimed `FileWatcher` merely needed wiring. Both reviewers rejected that
and were right: `FileWatcher` solves change *triggering* only. Verified
in-tree — `JSONLIncrementalReader` was orphaned, every adapter full-parsed via
`String(contentsOf:)`, and `SessionStore` had no dirty set. Adapters gained
`sources()` and `update()`, folding new records into an opaque checkpoint.

**File identity is (device, inode), not path plus (size, mtime).** *Codex.* A
transcript replaced by a different file of the same length within the same
second would otherwise look unchanged and the stale session would persist.

**OpenCode is fingerprinted across its WAL files.** *Codex.* SQLite in WAL mode
can change through `opencode.db-wal` while the main `.db` size and mtime sit
still; fingerprinting only the `.db` would make vibra permanently stale.

**Ingest runs on its own actor, off the main actor.** A full pass took 13.4s
while the timer fired every 2s, so refreshes queued faster than they drained —
that re-entrancy is what pinned a core. Concurrent requests now coalesce into
at most one extra pass rather than stacking.

**A freshness horizon, decided during implementation.** The remaining cost was
parsing all 488 transcripts to display four live sessions. Sources untouched
beyond the display window are now skipped on their mtime without being opened:
342 MB read becomes 6.9 MB. *Consequence to remember:* history older than the
horizon is never read, so P1.3 needs its own non-horizon path.

### Acceptance — met

Idle CPU < 2% (measured 0.0%) and a refresh with no changes reads zero bytes.
`make bench` asserts the zero-byte property and prints `PASS`/`FAIL`.

## P0.2 — Bounded-memory parsing

**Goal.** Stop holding whole transcripts in RAM. 626 MB traced to
`String(contentsOf:)`.

### Critical decisions

**Stream top-to-bottom; never tail-first.** *DeepSeek, rejecting the draft.*
The draft proposed reading tail-first and stopping once the summary was known.
That is a correctness regression, not an optimization: `ClaudeCodeAdapter`
accumulates `usage +=` across *every* assistant record, so stopping early
yields wrong token totals and therefore wrong costs — which P1.3 would then
report as fact.

**Drain autoreleased objects per batch.** `JSONSerialization` returns
autoreleased objects and nothing drained them, so a cold pass accumulated the
entire corpus: 880 MB resident. One `autoreleasepool` cut it to 416 MB.

**Batch size does not matter; smaller is worse.** Measured, not assumed.
2000 → 250 lines left peak RSS unchanged (416 → 419 MB) and read *more*
(342 → 365 MB), because a discarded partial chunk gets re-read. Left at 2000.

### Acceptance — met

RSS flat across refreshes; token totals identical to full-parse output, pinned
by folding-equivalence tests on both fixtures.

## P0.3 — OpenCode permission column — **CUT**

Both reviewers independently flagged this as already implemented, and they were
right: the adapter selects `permission` and maps a non-empty value to
`.permissionPrompt`, with a passing test. **The README claiming otherwise was
the defect.** Corrected.

What remains is verification, not implementation: confirm OpenCode actually
writes that column when it parks on an approval prompt. One real session
carries a 172-character permission value, which is evidence it does, but the
live transition has not been observed.

---

# Phase 0b — Testability — **DONE**

## P0b.1 — Make the notifier testable

**Goal.** The app's headline feature sat behind the least-verified code in the
project.

### Critical decisions

**Split decisions from delivery.** The problem was not missing tests but that
tests were *impossible*: the logic was welded to `UNUserNotificationCenter`,
which needs a signed bundle plus user authorization and silently drops whatever
it will not show. `AttentionNotifier` (VibraCore) owns every decision;
`UserNotificationSink` (VibraApp) only delivers.

**Inject the clock.** `notifyIfNeeded` takes `now`, so debounce is
deterministic instead of requiring a real minute to elapse.

**Mutation-test the rules.** After the `swift test` false-green episode, "39
passed" is not evidence on its own. Deleting the debounce check and deleting
the transition check each make the suite fail.

### Acceptance — met

No second notification for the same (session, state) within 60s. Debounce is
per-session and per-state: two sessions each alert, and `blocked` versus
`awaitingInput` are different events.

---

# Phase 1 — The features users notice

## P1.1 — Terminal jump-back — **DONE (v1)** 2026-09-20

**Goal.** Click a session row and land in the terminal tab that session is
running in, so the alert leads somewhere instead of just informing you.

### Critical decisions

**cwd is not identity — correlate on controlling TTY.** *Both reviewers,
independently.* A live counterexample exists on the development machine: a
Codex session and an OpenCode session occupied `~/workplace/vibra`
simultaneously. Two agents sharing a directory have different ptys, so the tty
is exactly the disambiguator.

**When ambiguous, offer a chooser — never guess.** *Codex.* Jumping to the
wrong tab is worse than not jumping, because it silently moves the user's focus
away from what they were doing.

**The session→process link turned out to need no heuristic at all.** Both
reviewers assumed cwd plus start-time matching would be required, because no
JSONL record carries a pid. Investigation found that two of the three agents
publish the link themselves:

- Claude Code writes `~/.claude/sessions/<pid>.json` containing its own pid
  *and* its sessionId.
- Codex holds an open lock at `~/.codex/thread-writer-locks/<sessionId>.lock`,
  so `lsof` yields the holder's pid.

The chain is therefore exact end to end: session id → pid → tty → tab. No
fuzzy matching anywhere. OpenCode publishes nothing comparable and is simply
not locatable, which is the correct answer rather than a guess.

**`~/.claude/sessions` also contains `<pid>.<hash>.key` secrets.** Only `*.json`
is ever enumerated, held to the same standard as the OpenCode auth tokens: a
canary test asserts key contents reach no output, and the check is
mutation-tested.

**VS Code is handled separately or not at all in v1.** *DeepSeek.* Its
integrated terminal exposes no queryable tty, so it cannot join the same
mechanism.

### Acceptance — partly met

- **Two agents in one directory: passes.** Demonstrated live — two Claude
  sessions both in `~/workplace` resolved to *different* ttys (`ttys002` and
  `ttys007`) via their published pids. A cwd match would have conflated them.
- **iTerm2: verified.** A session on a real iTerm tab focuses correctly.
- **Refuses to guess: verified.** A session on a herdr pane (`ttys009`) reports
  "no terminal owns ttys009" instead of jumping somewhere plausible.
- **Terminal.app: NOT verified.** It was not running on the test machine. The
  code path exists and is unexercised.

### Known limitation of v1

**Multiplexer panes are not jumpable.** tmux, screen and herdr own their panes'
ptys, so the emulator never sees them and there is nothing to focus. On a
machine where agents mostly run inside a multiplexer — as they do on the
development machine — jump-back will frequently be unavailable. herdr was
examined as a special case and rejected for v1: `herdr pane list` exposes no
tty, and `herdr pane focus` only moves to a *neighbouring* pane, so wiring it
up would require exactly the cwd-based guessing this step ruled out.

## P1.2 — Usage figures stay local — **DECIDED**

**Goal.** Show what usage costs without breaking the promise that makes vibra
worth trusting.

### Critical decisions

**No network egress, not even opt-in.** Both reviewers rejected the draft's
opt-in option. *Codex:* an opt-in API call still makes an absolute "zero
egress" claim false, so the promise would have to change *before* the feature,
not alongside it. *DeepSeek:* zero-egress is vibra's entire trust story and its
only real differentiator against the paid competitor; a token-bearing egress
path, even off by default, is a permanently different security posture.

**Label it honestly.** Figures are "estimated API-equivalent value", never
presented as a subscription quota. A real subscription read, if ever wanted,
ships as a separate clearly-labelled tool.

## P1.3 — Weekly report card — **DONE** 2026-09-20

**Goal.** Tokens, API-equivalent value, per-agent split, per-day rollups,
reachable from the menu bar.

### Critical decisions

**Attribute usage per record, not per session.** `byDay` grouped on
`session.lastActivity` and assigned a session's *entire* total to one day.
Sessions do span days — one here spans 2026-09-18 to 09-21 carrying 145M
tokens — so its whole dollar value would land on the last day and show zero
for the three days the work happened. Adapters now emit timestamped
`UsageSample`s and the report buckets them. *Both seats chose this.*

**Buckets are keyed by (local day, model).** Local because transcript
timestamps are UTC and bucketing by UTC silently moves evening sessions into
tomorrow. Per-model because a session can switch models mid-flight, and
pricing its whole total at whichever model happened to be last is wrong —
*a trap Codex raised that the draft had missed.*

**`Session` stays lean.** *DeepSeek.* It is the poll-path hot row, compared
and encoded every refresh; a growing per-day map on it would threaten the
idle-cost property Phase 0 recovered. Reports accumulate separately.

**On-demand read with isolated state.** A seven-day window measured 62 MB
across 35 files (~2s) — fine for an explicit action, ruinous every two
seconds. `ReportIngest` shares **no** offsets or checkpoints with
`SessionIngest`: sharing them would let opening the report consume the live
monitor's unread bytes, or let the monitor's 12-hour horizon truncate the
report. A persistent rollup cache was rejected as premature — it would
duplicate the rotation/truncation/inode machinery the checkpoints already
solve.

**Rolling last-7-days, not calendar week.** *The seats split here.* Codex
argued for local calendar weeks as stable non-overlapping buckets; DeepSeek
for rolling, since it matches the read window exactly, avoids the
Sunday-vs-Monday ambiguity, and avoids a near-empty card on Monday morning.
Rolling was chosen for v1; Codex had already allowed it as an acceptable
separate metric. A calendar week can be added later.

**Undated usage is shown, never dated.** *Codex.* OpenCode stores per-session
totals with no per-record timestamps, so its usage is real but unattributable.
It gets its own line rather than a fabricated day.

**Unknown models produce unpriced tokens, never $0.** Free and unknown must
not look alike.

**Labelling is load-bearing.** Both seats required it: "estimated
API-equivalent value", never cost, spent, bill or quota; and an explicit note
that figures are computed locally and nothing leaves the machine.

### Acceptance — met

Reachable from the menu (`Usage Report…`), and per-day figures verified
against an **independent** recomputation straight from the raw transcripts:
Sep 14–20 matched to the displayed precision on every day. Phase 0's
zero-byte warm refresh still passes, confirming the report does not disturb
the poll path.

---

# Phase 2 — Breadth

## P2.1 — Auto-detect installed agents

**Goal.** Stop hardcoding three adapters in `AdapterRegistry`; show only agents
that have state on disk.

### Critical decisions

**Detect by state on disk, not by binary on `PATH`.** An installed CLI that has
never run has nothing to show, and a removed CLI may still have transcripts
worth reading.

## P2.2 — More adapters

**Goal.** Cover the agents a user actually runs.

### Critical decisions

**Order by evidence of local use, not by the competitor's list length.**
`hermes` and `~/.cursor` are present on this machine; agents nobody here runs
come later.

**Every adapter is built against fixtures.** No adapter is developed by reading
the user's real session data — sanitized fixtures are extracted first. This is
a privacy rule and a correctness one: the exact observed schema beats a guess.

### Acceptance

Per adapter: a fixture-based test, built without reading real user data.

---

# Phase 3 — Distribution

## P3.1 — Developer ID signing and notarization

**Goal.** Make notifications work without a manual System Settings step, and
make the app distributable.

### Critical decisions

**Requires a paid Apple Developer account — a user decision, not a code
change.** Confirmed empirically: an ad-hoc signed bundle gets
`authorization granted: false` with "Notifications are not allowed for this
application". No code change substitutes for a signature.

## P3.2 — Sparkle auto-update

### Critical decisions

**Verify an EdDSA signature before installing anything.** An auto-updater is
the highest-value target in the app; an unverified one is a remote code
execution channel.

## P3.3 — Homebrew cask

Depends on P3.1: a cask distributing an unsigned bundle is hostile to users.

---

# Explicitly not doing

**Approving agent permission prompts from the menu bar.** The competitor offers
this. It converts a passive read-only monitor into something that can approve
tool calls — a materially different security posture that contradicts the
read-only contract every adapter is built on. A monitor you can trust to be
*only* a monitor is worth more than the convenience.

**A Windows port.**
