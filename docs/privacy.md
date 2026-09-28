# Privacy and safety

Vibra never asks these tools to change what they write. It is a passive reader
of files that already exist.

**It installs nothing into your agents** — no hooks, no plugins, no statusline,
no wrapper binaries. Uninstalling Vibra is deleting one `.app`.

Vibra reads local files and sends nothing anywhere. Specifically:

- **No network egress at all.** No account, no telemetry, no update ping.
- `opencode.db` also contains `access_token`, `refresh_token` and a `credential`
  table. The adapter opens the database **read-only** (`mode=ro`), emits a
  single hard-coded `SELECT` against the `session` table with an explicit column
  list, never `SELECT *`, and verifies the schema before querying.
- A **canary test** builds a fixture database containing a sentinel token and
  asserts that string appears nowhere in the returned sessions, their JSON
  encoding, or any error description. `make test` fails if that test did not run.
- Cursor's `state.vscdb` holds its auth tokens too, so the Cursor adapter gets
  the same contract: read-only, one hard-coded `SELECT`, and the token table is
  never referenced.
- VS Code's chat logs contain the whole conversation. The adapter replays each
  log onto a reduced state (title, folder, and per request its timestamps,
  model, token counts and reply state) and discards every message and response
  body as it parses. A canary test plants a sentinel in the prompt, the response
  and the input box and asserts it appears nowhere in the returned sessions.
- Hermes keeps secrets in `~/.hermes/.env` and `auth.json`. The Hermes adapter
  knows one path, `state.db`, opens it read-only, and reads an allowlist of
  columns. The status path never selects message text; the one statement that
  does runs only for the History window, and a test proves the status path
  never prepares it. A canary in a message row, the system prompt, `.env` and
  `auth.json` appears in no session, no `--query` output and no error.
- **History is the one feature that shows what you typed.** It reads on demand,
  keeps the text in memory only while its window is open, and writes nothing.
  Everything machine-readable stays content-free: `--query`, `--probe`,
  `--dump-sessions` and `--history-stats` print states, counts and project
  names, never message text, and a canary test covers `--history-stats`.
- The only thing Vibra persists between runs is its three settings, in the
  `ai.silexlab.vibra` preferences domain. (The `--show-* --snapshot <path>`
  diagnostics write a PNG where you tell them to.)
- Adapters never log or print raw rows.
