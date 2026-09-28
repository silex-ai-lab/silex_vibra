# OpenCode

Vibra reads OpenCode's session database and shows working, needs approval and idle; OpenCode publishes no session→process link, so its rows cannot be jumped to.

## What Vibra reads

`~/.local/share/opencode/opencode.db` (incl. DeepSeek)

Vibra opens the database read-only (`mode=ro`), runs one hard-coded `SELECT`
against the `session` table with an explicit column list (including
`permission`), and never references the `account`/`credential` tables. It never
writes to the database — see [../privacy.md](../privacy.md).

## States shown

- 🔵 **working** — can show, from a recent, unrecognised last event
  (`.unknown`; `StateEngine` treats recent `.unknown` as working).
- 🟠 **your turn** — never, because `OpenCodeAdapter` emits only
  `.permissionPrompt` or `.unknown`; there is no `.turnComplete` signal.
- 🔴 **needs approval** — can show, from a non-empty `permission` column
  (`.permissionPrompt`).
- 🟡 **stalled** — never, because `.producing` is never emitted.
- ⚪️ **idle** — can show, from an unrecognised last event with no recent
  activity (`.unknown`; `StateEngine`).

## Verified vs. unverified

| State | Status | Evidence |
|---|---|---|
| working | fixture-tested | `OpenCodeAdapterTests.permissionColumnMapsToLastEvent` (NULL `permission` → `.unknown`); `StateEngine` maps recent `.unknown` → working |
| your turn | never shown | `OpenCodeAdapter.discoverSessions` emits only `.permissionPrompt` / `.unknown` |
| needs approval | fixture-tested | `OpenCodeAdapterTests.permissionColumnMapsToLastEvent` (`permission` non-empty → `.permissionPrompt`); unverified live ([README@d40c4fb:547-549](https://github.com/silex-ai-lab/silex_vibra/blob/d40c4fb/README.md#L547-L549)) |
| stalled | never shown | no `.producing` emitted |
| idle | fixture-tested | `OpenCodeAdapterTests.permissionColumnMapsToLastEvent` (`.unknown`); `StateEngine` maps quiet `.unknown` → idle |

## Limits

- **OpenCode blocked-state detection is unverified.** The adapter does read the
  `permission` column and maps a non-empty value to `needs approval`, but that
  transition has not yet been observed live against a real approval prompt.

OpenCode publishes no link between its session and its process, so there is no
tab to jump to; its menu row reports state and tokens but does nothing when
clicked (see [../troubleshooting.md](../troubleshooting.md)).

## Check it yourself

From the cloned repo:

```sh
make probe
```

Or ask the installed app, filtered to OpenCode:

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --query --agent openCode
```
