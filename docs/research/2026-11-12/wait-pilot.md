# Minutes agents waited on the human: n=1 pilot (direction C)

Date 2026-11-13. Plan: `docs/PLAN-2026-11-13-wait-minutes.md` (task 7).
This is one person's machine over one month, in Claude Code auto mode. It is
a pilot measurement, not a result about anyone else.

## Method

- Command: `Vibra --wait-stats --from 2026-10-14 --to 2026-11-12`, local time
  zone `America/Los_Angeles` (the window includes the 2026-11-01 clock change,
  so it is 30 calendar days and 721 hours).
- Input: a read-only snapshot of the owner's Claude Code and Codex
  transcripts (every `.jsonl` under `.claude/projects` and every
  `rollout-*.jsonl` under `.codex/sessions` modified since 2026-10-12), 950
  files, 2,479,108 KB on disk, copied with `cp -p` into the planner's private
  scratchpad, read through `VIBRA_HOME`, deleted after the run. Nothing from
  it is committed or was sent anywhere.
- Definitions: the plan's specification. In short, a **turn** wait runs from
  the agent's end of turn to the person's next prompt or slash command; a
  **question** wait from an `AskUserQuestion` call to its answer; an
  **approval** wait from a tool call to its result when the person decided it.
  Each wait is capped at 2 h. **Blocked** minutes are the union of a
  session's capped waits; `scope=within_cap` leaves out waits longer than 2 h.

## Agreement (the correctness gate)

The Swift build (`e3b6540`) and the independent Python oracle
(`tools/wait-oracle/wait_oracle.py`) were run on the same snapshot, the same
window and the same time zone, in both orders.

| Run | Result |
|---|---|
| Swift then oracle (11:23-11:25 UTC) | `diff` empty, 28 lines |
| Oracle then Swift | `diff` empty; Swift run 1 equals Swift run 2 |
| Live transcripts, same window (diagnostic only) | Swift and oracle identical; live differs from the snapshot only in `open agent=claudeCode` (84 vs 85), the one line the plan expected to move while a session is still live |

Swift read 2,553,757,292 bytes in 82.61 s on the snapshot. The oracle took
about 6 s on the same input (wall clock between its start and end stamps).
The gap is a measured cost of the Swift path; its cause is not measured here
(inferred: each line is parsed as JSON twice, once for the History extractor
and once for the wait rules, and the History wrapper regexes are compiled per
call).

Supporting evidence: the oracle and the Swift tests pass the same eight
hand-derived fixture scenarios byte for byte (`oracle_selftest.py`,
`WaitStatsTests`, and the CLI); seven rule mutations each fail the oracle's
selftest (`pilot/oracle-mutations.txt`); the `waitSentinelsNeverLeak` canary
fails when a fold keeps prompt text or a wait keeps tool input
(`pilot/canary-mutations.txt`).

## Output

`pilot/wait-stats-2026-10-14_2026-11-12.txt`, verbatim:

```
sessions agent=claudeCode n=101
sessions agent=codex n=22
open agent=claudeCode n=84
open agent=codex n=19
waits agent=claudeCode kind=approval answer=accept n=8
waits agent=claudeCode kind=question answer=accept n=44
waits agent=claudeCode kind=question answer=reject n=7
waits agent=claudeCode kind=question answer=unknown n=4
waits agent=claudeCode kind=turn n=750
waits agent=codex kind=turn n=132
over_cap agent=claudeCode kind=approval n=1
over_cap agent=claudeCode kind=question n=12
over_cap agent=claudeCode kind=turn n=78
over_cap agent=codex kind=turn n=25
seconds agent=claudeCode kind=approval p25=43 p50=60 p75=186 n=8
seconds agent=claudeCode kind=question p25=57 p50=597 p75=5951 n=55
seconds agent=claudeCode kind=turn p25=157 p50=606 p75=3264 n=750
seconds agent=codex kind=turn p25=20 p50=332 p75=3722 n=132
seconds agent=claudeCode kind=approval ordinal=1 p25=50 p50=69 p75=504 n=5
seconds agent=claudeCode kind=approval ordinal=2-3 p25=29 p50=52 p75=66 n=3
seconds agent=claudeCode kind=question ordinal=1 p25=59 p50=497 p75=3095 n=28
seconds agent=claudeCode kind=question ordinal=2-3 p25=55 p50=1079 p75=7200 n=15
seconds agent=claudeCode kind=question ordinal=4-7 p25=46 p50=381 p75=1607 n=8
seconds agent=claudeCode kind=question ordinal=8+ p25=319 p50=1977 p75=4074 n=4
blocked agent=claudeCode scope=all unit=min p25=17 p50=121 p75=283 total=24792 n=101
blocked agent=claudeCode scope=within_cap unit=min p25=13 p50=70 p75=178 total=13872 n=101
blocked agent=codex scope=all unit=min p25=0 p50=0 p75=120 total=4555 n=22
blocked agent=codex scope=within_cap unit=min p25=0 p50=0 p75=0 total=1555 n=22
```

