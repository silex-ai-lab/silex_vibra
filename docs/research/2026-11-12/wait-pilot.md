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
  `rollout-*.jsonl` under `.codex/sessions` modified since 2026-10-12),
  copied with `rsync -a` (times kept) into the planner's private scratchpad,
  read through `VIBRA_HOME`, deleted after the run. Nothing from it is
  committed or was sent anywhere. The run is `probe/agreement_run.sh`; its
  complete output, with file count, sizes, timings and every diff result, is
  `pilot/agreement-run.txt`.
- Definitions: the plan's specification. In short, a **turn** wait runs from
  the agent's end of turn to the person's next prompt or slash command; a
  **question** wait from an `AskUserQuestion` call to its answer; an
  **approval** wait from a tool call to its result when the person decided it.
  Each wait is capped at 2 h. **Blocked** minutes are the union of a
  session's capped waits; `scope=within_cap` leaves out waits longer than 2 h.

## Agreement (the correctness gate)

Vibra built from `b412c9a` by the run script itself and the independent
Python oracle (`tools/wait-oracle/wait_oracle.py`) ran on the same snapshot,
window and time zone, in both orders (`pilot/agreement-run.txt`, taken
2026-11-13 15:47 UTC):

| Check | Result |
|---|---|
| Snapshot | 953 files, 2,572,503,088 bytes (sum of file sizes) |
| Swift then oracle | identical, 28 lines each |
| Oracle then Swift | identical; Swift run 1 equals run 2 |
| Live transcripts, same window (diagnostic only) | Swift and oracle identical; live differs from the snapshot only in `open agent=claudeCode` (82 vs 83), the one line the plan expected to move while a session is still live |
| Time | Swift 89.4 s and 88.7 s (its own `read … in` line); the oracle 6.3 s and 6.0 s wall clock |

Four earlier recorded runs (14:50, 15:00, 15:22 and 15:35 UTC) agreed too. The
first used an app binary left over from before the round-1 code fixes
(`make test` builds only the test target); the script now builds the app
itself and prints the commit and the binary's hash. The other three preceded
later code changes. None of their outputs or timings are used here.

Swift reports reading 2,590,054,688 bytes, more than the snapshot holds. The
line reader counts every chunk it reads, and a read that stops at 2,000 lines
re-reads the rest of that chunk on the next call (`IncrementalLineReader`,
inferred from its code, not measured). The 14x gap to the oracle is a measured
cost of the Swift path; its cause is not measured (inferred: each line is
parsed as JSON twice, once for History and once for the wait rules, and the
History wrapper regexes are compiled on every call).

**Two snapshots of the same window gave different counts.** An earlier
snapshot, taken at 11:23 UTC the same day and read by the code at `e3b6540`,
also agreed in both orders but gave 101 Claude Code sessions and 750 turn
waits (22 Codex sessions, 132 waits; its output is the version of
`pilot/wait-stats-2026-10-14_2026-11-12.txt` committed at `94659b9`) against
99, 701, 21 and 130 here. Why they differ was not established. Possible
explanations, none verified: transcripts of the window's first days removed
by Claude Code's 30-day cleanup (the window starts 30 days back) or by Codex
archiving; later edits to those files; the round-1 rule changes between the
two code versions (the two-element shell command and the all-object list
rules). The numbers below are from the later run, whose output is
committed.

Supporting evidence: the oracle and the Swift tests pass the same eight
hand-derived fixture scenarios byte for byte (`oracle_selftest.py`,
`WaitStatsTests`, and the CLI); nine rule mutations each fail the oracle's
selftest (`pilot/oracle-mutations.txt`); the `waitSentinelsNeverLeak` canary
fails when a fold keeps prompt text or a wait keeps tool input
(`pilot/canary-mutations.txt`).

## Output

`pilot/wait-stats-2026-10-14_2026-11-12.txt`, verbatim:

