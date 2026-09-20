# vibra roadmap

Closing the gap to the paid competitor, in the order that actually matters.

Built independently from public feature descriptions and from the agents' own
on-disk formats. No decompilation, no copied code or assets.

Reviewed 2026-09-20 by a DeepSeek seat and a Codex seat. Both rejected the
first draft; what follows is the revision. Their objections are recorded inline
because the reasoning matters more than the conclusion.

## Measured baseline, 2026-09-20

Numbers from the running app on a Mac mini (M4), not estimates:

| Metric | vibra today | Competitor claim |
|---|---|---|
| Idle CPU | **~97% sustained** | "minimal" |
| RSS | **626 MB** after 10h | "< 50 MB" |
| Agents supported | 3 | 25 |
| Bundle size | 516 KB | — |
| Signing | ad-hoc | Developer ID |

The CPU and memory figures are the story. Everything else waits.

---

## Phase 0 — Correctness and cost

**Blocks Phase 1.** An app pinning a core is broken, and features built on it
are sand.

### P0.1 — Stop re-parsing the world every 2 seconds

`SessionStore` polls on a 2.0s timer and each refresh fully re-parses **488
JSONL files totalling 339 MB** — roughly 170 GB/min of redundant work.

The first draft claimed "the fix largely exists already, `FileWatcher` just
needs wiring." **Both reviewers rejected that as false**, and they were right.
Verified in-tree:

- `FileWatcher` is referenced nowhere outside its own file.
- `JSONLIncrementalReader` is orphaned — no adapter consumes it.
- All three adapters full-parse; `ClaudeCodeAdapter.swift:177` reads whole
  files with `String(contentsOf:)`.
- `SessionStore` has no dirty/changed-file set.

`FileWatcher` solves change *triggering* only. The parsing half does not exist.

Scope, explicitly:

1. A dirty-file set in `SessionStore`, fed by `FileWatcher`.
2. Streaming parse in all three adapters (shared with P0.2).
3. Per-session summary cache keyed by file, so unchanged files cost nothing.
4. A decision on per-file byte-offset accumulation. `AgentAdapter.discoverSessions()`
   is a *full-parse contract*; true incremental reads need that contract
   changed. Decide before implementing, don't discover it midway.
5. Recovery paths: startup, truncation, file replacement, and dropped FSEvents
   all rebuild cache state. FSEvents coalesces and is advisory.

Keep a slow safety-net rescan (~60s) for missed events.

**AC:** idle CPU < 2% and RSS < 60 MB over 10 minutes against the same 488-file
corpus; a regression test asserting a second refresh with no file changes reads
zero bytes.

### P0.2 — Bounded-memory parsing

626 MB RSS traces to `String(contentsOf:)` loading entire files.

The first draft proposed "read tail-first and stop once the session summary is
known." **DeepSeek rejected the mechanism as a correctness regression, and
verified it against the code:** `ClaudeCodeAdapter` accumulates `usage +=`
across *every* `assistant` record. Stopping early produces wrong token totals,
and therefore wrong costs — which P1.3 then reports as fact. Tail-first is not
a faster version of the right answer; it is the wrong answer.

Correct mechanism: stream each file top-to-bottom, line by line, with bounded
memory, accumulating usage as it goes. Replace `String(contentsOf:)` in
`readLines` with a line iterator.

**AC:** RSS flat across 1000 refreshes; token totals byte-identical to today's
full-parse output on the real corpus.

### P0.3 — ~~Read the OpenCode permission column~~ (already done)

Cut. **Both reviewers independently flagged this as already implemented**, and
they were right — `OpenCodeAdapter` selects `permission` and maps non-empty to
`.permissionPrompt`, with a passing test. The README claiming otherwise was
wrong; the code was fine. Fixed.

What remains is a *verification* task, not implementation: confirm OpenCode
actually writes that column when it parks on an approval prompt. One real
session on this machine carries a 172-character permission value, which is
evidence it does, but the transition has not been observed live.

---

## Phase 0b — Runs in parallel, blocks nothing