## Readings

Each line below is arithmetic on the output above, or labelled.

1. **A finished Claude Code turn waited a median of 10 minutes** (606 s,
   IQR 157-3,264 s, 750 waits in 101 sessions). Codex: median 332 s, IQR
   20-3,722 s, 132 waits in 22 sessions.
2. **The 2 h cap carries much of the total.** Claude Code: 10,920 of 24,792
   blocked minutes (44%) come from the 91 waits over 2 h; Codex: 3,000 of
   4,555 (66%). The within-cap median per Claude Code session is 70 min
   (IQR 13-178). Any headline figure depends on the cap, so it would need to
   show `within_cap` or say what the cap is.
3. **Most sessions end waiting.** 84 of 101 Claude Code sessions and 19 of 22
   Codex sessions end on a turn wait that was never closed; those final waits
   are not counted.
4. **Approvals are rare here, questions are not.** 8 human-decided approvals
   in 30 days (auto mode), against 55 `AskUserQuestion` answers (median 597 s,
   12 over 2 h). An approval median of 60 s includes the tool's own run time.
5. **No habituation curve can be read from this.** Question medians by
   ordinal are 497 s (1st, n=28), 1,079 s (2nd-3rd, n=15), 381 s (4th-7th,
   n=8), 1,977 s (8th and later, n=4): no monotone trend, and the later
   buckets are too small to separate from noise.
6. **Why 101, not the plan preview's 221.** The preview counted any
   transcript with a typed-looking prompt. On the snapshot, 118 of those are
   `sdk-cli` (unattended `claude -p`) runs and 105 are interactive
   (`probe/session-kinds-snapshot.txt`); History, and so this metric,
   excludes the unattended ones. Which rule leaves out the other 4 of 105
   (no human event or wait inside the window, or only text History drops)
   was not measured.

## What is left unmeasured or uncertain

- Every item in the plan's "Known limits": approval waits include tool run
  time; open final waits are not counted; non-`end_turn` stop reasons open no
  wait; a resumed or forked transcript can count twice (one Codex prompt in
  30 days); minutes overlap in wall time across sessions; dispatch-only fleet
  seats and slash-command-only sessions are not eligible.
- Tag-led prompts that still pass History after task 3
  (`probe/wait-rule-after-task3-30d.txt`): Claude Code 1
  (`artifact-content-authored-by-others`, a block whose element is not a
  whole wrapper), Codex 2 `command-message` and 2 `command-name` (tag-led
  with text after the element), and 2 `realtime_delegation` (kept on purpose:
  the person speaking). Whether the Claude-style tags seen in Codex prompts
  were injected or pasted by the person was not established.
- Whether Vibra's banners were allowed during this month is not recorded.

## What it says about a UI surface (planner's reading)

A per-session "minutes waited" figure is dominated by long idle waits and by
sessions that end waiting, so on its own it mostly measures how many sessions
a person leaves open. A useful surface would need the within-cap figure and a
plain statement of the cap. The menu already shows how long a session has
been waiting now. The next step is the notifications on/off protocol (plan
task 9), which uses this command unchanged; a surface is decided after it.
