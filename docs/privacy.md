# Privacy and safety

Vibra never asks these tools to change what they write. It is a passive reader
of files that already exist.

**It installs nothing into your agents** — no hooks, no plugins, no statusline,
no wrapper binaries. Uninstalling Vibra is deleting the app, then its saved
data: `rm -rf ~/Library/Application\ Support/Vibra` removes your answers in the
Review Agent Activity window, and `defaults delete ai.silexlab.vibra` removes its
settings.

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
- **Code checks in Session Details read commands and check output, and show
  neither.** For Claude Code and Codex, opening a session's details reads that
  session's transcripts and its subagents'. Each tool record is parsed in memory,
  including shell command text, edited paths and tool output. From a check's
  output only the last 6 KB is examined. All of it is reduced to a kind, a result
  and a timestamp, then dropped, and nothing is written. To find a Codex session's
  subagents, Vibra also opens each rollout modified since that session started
  and reads its first line, which it parses only when the line names this
  session's id. A canary test (`evidenceSentinelsNeverLeak`) plants a sentinel in
  a command, a path and tool output for both agents and asserts it reaches no
  extractor state, result, row text or `--evidence-stats` output. `make test`
  fails if that test did not run.
- **Test-file edits are counted, never kept.** For a Claude Code `Edit` or
  `MultiEdit` on a test file, the removed and inserted text is read in memory
  only to count pattern matches, in the extractor, and then dropped. The file's
  path becomes an opaque in-memory hash key, used only to tell one file from
  another. Nothing new is written to disk, and nothing is sent anywhere. The
  `evidenceSentinelsNeverLeak` canary also plants sentinels in test-file paths
  and in edit text for both agents. It requires the test-edit sentence to fire
  first, so the text went through counting, and then asserts no sentinel
  reaches any output. With a key that kept the raw path, or one built from the
  edit text, the canary failed on the matching sentinel (plan task 7 mutation
  run).
- **`--wait-stats` reads prompts only to classify them, and prints
  durations.** It reads Claude Code and Codex transcripts from disk. A prompt
  goes through the same History rule, in memory, only to decide whether you
  typed it or a fleet planner dispatched it; a record History drops is
  searched only for a leading slash-command or shell-run tag; tool input is
  never read, only a tool's name, its id and the decision Claude Code
  records. What it keeps per transcript is times, and what it prints is
  counts and durations. The `waitSentinelsNeverLeak` canary plants sentinels
  in prompts, tool input and results, replies, cwd, session ids and file
  paths for both agents, requires waits of every kind to be produced first,
  and asserts no sentinel reaches the output or the folded values. A fold
  that kept prompt text, or a wait that kept tool input, failed it (plan
  task 6 mutation run). `make test` fails if it did not run.
- **Returning to a session in Orca reads one environment variable.** When you
  click a session running in an Orca terminal, Vibra asks the kernel for that
  agent process's start-up environment and keeps only `ORCA_TERMINAL_HANDLE`,
  which it passes to `orca terminal switch`. That environment also holds other
  values, including an Orca hook token. They are not stored, printed or passed
  on. Nothing is read until you click.
- **History is the one feature that shows what you typed.** It reads on demand,
  keeps the text in memory only while its window is open, and writes nothing.
  Everything machine-readable stays content-free: `--query`, `--probe`,
  `--dump-sessions` and `--history-stats` print states, counts and project
  names, never message text, and a canary test covers `--history-stats`.
- `--dump-menu`, and the file named by `VIBRA_DEBUG_MENU_DUMP`, carry keys,
  states and codes only: an agent, a session id, a state, a wait kind and
  seconds, a click kind, and a failing agent's problem code. Never a title,
  path or branch. A canary test covers it.
- Notification bodies name the project, or a scheduled task plus its project;
  they never carry a title the agent derived from a prompt.
- Vibra persists two things between runs. Its four settings live in the
  `ai.silexlab.vibra` preferences domain: the three thresholds in Settings, and
  `onboardingCompleted`, the boolean that records the first-run window was
  closed. Your answers in the Review Agent Activity window live in
  `~/Library/Application Support/Vibra/incidents.json`, as hashed incident ids,
  the answer and its date, and one notification timestamp. An answer older than
  90 days is pruned. A file that cannot be read is renamed
  `incidents.corrupt-<time>.json`, kept beside it, and the window says your
  answers were reset. (The `--show-* --snapshot <path>` diagnostics write a PNG
  where you tell them to.)
- **The incident monitor is always on, and reads what Session Details reads.**
  At launch it parses every Claude Code and Codex transcript modified in the last
  7 days, and afterwards every line appended to them, including tool inputs, shell
  command text, edited paths and tool results. All of it is reduced in memory to
  closed values: a kind, a credential class, a tool class, a date, a token count
  and a hashed id. Only the hashed ids, your answers and one timestamp are
  written. A retried call is compared through a fingerprint held in memory and
  never stored. `--incidents` prints those closed values and nothing else. A
  canary test (`incidentSentinelsNeverLeak`) plants a sentinel in a command, a
  path, tool output, a prompt, a secret-shaped session id and a vendor key id, and
  asserts it reaches no incident, JSON, store file, report draft or `mailto:` URL.
  `make test` fails if that test did not run.
- **Reports leave only when you send them.** A report is a draft on this Mac that
  you can edit. Open Email Draft hands it to your mail app with no recipient, and
  the vendor page opens in your browser with no query string. Vibra makes no
  request and cannot see whether you sent anything.
- **A vendor usage file is read and dropped.** You fetch it yourself with your own
  key, Vibra parses it in memory, never stores it and never sees the key. Findings
  from it live until the app quits. The answer you give is kept by hashed id.
- `VIBRA_HOME`, `VIBRA_PREFS_DOMAIN` and `VIBRA_DEBUG_MENU_DUMP` are diagnostic
  environment overrides: a fixture data tree (`incidents.json` follows it), a
  separate preferences domain and a place to write the menu dump. Unset, Vibra uses the real ones and writes no
  dump.
- Adapters never log or print raw rows.
- **The Usage Report's performance suggestions** read, from Claude Code
  transcripts, only each response's ID, token counts, model, timestamp,
  `isSidechain` flag, the names of the tools it called and the last component
  of its working directory. Never tool inputs, tool results or message text. A
  canary test (`perfPrivacySentinelsNeverLeak`) plants a sentinel in message
  text, a thinking block, a tool input, a tool result, `wireToolInputs` and a
  parent directory, makes every suggestion kind fire, and asserts no sentinel
  reaches a sample, the JSON or the rendered text. `make test` fails if that
  test did not run.