### P0b.1 — Make `Notifier` testable — **DONE 2026-09-20**

Split in two. `AttentionNotifier` in `VibraCore` owns every decision —
transition detection and debounce — and takes its clock as a parameter, so the
rules are exercised without a signed bundle, user authorization, or waiting a
real minute. `UserNotificationSink` in `VibraApp` only delivers, and contains
no decisions, because it is the part a test genuinely cannot drive: macOS
silently drops whatever it will not show.

10 tests cover it. Both rules were mutation-tested — removing the debounce and
removing the transition check each make the suite fail — because a test that
cannot fail is worse than no test.

---

## Phase 1 — The features users notice

### P1.1 — Terminal jump-back

Click a session row, focus the terminal tab it runs in.

**cwd is not identity.** Both reviewers rejected a cwd-based match, with a
live counterexample on this machine: a Codex session and an OpenCode session
were both in `~/workplace/vibra` simultaneously.

Correlate on **controlling TTY**. Two agents sharing a directory have different
ptys. Enumerate agent processes (pid, cwd, tty, start time) and match against
terminal-reported ttys — iTerm2 and Terminal.app both expose tty via
AppleScript.

The gap to solve: no JSONL record carries a pid or tty, so a session-to-process
link is still needed. Use cwd plus start-time ≈ `startedAt`, and the session id
if a CLI exposes it in argv or env. **When ambiguous, show all candidate tabs
rather than guessing** — a jump to the wrong tab is worse than no jump.

VS Code's integrated terminal exposes no queryable tty. Handle separately or
skip in v1.

**AC:** correct tab focused for iTerm2 *and* Terminal.app, including the
two-agents-in-one-directory case; ambiguity surfaces a chooser, never a guess.

### P1.2 — Usage figures: local only, no network

The competitor calls official usage APIs with locally-stored tokens to show
real subscription quota. vibra will not.

Both reviewers rejected the draft's opt-in-network option. Codex: an opt-in API
call still makes an absolute "zero egress" claim false, so the promise must
change *before* the feature, not alongside it. DeepSeek: zero-egress is vibra's
entire trust story and its only real differentiator, and a token-bearing egress
path — even off by default — is a permanently different security posture.

Decision: keep computing value locally from token counts, labelled **"estimated
API-equivalent value"**, never presented as a subscription quota. `UsageAggregator`
already does this. If a real subscription read is ever wanted, it ships as a
separate clearly-labelled tool, not in vibra core.

### P1.3 — Weekly report card

Tokens, API-equivalent value, per-agent split, day and week rollups.
`UsageAggregator` already computes the rollups; this is presentation.

**Depends on P0.2** — a report built on wrong token totals is worse than none.

**AC:** report reachable from the menu, numbers matching `make probe`.

---

## Phase 2 — Breadth

### P2.1 — Auto-detect installed agents

`AdapterRegistry` hardcodes three. Detect what has state on disk and show only
that.

### P2.2 — More adapters

Each is one file implementing the existing `AgentAdapter` protocol; the
architecture already supports this. Order by evidence of local use — on this
machine `hermes` and `~/.cursor` are present, so those precede agents nobody
here runs.

Candidates: Gemini CLI, Cursor, Amp, Hermes, Droid, Qwen, Kimi.

**AC per adapter:** fixture-based test, built without reading the user's real
session data.

---

## Phase 3 — Distribution

### P3.1 — Developer ID signing and notarization

Currently ad-hoc signed, so macOS refuses notification authorization until the
user enables it by hand in System Settings. Requires a paid Apple Developer
account — **a user decision, not a code change.**

### P3.2 — Sparkle auto-update with EdDSA signature verification

### P3.3 — Homebrew cask

---

## Explicitly not doing

- **Approving agent permission prompts from the menu bar.** The competitor
  offers it. It converts a passive read-only monitor into something that can
  approve tool calls — a materially different security posture that
  contradicts the read-only contract every adapter is built on. The value of a
  monitor you can trust to be *only* a monitor is worth more than the
  convenience.
- **A Windows port.**