```
sessions agent=claudeCode n=99
sessions agent=codex n=21
open agent=claudeCode n=83
open agent=codex n=19
waits agent=claudeCode kind=approval answer=accept n=7
waits agent=claudeCode kind=question answer=accept n=43
waits agent=claudeCode kind=question answer=reject n=7
waits agent=claudeCode kind=question answer=unknown n=4
waits agent=claudeCode kind=turn n=701
waits agent=codex kind=turn n=130
over_cap agent=claudeCode kind=approval n=1
over_cap agent=claudeCode kind=question n=12
over_cap agent=claudeCode kind=turn n=78
over_cap agent=codex kind=turn n=25
seconds agent=claudeCode kind=approval p25=37 p50=52 p75=292 n=7
seconds agent=claudeCode kind=question p25=62 p50=605 p75=6149 n=54
seconds agent=claudeCode kind=turn p25=174 p50=672 p75=3274 n=701
seconds agent=codex kind=turn p25=23 p50=366 p75=3764 n=130
seconds agent=claudeCode kind=approval ordinal=1 p25=43 p50=277 p75=2178 n=4
seconds agent=claudeCode kind=approval ordinal=2-3 p25=29 p50=52 p75=66 n=3
seconds agent=claudeCode kind=question ordinal=1 p25=59 p50=497 p75=3095 n=28
seconds agent=claudeCode kind=question ordinal=2-3 p25=55 p50=1079 p75=7200 n=15
seconds agent=claudeCode kind=question ordinal=4-7 p25=99 p50=614 p75=2321 n=7
seconds agent=claudeCode kind=question ordinal=8+ p25=319 p50=1977 p75=4074 n=4
blocked agent=claudeCode scope=all unit=min p25=15 p50=100 p75=288 total=24289 n=99
blocked agent=claudeCode scope=within_cap unit=min p25=12 p50=70 p75=163 total=13369 n=99
blocked agent=codex scope=all unit=min p25=0 p50=0 p75=120 total=4554 n=21
blocked agent=codex scope=within_cap unit=min p25=0 p50=0 p75=0 total=1554 n=21
```

## Readings

Each line below is arithmetic on the output above, or labelled.

1. **A finished Claude Code turn waited a median of 11 minutes** (672 s,
   IQR 174-3,274 s, 701 waits in 99 sessions). Codex: median 366 s, IQR
   23-3,764 s, 130 waits in 21 sessions.
2. **The 2 h cap carries much of the total.** Claude Code: 10,920 of 24,289
   blocked minutes (45%) come from the 91 waits over 2 h; Codex: 3,000 of
   4,554 (66%). The within-cap median per Claude Code session is 70 min
   (IQR 12-163). Any headline figure depends on the cap, so it would need to
   show `within_cap` or say what the cap is.
3. **Most sessions end waiting.** 83 of 99 Claude Code sessions and 19 of 21
   Codex sessions end on a turn wait that was never closed; those final waits
   are not counted.
4. **Approvals are rare here, questions are not.** 7 human-decided approvals
   in 30 days (auto mode), against 54 `AskUserQuestion` answers (43 accept,
   7 reject, 4 with no decision; median 605 s, 12 over 2 h). The approval
   median of 52 s includes the tool's own run time.
5. **No habituation curve can be read from this.** Question medians by
   ordinal are 497 s (1st, n=28), 1,079 s (2nd-3rd, n=15), 614 s (4th-7th,
   n=7), 1,977 s (8th and later, n=4): no monotone trend, and the later
   buckets are too small to separate from noise.
6. **Why about 100 sessions, not the plan preview's 221.** The preview counted
   any transcript with a typed-looking prompt. On the earlier snapshot, 118 of
   those were `sdk-cli` (unattended `claude -p`) runs and 105 interactive
   (`probe/session-kinds-snapshot.txt`); History, and so this metric,
   excludes the unattended ones. Which rule leaves out the remaining few
   interactive transcripts (no human event or wait inside the window, or only
   text History drops) was not measured.

## What is left unmeasured or uncertain

- The plan's known limits, all of which apply here:
  - an approval wait includes the approved tool's run time;
  - a turn wait still open when the transcript ends is not counted;
  - a turn that ends with `stop_reason` `stop_sequence`, `refusal`,
    `max_tokens` or none opens no wait;
  - a background `<task-notification>` that restarts the agent after
    `end_turn` clears the wait, which then starts at the later `end_turn`;
  - an interrupted turn (Claude Code interrupt, Codex `turn_aborted`) opens
    no wait, although the agent then waits;
  - a prompt queued while the agent works can close a wait of about zero
    seconds;
  - a transcript copied into a second file by a resume or fork counts its
    waits in both (one Codex prompt in 30 days, `probe/wait-rule-30d.txt`);
  - one person waits on several sessions at once, so session minutes overlap
    in wall time;
  - a session driven only by slash commands, and a fleet seat with only
    dispatch prompts, are not eligible (4 such seat transcripts with 6
    human-answered dialogs in 30 days);
  - the cap is 2 h, and `scope=within_cap` shows what it carries.
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
