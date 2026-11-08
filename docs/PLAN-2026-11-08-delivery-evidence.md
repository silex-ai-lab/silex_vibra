# Plan: feature review and Delivery Evidence Lite

Status: approved by the owner on 2026-11-08, including the privacy change in
section 5.
Base: `main` at `c47e90d`.

## 1. What this plan decides

A product proposal describes Vibra's next stage as "unified observation and
delivery verification" for coding agents. This plan checks that proposal against
the code, the written product boundaries and local transcript data. It then
picks one feature to build.

The pick is **Delivery Evidence Lite**. The Session Details window gains one
row that answers one question: since this session last changed code, did Vibra
see a test, build or lint command, and what did it return?

## 2. Review of the proposed features

| Proposed | State in Vibra | Decision |
|---|---|---|
| P0 agent ingest and health | Done. Six adapters, per-source health | Keep |
| P0 global workbench | Partly. Three sections exist, no repo or worktree grouping | Backlog B6 |
| P0 execution timeline | Partly. Claude Code only, tool names only, first 60 events | Backlog B3 |
| P0 multi-agent relationships | Missing. Data exists in both agents | Backlog B5 |
| P0 code change linkage | Partly. Branch only, Codex always reports none | Backlog B1, B8 |
| P0 verification evidence | Missing | **Picked, narrowed** |
| P0 anomaly alerts | Partly. Stalled state only | Backlog B7, after the pick |
| P0 cost and time | Done. Usage Report and suggestions | Keep |
| P0 local data control | Done, stronger than proposed. Four settings persist and nothing else | Retention and export have nothing to act on |
| P1 GitHub issue, PR and CI | Conflicts with ROADMAP P1.2, no network even opt-in | Not without changing that promise |
| P1 component map | No data source in Vibra | Decline. Agenttrail's ground |
| P1 verification gap detection | Same data as the pick | Merged into the pick |
| P1 collaboration risk | Feasible once edits are extracted | Backlog B9 |
| P1 history search and MCP | Search and `--query` exist | Decline MCP. It adds a server |
| P1 config comparison | Needs outcome labels nobody records | Decline |
| P2 pause, cancel, approve | ROADMAP "Explicitly not doing" | Decline |
| P2 failure regression cases | Different product | Decline |
| P2 team governance | Conflicts with no network | Decline |
| P2 eBPF system evidence | Linux only, Vibra is macOS only | Decline |

Three parts of the proposal are declined as a whole.

- A database of Task, Run, Change and Verification objects. Vibra's promise is
  that it stores nothing. On-demand derivation has served Report and History.
- Adopting agtrace, agento11y, Langfuse or similar as dependencies. Package.swift
  has none, and the proposal itself says the combination is unverified.
- Three new product pages. The Details window already exists.

All ten cited repositories exist and were pushed recently, checked with `gh` on
2026-11-08. Their README claims and licenses were not verified.

## 3. Measurements behind the pick

Source is this Mac, transcripts modified in the last 14 days. The probes print
counts only. They sit outside the repository and become `tools/evidence-oracle`
in step 1.

**Claude Code hides exit status almost every time.** Of 616 test, build or lint
commands with a recorded result, 602 (97.7%) pipe into `tail` or `grep`, use
`||`, or are followed by other commands. `is_error` then reports the last
command in the line and says nothing about the test run. A feature that reads
exit status alone would show these as green. This is the proposal's main trap.

**Codex records exit status on every command.** All 4597 `CommandExecution`
items carry an integer `exit_code`. Of 48 check commands, 38 are unmasked.

**A runner's own summary line is usable and errs safely.** On 61 commands whose
exit status is known, a small text classifier said passed 23 times and every
one exited 0. It said failed 4 times and every one exited non-zero. It stayed
undecided on 34, including 12 of the 16 real failures. That is zero wrong
verdicts in 27, a small sample, and those 61 commands may not represent the
masked ones. On the 602 masked Claude commands it decides 339 and leaves 258
undecided. The other 5 reported `is_error`.

**The gap is common, and its precision is unmeasured.** 24 root sessions edited
code. 8 had no check command, 6 changed code after the last check, 4 ended on a
pass, and 6 ended on an undecided check. Subagent activity was excluded from
those counts, so they likely overstate the gap.

**Edits made through the shell are invisible.** 44% of Claude Bash calls match a
loose write pattern, and that pattern also matches stderr redirects, so it is
an upper bound. v1 counts only Edit, Write, MultiEdit and Codex FileChange, and
says so on screen.

## 4. Backlog

