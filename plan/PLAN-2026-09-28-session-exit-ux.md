# Plan: make session exits quiet and remove stale actions

Status: Navigation mitigation implemented; lifecycle and exit detection remain planned.

Release: `2026-09-28.1`. See the [release notes](../docs/releases/2026-09-28.1.md)
for the delivered scope and verification limits.

Update after live diagnosis: the two reported Codex rows were held by one
managed app-server process, not by their interactive terminal clients. The
navigation fix recognizes that ownership and opens an exact desktop thread
link, with nonmodal session-history fallback. This implements part of Phase 1;
the lifecycle and process-exit work below remains planned. A persistent daemon
lock alone cannot prove that a user still has that session open.

Validation of the navigation mitigation: `make test` passed all 168 tests;
the release build passed; live `--locate` identified both reported rows as
shared-server threads. Installed with the existing `vibra local signing`
identity. Automated menu-click verification was limited by the UI tool exposing
only Vibra's notch overlay, and denying access to iTerm. End-to-end desktop
thread navigation has not been visually verified.

## Intended behavior

When a user exits an agent session, Vibra removes its live row, attention
count, and notification promptly. A click racing with that exit never opens
an error dialog. History stays available. No confirmation or new setting is
needed for ordinary exits.

The user's observation is that most failures follow an intentional session
exit. Treat that as the primary scenario. The screenshot alone does not prove
an exit: the current no-terminal result also covers live background processes,
inspection failures, and failed app activation.

## Findings in the current code

- `Session.withoutExited` keeps every `.working` session even when its ID is
  absent from the live set. `StateEngine` keeps a producing session working
  until `stallThreshold` (five minutes by default), so an exit during work
  can remain visible across multiple refreshes.
- `SessionStore` watches transcript paths and Claude process-record changes,
  with a 60-second safety refresh. A process exit need not change a watched
  file. Codex lock files survive exit; watching file existence alone cannot
  establish whether a writer is alive.
- `ProcessLocator` collapses lookup failure and unavailable process evidence
  into absence. `ProcessInspector.tty` collapses failed inspection and a
  genuinely absent terminal into the same result.
- Menu rows use agent-level `canJump`, then hold a snapshot of the session.
  Clicks do not first reconcile that snapshot with current lifecycle state.
- Routine jump failures activate Vibra and run a modal `NSAlert`. Notification
  clicks already remove the clicked banner, but can still show this alert.
- `AttentionNotifier` already withdraws notifications for sessions removed
  from the live snapshot; the lifecycle fix should reuse that path.

## Phase 1 — make late clicks harmless

1. Replace modal handling of `notLocatable` and `noControllingTerminal` with
   an asynchronous reconciliation path shared by menu and notification clicks.
   Keep GUI activation on the main actor; run process queries off it with
   bounded execution time. Coalesce repeated clicks for the same session.
2. Resolve the clicked ID against the latest store, then recheck its process.
   If exit is confirmed, remove the live entry and its attention contribution,
   withdraw its notification, and return without activating Vibra or requiring
   acknowledgement. Reconcile through the store so menu and `--query` agree.
3. If the process remains alive but has no reachable window, retain the row
   and offer a nonmodal status: "No window is available for this session."
   Include View History and Retry; History may show an empty result for agents
   whose transcript history is unsupported. Do not label this case "closed."
4. If inspection is inconclusive, retain the session and show "Couldn't check
   this session. Try again." without a modal. Do not remove other sessions'
   notifications based on inconclusive checks.
5. Correct History's existing failure text: unsuccessful navigation does not
   necessarily mean its session is no longer live. Avoid an implicit clipboard
   change merely because navigation failed; make Copy an explicit action.

This phase removes the immediate pain even before background detection improves.

## Phase 2 — track exit evidence explicitly

1. Represent lifecycle evidence separately from activity and navigation:
   running, exited, unknown, and parked desktop session. Include the observed
   process identity and observation time. Retain PID start identity where
   available to protect against PID reuse.
2. Treat a verified exit of the previously associated process as stronger than
   cached `.working` output. Remove the unconditional working-state exemption
   for confirmed exits. Preserve a short startup grace for sessions whose
   process association has never been established; initial lookup failure is
   not proof of exit.
3. Before retiring an exited process's session, check for a replacement owner
   or newer activity. Resume/restart under the same session ID must recover
   automatically. A shared backend process is not proof that its particular
   session or UI remains open; retain unknown status when session-specific
   evidence is unavailable.
4. Preserve the existing parked Claude desktop behavior: a resumable UI session
   can legitimately outlive its worker. Agent adapters without reliable exit
   evidence retain their existing lifecycle policy; lack of a terminal never
   establishes exit.
5. Prevent an older in-flight refresh from restoring a removed row. Associate
   exit evidence with a process generation and reconcile newer observations
   before applying snapshots. Never permanently suppress a session ID.

## Phase 3 — detect exits promptly without expensive polling

1. Track already-resolved process identities and subscribe to process-exit
   events where supported. On exit, perform a targeted session recheck and
   publish the resulting snapshot. Cancel observers as owners change or rows
   disappear; handle processes that exit during observer registration.
2. Keep Claude's existing process-record watcher and the safety rescan as
   backstops. Add a coalesced refresh when the menu opens so stale rows are
   reconciled even after missed events. Opening the menu must remain responsive.
3. Where exit observation is unavailable, use a lightweight bounded liveness
   check for tracked processes, initially every five seconds while such
   sessions exist. Re-resolve ownership only when needed. Do not run a full
   transcript scan or per-session `lsof` on a new high-frequency timer.
4. Update reachability independently of transcript changes. A session can
   lose its process without producing a new log record.

## Acceptance and verification

- Quit a waiting CLI session: its row, counts, and delivered notification
  disappear. Target: within two seconds with exit events, or one fallback
  interval plus bounded lookup time when event observation is unavailable.
- Quit during output: no five-minute working-state retention after verified
  exit. A delayed refresh cannot restore the stale row.
- Click a row or notification immediately before/after exit, including repeated
  clicks: no modal, no focus theft, no duplicate navigation attempts.
- Deny or fail process inspection: no false removal or false "closed" claim.
- Keep a headless process running: it remains visible despite having no TTY.
- Park a desktop session, replace a worker, reuse a PID, and resume a session:
  valid sessions remain reachable or recover without restarting Vibra.
- Closed sessions retain their existing History records. Genuine pending
  approvals on still-live sessions remain visible and notified.
- Add deterministic lifecycle and notification tests with injected process
  observations and clocks. Test click policy independently of AppKit; manually
  verify native menu/notification behavior. Run `make test` for implementation.
- Measure idle CPU and subprocess counts with multiple active sessions; confirm
  the new observers do not introduce repeated full scans or main-thread stalls.

## Delivery order

Ship Phase 1 first, then lifecycle correctness in Phase 2, then faster exit
detection in Phase 3. Keep terminal support expansion and visual redesign out
of this fix. Success is that closing a session feels finished, and late clicks
cost the user no extra acknowledgement.
