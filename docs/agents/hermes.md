# Hermes

Vibra reads Hermes Agent's state database and shows working, your turn, stalled and idle (fixture-tested only); Hermes never reports needs approval and its rows cannot be jumped to.

## What Vibra reads

`~/.hermes/state.db` (CLI and chat gateways)

Vibra opens the database read-only, reads an allowlist of columns from the
`sessions` and `messages` tables, and never selects message `content` on the
status path. It knows one path, `state.db`, and never opens `~/.hermes/.env` or
`auth.json` — see [../privacy.md](../privacy.md).

## States shown

- 🔵 **working** — can show, from the latest active message: an `assistant`
  message ending in `tool_calls`, or a `tool`/`user` message (`.producing`).
- 🟠 **your turn** — can show, from an `assistant` message whose `finish_reason`
  is `stop` or `length` (`.turnComplete`).
- 🔴 **needs approval** — never, because `HermesAdapter.lastEvent` never yields
  `.permissionPrompt`; Hermes records no approval state Vibra can see.
- 🟡 **stalled** — can show, from `.producing` that went quiet past the stall
  threshold (`StateEngine`).
- ⚪️ **idle** — can show, from an ended session (`.settled`) or an unrecognised
  last event.

## Verified vs. unverified

| State | Status | Evidence |
|---|---|---|
| working | fixture-tested | `HermesAdapterTests.stateRulesFollowTheLatestActiveMessage` (`tool`/`user`/`tool_calls` → `.producing`); no live transition watched ([README@d40c4fb:550-556](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L550-L556)) |
| your turn | fixture-tested | `HermesAdapterTests.stateRulesFollowTheLatestActiveMessage` (`stop`/`length` → `.turnComplete`); no live transition watched ([README@d40c4fb:550-556](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L550-L556)) |
| needs approval | never shown | `HermesAdapter.lastEvent` never yields `.permissionPrompt`; `HermesAdapterTests.stateRulesFollowTheLatestActiveMessage` asserts none |
| stalled | fixture-tested | `LivePipelineTests.classificationUsesThePassedStallThreshold` (`SettingsAndPipelineTests.swift`) (`.producing` quiet → stalled); no live transition watched ([README@d40c4fb:550-556](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L550-L556)) |
| idle | fixture-tested | `HermesAdapterTests.stateRulesFollowTheLatestActiveMessage` (`h_ended` → `.settled`); ended sessions observed idle on a real `state.db` ([README@d40c4fb:550-552](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L550-L552)) |

## Limits

- **Hermes states are fixture-tested only.** The adapter was checked against a
  real `state.db` for discovery (every session found, ended ones idle, a
  subagent unattended), but that machine's newest Hermes activity was months
  old, so no live transition was watched. Hermes records no approval state
  Vibra can see, so a Hermes session never shows "needs approval".
  `reasoning_tokens` are not counted, to avoid counting them twice if they are
  already inside `output_tokens`.

Hermes publishes no link between its session and its process, so there is no
tab to jump to; its menu row reports state and tokens but does nothing when
clicked (see [../troubleshooting.md](../troubleshooting.md)).

## Check it yourself

From the cloned repo:

```sh
make probe
```

Or ask the installed app, filtered to Hermes:

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --query --agent hermes
```
