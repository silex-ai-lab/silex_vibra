# Features

The five session states and the compatibility table are on the
[README](../README.md). This page covers the menu's structure and everything
beyond it.

## The menu

The dropdown leads with **Needs You**: every session waiting on you, across all
agents, approvals before finished turns, longest wait first. **Running** comes
next (working and stalled), and idle sessions collapse into a **Recent**
submenu. Each row names the agent, and a waiting row also says how long —
`needs approval · 4m`, or `your turn · first seen 4m ago` when Vibra did not see
the turn end. Rows that share a label are told apart by branch, then the last
two path components, then a short session prefix. A row carries no token count; the tooltip does
(`Tokens: none reported` when the agent publishes none), and so does the detail
window.

A row for an agent Vibra cannot return to — OpenCode and Hermes — is not
disabled: clicking it opens its details.

**Session Details** lists every session in the same order, whatever its state.
Clicking one opens the detail window: project, agent, branch, state and the
evidence behind that state, when it was last observed and whether its data
source is being read normally, tokens, and buttons for **Return to Session**
(only when a return is possible), **View History** (only for agents whose
history Vibra reads), **Open Project Folder** and **Copy Path**. A session that
exits keeps the details it had and says `No longer active`.

For Claude Code and Codex the window also has a **Code checks** row. It says
whether the session issued a test, build or lint command after its last code
change, counting subagents, and what that command returned. An exit status
counts only when the check is one simple command on its own. Anything else, such
as a pipe, `&&`, a subshell or a background run, falls to the runner's own
summary line, and a call that did not exit cleanly can never read as a pass from
one. A run that selected no tests reads as not visible. If
nothing decides, the result reads as not visible. The row describes what this
session did. It does not say a task is done, and edits made through shell
commands are not counted. `Vibra --evidence-stats [--days N]` prints the same
results as counts, with no commands or paths.

When there is nothing to show, the menu says why: `No active sessions` when the
sources are readable, a list of agents to start when none has state on disk,
and a notice instead of a claim of inactivity when a source cannot be read.

**Setup…** reopens the first-run window. At first launch it shows what Vibra
found for each agent (`seen recently`, `no recent sessions` or `no sessions
yet` — never "not installed"), the notification state with **Enable
Notifications** and **Send Test**, **Open Notification Settings**, and
**Launch Vibra at login**. Closing it counts as finishing it, so it does not
reopen on its own.

## Usage Report

**Usage Report…** (⌘U in the menu) shows what your agents used over the last
seven days (rolling, not a calendar week): tokens and estimated API-equivalent
value **by day** and **by agent**, and a total. It is read from the agents'
files when you open the window, separately from the live menu, so opening it
never disturbs what the menu shows.

Coverage differs by agent:

- **Claude Code and Codex** are counted per record and bucketed by local day,
  so a session that spans several days is spread across them. These are the
  only agents in the by-day lines, the by-agent lines and the total.
- **OpenCode and Hermes** store per-session totals with no per-message
  timestamps. Their tokens are shown on a separate "could not be dated" line —
  all of their sessions, not limited to the seven days — and are **not**
  included in the by-day lines, by-agent lines or total.
- **Cursor and VS Code** contribute nothing: Cursor records no token usage,
  and VS Code's tokens are not read into the report.