| ID | Item | Size | Evidence or dependency |
|---|---|---|---|
| **E1** | **Delivery Evidence Lite** | M | Section 3. Built by this plan |
| B1 | Codex branch from `session_meta.git.branch` | S | Present in 171 of 172 records that carry `git` |
| B2 | Subagent activity keeps the parent row alive | S | Known limit left by `387ba3f`. Inferred, not measured |
| B3 | Recent activity timeline, newest first, Codex added | M | `item_completed` records exist |
| B4 | Snooze and approval escalation | M | Improvement plan F06 |
| B5 | Parent and child agent tree | M | Codex `parent_thread_id`, Claude `subagents/` |
| B6 | Group by repo and worktree | M | Depends on B1 |
| B7 | Repeated failing check alert | S | Depends on E1 |
| B8 | Commit at check time against commit now | M | Local `git` only. Depends on E1 |
| B9 | Two live sessions editing one file | M | Depends on E1 edit extraction |
| B10 | Signing, notarization, 0.4.0 release | M | Blocked on a Developer ID certificate |

## 5. E1 design

**Boundary.** Read on demand when the Details window opens, like History. Never
on the poll path, never stored, never on `Session`. Claude Code and Codex only.
Root transcript plus that session's subagent transcripts.

**Data shape.** One enum, so a contradictory state cannot be built.

```swift
public enum CheckKind: String, Sendable { case test, build, lint }
public enum CheckProof: Sendable, Equatable { case exitStatus, runnerSummary }
public enum CheckResult: Sendable, Equatable {
    case passed(CheckProof), failed(CheckProof), unknown
}
public struct ObservedCheck: Sendable, Equatable {
    public let at: Date, kind: CheckKind, result: CheckResult
}
public enum DeliveryEvidence: Sendable, Equatable {
    case noToolRecordsRecognized
    case noCodeChangeSeen
    case changedWithoutCheck(lastChange: Date)
    case changedAfterLastCheck(lastChange: Date, check: ObservedCheck)
    case checkedAfterLastChange(ObservedCheck)
}
```

**Rules.**

- A non-zero exit visible to Vibra is always `failed(.exitStatus)`.
- Exit 0 counts as `passed(.exitStatus)` only when the check is the whole
  command, or `pipefail` is set.
- Otherwise read the last 6 KB of output through a runner summary table. No
  match is `unknown`, and `unknown` is never rounded up.
- Documentation edits (`.md`, `.txt`, images) do not count as code changes.

**Wording.** The row states what was seen and never says "done" or "verified".
For example, "Code changed 12 min ago. No test, build or lint command seen
since." or "Tests ran after the last code change. Result not visible, output
was piped." The row ends with the limit, "Edits made through shell commands are
not counted."

**Privacy, the one boundary this changes.** Vibra today never reads tool inputs
or results for suggestions, and History reads tool names only. E1 reads command
text, file extensions and the last 6 KB of check output in memory, maps them to
the enums above and drops them. A canary test covers it.

## 6. Execution steps

Each step ends in a check and a commit on `feat/delivery-evidence`, cut from
`main`.

- [ ] 1. Move the probes to `tools/evidence-oracle`, content-free and rerunnable.
      Check: prints the section 3 counts.
- [ ] 2. Failing tests first, then `CommandClassifier` and `RunnerSummary`, both
      pure. Check: `swift test | tail` is never exit-proven, and a full failure
      table for swift, XCTest, pytest, cargo, go, vitest and jest.
- [ ] 3. `DeliveryEvidence.build(events)`, pure. Check: one test per case and
      ordering at equal timestamps.
- [ ] 4. `EvidenceExtractor` for both adapters, mirroring `historyExtractor()`.
      Pairing survives batch boundaries and duplicate `tool_use` records. Check:
      fixtures only.
- [ ] 5. `EvidenceIngest` actor, resolving root and subagent transcripts. Check:
      fixture tree with subagents.
- [ ] 6. Canary `evidenceSentinelsNeverLeak`, added to `CANARIES` in the
      Makefile. Check: fails when a sentinel is deliberately passed through.
- [ ] 7. `--evidence-stats`, content-free. Check: Swift counts match the oracle
      on real data, and any disagreement is explained.
- [ ] 8. Details row, async with "Checking…", refreshed only when the session's
      `lastActivity` moves. Check: `--show-detail --snapshot` for real sessions.
- [ ] 9. Docs. `privacy.md`, `features.md`, `ROADMAP.md`, `CHANGELOG.md`.
- [ ] 10. Independent review of the diff, then `make install`, then the owner
      opens real sessions. Nothing is pushed without being asked.

## 7. Acceptance

1. `make test SWIFT_BUILD_SYSTEM=native` passes with all three canaries.
2. A masked check is never reported as passed on exit status. Mutation check:
   removing the masking rule makes a test fail.
3. Through `--evidence-stats` on real data, no check with a known exit status
   gets the opposite verdict. Today's figure is 0 of 27 from the probe.
