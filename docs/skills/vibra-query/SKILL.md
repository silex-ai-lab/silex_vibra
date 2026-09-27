---
name: vibra-query
description: Ask Vibra which local coding-agent sessions (Claude Code, Codex, OpenCode, Cursor, VS Code Copilot Chat, Hermes) are working, stalled, waiting for the user, or blocked on an approval, and what they have cost. Use when an agent needs to know whether another session needs the human, or wants a machine-readable list of live agent sessions on this Mac.
---

# vibra-query

Vibra is a macOS menu-bar app that watches the session files local coding
agents write. `--query` prints exactly what its menu shows, as JSON.

## Run it

```sh
/Applications/Vibra.app/Contents/MacOS/Vibra --query     # after `make install`
<repo>/.build/release/VibraApp --query                   # from a build (`make query`)
```

Options:

- `--attention` — only sessions that need the human (`awaitingInput`, `blocked`).
- `--agent <kind>` — one of `claudeCode`, `codex`, `openCode`, `cursor`,
  `vsCode`, `hermes`. An unknown kind exits 1 with the valid list on stderr.

Exit 0 with one JSON object on stdout; exit 1 on failure.

## Output

```json
{
  "generatedAt": "2026-09-26T09:00:00Z",
  "settings": {"activityWindowSeconds": 43200, "attentionDecaySeconds": 28800, "stallThresholdSeconds": 300},
  "sessions": [{
    "agent": "claudeCode", "id": "…", "project": "my-repo", "cwd": "/Users/me/my-repo",
    "gitBranch": "main", "state": "awaitingInput", "needsAttention": true,
    "lastEvent": "turnComplete", "lastActivity": "…", "startedAt": "…",
    "model": "…", "tokens": {"input": 0, "output": 0, "cacheRead": 0, "cacheCreation": 0},
    "estimatedCostUSD": 0.12, "unattended": false
  }]
}
```

- `state`: `working`, `awaitingInput` (your turn), `blocked` (needs approval),
  `stalled` (went quiet mid-turn), `idle`.
- Every key is always present; unknown values are `null`.
  `estimatedCostUSD` is `null` when the model has no published rate — never 0.
  It is an API-price estimate, not a bill.
- Only sessions active within `activityWindowSeconds` are listed.
- `unattended` sessions (`claude -p`, scheduled tasks, `codex exec`, Hermes
  subagents) finishing their turn is not a question for anyone.

## Guarantees

- **Never contains message content**, and so no session titles (they are
  derived from message text). Identify a session by `project`, `cwd` and `id`.
- Read-only: Vibra never writes to the agents' files, and `--query` writes
  nothing at all.
- Local only: no network.