Tokens from a model with no published rate are listed as unpriced and left
out of the estimate rather than counted as `$0`. See
[What the cost figures mean](#what-the-cost-figures-mean) for what the value
is and is not.

Claude Code writes one API response as several transcript records, one per
content block, each repeating the response's ID and token counts. Vibra counts
each response once, keeping its last record, when those records are adjacent
in the file, as they were in every case measured (9,789 repeats, none
non-adjacent, none across files). Before 2026-11-03 it summed every
record, which overstated Claude Code tokens and value by about 2x (measured
2.13x on one machine's last 7 days). Totals from earlier versions are not
comparable.

### Performance suggestions

Below the totals, the report lists up to three patterns that cost your Claude
Code sessions the most in the window, one per kind, each with the command to
try next time and the evidence behind it:

```
PERFORMANCE — Claude Code sessions
1. Run /compact inside long tasks and /clear between tasks. Split unrelated work into separate sessions.
   proj, Nov 2, 60 turns above 200k: the context above 200k cost about $0.90.
```

| Kind | What it measures | Figure |
|---|---|---|
| Context carry | At least 50 turns in one stretch between compactions whose prompt was above 200k tokens. | What the prompt tokens above 200k cost on those turns. |
| Cache rewrite | Turns where most of what the previous turn left in cache was written to cache again, with the cause it coincided with: a model switch, a gap of over an hour, a gap of over 5 minutes, or neither. The cause is a correlation, labelled "inferred". | The write premium over a cache read on that context. |
| Exploration burst | At least 3 turns in a row that only Read, Grep or Glob. | If what the burst added stayed in context, what re-sending it cost. |

How to read them:

- **A figure is an estimate of what the pattern cost, not a promised saving.**
  The alternative (`/compact`, a subagent) has its own cost, which the
  transcript cannot show. Figures use Vibra's rate table, last verified
  2026-09-19, which has a single cache-write rate, so 1-hour cache writes are
  priced low.
- **Only patterns worth acting on are shown.** A pattern is listed when it cost
  at least $0.25 and at least 10% of that session's value. When none qualifies,
  the report says so instead of padding the list.
- **Sessions on a model with no published rate** (Fable, today) get no figure.
  Their patterns are listed separately, marked "no published rate".
- **Subagent transcripts** count in the totals but are not analyzed: the advice
  is about the main session.
- Sessions with fewer than 10 turns in the window are skipped.
- The exploration-burst kind has not yet been seen as a lead on real sessions.

The thresholds can be changed with `defaults write`, read when the report
opens:

| Key | Default |
|---|---|
| `perf.minTurns` | 10 |
| `perf.d1MinTurnsAboveFloor` | 50 |
| `perf.d1CarryFloorTokens` | 200000 |
| `perf.d2MinRewriteTokens` | 30000 |
| `perf.d3MinBurstTurns` | 3 |
| `perf.leadMinUSD` | 0.25 |
| `perf.leadMinShare` | 0.10 |

```sh
defaults write ai.silexlab.vibra perf.d1CarryFloorTokens -int 300000
defaults delete ai.silexlab.vibra perf.d1CarryFloorTokens   # back to the default
```

### `--report` and `--report --json`

`Vibra --report` prints the same text as the window. `Vibra --report --json`
prints one JSON object with `"schema": 1`, the window, the bytes and files
read, exact token counts per agent, and every suggestion that fired with its
evidence. `VIBRA_NOW=<ISO 8601 time>` runs either at a fixed time. Neither
prints message text.

## Review Agent Activity

The menu's **Review Agent Activity…** lists what Vibra saw agents do that you may
not have sanctioned. It covers Claude Code and Codex only, and it observes. It
never blocks or interrupts an agent.

| Finding | Severity | What it means |
|---|---|---|
| A denied call ran later | review | A call was denied and the identical call later returned, with no message from you in between. You or a rule may have approved the retry. Claude Code only |
| A credential read | review | A named reader was pointed at a credential: `~/.aws`, `~/.ssh`, `.netrc`, a package or GitHub token, an agent's own credentials, a keychain lookup, or a `.env` outside the workspace |
| This project's .env was named | info | The same, for a `.env` inside the workspace. One per session |
| A write outside the workspace | review | A tool edit whose path, as written, is outside the workspace. One finding per session and destination family, sibling repositories or elsewhere. A later write reopens a closed one |
| A force push | review | `git push --force`, `-f` or a `+` refspec. `--force-with-lease` alone is exempt |
| Guardrails were off | info | The session ran in `bypassPermissions` or `danger-full-access` |
| The vendor rejected the credentials | info | An `authentication_failed` record. Claude Code only |
| Vendor usage this Mac cannot explain | review | From a usage file you import |

**What it cannot see.** Readers are named commands with known options, so `sed`,
`awk`, `xxd`, `strings`, `gh auth token`, scripts and interpreter one-liners are
not analysed, and an unknown option declines that command. A shell finding that
may not have run says so. Paths are compared as written, so a symlink or a
`--add-dir` grant looks like an outside write. Shell redirection is not analysed.

**Answers.** Each finding can be marked Expected, Resolved or Reported, and
reopened. Notifications carry a count only, at most one a minute, and backfilled
findings never notify on a first run. A finding that completed while Vibra was
closed notifies at the next launch. After launch the list fills in once the replay
finishes, 20 to 25 seconds for 700 MB of transcripts on the machine it was measured
on.

**Importing vendor usage.** The window can compare a usage file with this Mac's
own usage, to spot quota someone else consumed. It needs an organization API
usage page for exactly one API key. One complete page holds at most 31 days, and
a file whose oldest day is more than 62 days old is refused. So is a file with
usage on a day after today (UTC); an empty day after today is ignored, because a
page lists every day in its range. Pro, Max and ChatGPT
plans appear in no file you can import. You fetch the file in your own terminal
with your own admin key, and the window shows the command. A day is flagged when
the vendor counted more than `max(10%, 100,000 tokens)` beyond what this Mac
recorded, which is a starting guess. Your other machines and apps look the same.
Subscription use on this Mac can mask excess.

**Reporting.** A finding can become a local draft you edit. Vibra states what it
saw and what else could explain it, and never says an agent was malicious or a key
was stolen. You can copy it, open it as an email with no recipient, or open the
vendor's page. Neither Claude Code's nor Codex's security policy publishes an
email address, so Vibra does not invent one.

`Vibra --incidents [--days N] [--json]` prints the same closed values. It reads
your answers and writes nothing.

## History, settings and `--query`

**History…** (⌘Y in the menu) lists the questions you typed into Claude Code,
Codex and Hermes over the last 1, 3, 7, 14 or 30 days, grouped by day, with a
search box and an agent filter that carries each agent's question count. Click
a row to read the question in the detail pane beside the list — its time,
agent, project and session id; the transcript file it came from, with **Copy
Path** and **Open**; and, for Claude Code, collapsed **Tasks** (the todo list
under that question) and **Timeline** (which tools ran, never their
arguments), read from that file only when you select the row. Copy the
question from there, or **Copy** to put every visible row on the clipboard as
tab-separated fields. Every button keeps its text label and gains an SF Symbol
beside it; the section headers carry one between the disclosure triangle and
the word. Double-click a row — or press ⌘J — to jump to its
session if it is still live, or to copy the question; ⌘F focuses the search,
⌘⇧C copies the visible rows, and Esc clears the search. It is read from the
agents' files when
you open the window — the same way the usage report is — held in memory while
the window is open, and dropped when you close it. Nothing is saved. Excluded:
anything the agent injected rather than you typed (tool results, slash-command
and shell output, background-task notifications, subagent prompts) and
unattended runs (`claude -p`, scheduled tasks, `codex exec`, Hermes
subagents). OpenCode, Cursor and VS Code are not covered: their prompt text
lives in stores Vibra deliberately does not read beyond session metadata.

**Settings…** (⌘,) has three numbers: when a mid-turn session counts as
stalled (default 5 min), when an unanswered "your turn" fades to idle (2 h),
and how far back the menu looks (12 h). A "your turn" you go back to, by
clicking its row or its notification, drops to idle at once and stays there
until the session has new activity. They are stored in the
`ai.silexlab.vibra` preferences domain, apply on the next refresh without a
relaunch, and can also be set from a shell:

```sh
defaults write ai.silexlab.vibra stallThresholdSeconds -int 600
defaults delete ai.silexlab.vibra        # back to the defaults
```

**`--query`** prints what the menu shows as JSON, for scripts and agents:

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --query                                # after make install
make query                                                                          # from a build
/Applications/Vibra.app/Contents/MacOS/Vibra --query --attention                    # only sessions that need you
/Applications/Vibra.app/Contents/MacOS/Vibra --query --agent codex                  # one agent
```

Each session has `agent`, `id`, `project`, `cwd`, `gitBranch`, `state`,
`needsAttention`, `lastEvent`, `lastActivity`, `startedAt`, `model`, `tokens`,
`estimatedCostUSD` (`null` when the model has no published rate) and
`unattended`, plus the settings in force. It never contains message text, so no
titles either. [docs/skills/vibra-query/SKILL.md](skills/vibra-query/SKILL.md)
tells a coding agent how to use it.

### Asking Vibra from another agent

A coding agent can answer "which of my sessions needs me?" without you
looking at the menu:

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --query --attention
```

That lists only the sessions waiting on you (`awaitingInput`) or on an
approval (`blocked`). The JSON never contains message text, and so no session
titles; it does contain metadata — `project`, the absolute `cwd`, `gitBranch`,
session `id`, `model`, tokens and estimated cost — so treat it as you would
those paths and names before handing it to another tool or model.
[skills/vibra-query/SKILL.md](skills/vibra-query/SKILL.md) is a
ready-made skill that teaches a coding agent to use it.

## Session states

The five states are listed on the [README](../README.md#what-the-colours-mean).

`stalled` exists because an agent that died mid-turn looks identical to a busy
one if you only ask "is it running?".

### Notification lifecycle

A "your turn" notification is only posted on the *transition* into 🟠 or 🔴,
debounced per session so state flicker cannot produce a burst — and it is
**withdrawn as soon as it stops being true**: when you answer the session and it
goes back to work, when the session disappears, and when Vibra quits. Each
session's notification is keyed by its session id, so one session that keeps
wanting you replaces its own entry rather than stacking new ones.

That matters because the alternative is what Vibra used to do: banners
accumulated in Notification Center for the whole login session, all of them
about prompts that had long since been answered.

## What the cost figures mean

Costs are computed from token counts times published per-model rates. They are
an **API-equivalent value**, not your actual bill. If you are on a subscription
(Claude Max, ChatGPT Plus/Pro) you are not charged per token and the real spend
is your flat fee — the figure tells you what that usage would have cost at API
list price, which is useful for comparison and useless as an invoice.

A model with no known published rate reports `n/a` rather than a guess.