4. Swift and oracle counts agree, or each difference has a stated cause.
5. `make bench` still reports zero bytes on a warm refresh, so the poll path is
   untouched.
6. The largest real transcript (63.5 MB today) finishes in under 3 s. That
   target is a guess from the Usage Report's 62 MB in about 2 s. The window
   stays responsive meanwhile.
7. The owner opens at least one real session per reachable case and judges the
   row correct.

## 8. Out of scope and known risks

Out of scope are git diffs, commit linkage, GitHub, menu badges, notifications
and the other four agents.

- Precision of the gap is unmeasured. Work verified by another session, or by a
  script outside the runner list, reads as a gap. The row words it as what this
  session did, so it stays true.
- Whether anyone changes behavior because of this row is a product hypothesis.
  This plan tests correctness only.
- Transcript formats change. Codex 0.166 already differs from the
  `exec_command_end` form the first probe assumed. A transcript with no
  recognised tool record yields `noToolRecordsRecognized`, shown as "Vibra saw
  no tool activity it can read in this session", so a format change reads as
  unknown and never as a clean session.

## 9. Implementation rules

These settle what section 5 left open. Facts below were counted on the same 14
days of transcripts.

**Command parsing.** Claude Code gives a shell string. Codex gives
`[shell, "-lc" or "-c", script]` in 4674 of 4674 commands, so the script is the
third element. `CommandClassifier` splits the script outside quotes.

- Separators are `&&`, `||`, `;`, `|`, a lone `&` and newline. `2>&1` and `&>`
  are not separators. Text after a heredoc's first newline is ignored.
- A segment is a check only when its first word, after leading `(`, `VAR=value`,
  `env`, `time`, `command`, `timeout N`, `npx`, `bunx`, `pnpm exec`, `do` and
  `then`, starts a runner in the table. The first word is compared by basename.
  A quoted `"make test"` in a commit message is not a check. After `uv run` or
  `poetry run`, any later word may start the runner, because their options can
  take values (170 real commands use this form).
- Runners. Test is `swift test`, `make test`, `make check`, `xcodebuild test`,
  `pytest`, `python[3] -m pytest`, `python[3] -m unittest`,
  `npm|pnpm|yarn|bun [run] test`, `vitest`, `jest`, `cargo test`, `go test`.
  Build is `swift build`, `make build`, other `xcodebuild`,
  `npm|pnpm|yarn|bun [run] build`, `cargo build`, `cargo check`, `go build`,
  `tsc`. Lint is `make lint`, `npm|pnpm|yarn|bun [run] lint|typecheck`,
  `cargo clippy`, `go vet`, `ruff check`, `mypy`, `eslint`.
- A check's exit status is visible when its segment is not piped, is not
  followed by `||`, and every separator after it is `&&`. `set -o pipefail`
  anywhere earlier makes a pipe visible.
- Several checks in one command report the strongest kind (test, then build,
  then lint). Exit status is visible only if it is visible for all of them.

**Result rules.**

| Exit status | Reported | Result |
|---|---|---|
| Visible, zero | any | `passed(.exitStatus)` |
| Visible, non-zero | any | `failed(.exitStatus)` |
| Masked | any | Runner summary, else `unknown` |
| No result record | none | `unknown` |

A masked non-zero status is not a failure. `swift test | grep FAIL` exits 1 when
nothing failed. A Claude Code result that begins "The user doesn't want to
proceed" means the check never ran, so it is `unknown`.

**Times.** A Claude Code event uses its `tool_use` record's timestamp. A Codex
check uses `item_completed` time minus `duration` (`secs`, `nanos`), and a Codex
change uses `item_completed` time. A code change at the same instant as a check
counts as after it.

**Which check is reported.** Among checks after the last code change, take the
latest of each kind. Any failed one wins, then test, then build, then lint.

**What counts as a code change.** A Claude Code `Edit`, `Write`, `MultiEdit` or
`NotebookEdit` whose result is not `is_error`, and a Codex `FileChange` with
status `completed`, for any changed path that is neither a documentation
extension (`md`, `mdx`, `txt`, `rst`, `png`, `jpg`, `jpeg`, `gif`, `svg`, `pdf`)
nor under `/tmp/`, `/private/tmp/`, `/var/folders/` or `/private/var/folders/`.

**Finding transcripts.** Claude Code file names equal the session id in 37 of
37. Subagents are `<session id>/subagents/*.jsonl` beside it. A Codex root's
file name ends in its id in 67 of 67. A Codex subagent's file does not contain
the root id, so `EvidenceIngest` reads the first `session_meta` of each rollout
modified since the session started and keeps those whose `session_id` matches.

**Refresh.** The Details window reads on open. While it stays open it rereads
at most once a minute, only when `lastActivity` moved, and never while a read is
running.
