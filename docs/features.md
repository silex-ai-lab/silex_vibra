# Features

Everything Vibra does beyond the menu itself. The menu, the five session
states and the compatibility table are on the [README](../README.md).

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
stalled (default 5 min), when an unanswered "your turn" fades to idle (8 h),
and how far back the menu looks (12 h). They are stored in the
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

The five states are listed on the [README](../README.md#session-states).

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
