# Fix plan — notification lifecycle (2026-09-21)

Found on a clean clone + `make install` on **macOS 15.7.3, Swift 6.1.2**
(STATUS.md's last verification was macOS 26.6.2, which is why neither shows up
there). Build, `make test` (66 tests), `make probe` and the menu bar app itself
are all fine; both bugs are in the notification path.

## Bug 1 — `--test-notification` crashes instead of reporting

```
$ /Applications/Vibra.app/Contents/MacOS/Vibra --test-notification
Trace/BPT trap: 5          exit 133, no output at all
```

Crash report, triggered thread:

```
_dispatch_assert_queue_fail
dispatch_assert_queue
swift_task_isCurrentExecutorWithFlagsImpl
closure #1 in <main.swift top level>
thunk for @escaping @callee_guaranteed (@unowned Bool, @guaranteed Error?) -> ()
```

`Package.swift` is `swift-tools-version:6.0`, so **top-level code in
`main.swift` is `@MainActor`-isolated**, and the two UserNotifications
completion handlers at `main.swift:20` and `:36` inherit that isolation.
UserNotifications invokes them on a background dispatch queue, the Swift 6
runtime checks the executor on closure entry, and the assert traps.

It dies *before* the first `print`, which is why stdout is empty — the output
was still in the block buffer.

**Blast radius is this one command.** `UserNotificationSink` is a plain
nonisolated class, so its callbacks (`{ _, _ in }`, `{ _ in }`) are nonisolated
and do not trap; the running app has been up for 15 minutes at 0.1% CPU. But
this command is the *documented* way to diagnose notifications (README
"Troubleshooting" and "Known limitations" both point at it), so while it traps
there is no way to find out whether notifications work on a given machine.

## Bug 2 — delivered notifications are never withdrawn

This is the one that was reported. Two defects that compound:

1. `NotificationSink` has **only `deliver`**. Nothing anywhere calls
   `removeDeliveredNotifications`. A session that flips 🟠 *your turn* → 🔵
   *working* leaves its banner sitting in Notification Center; after a day of
   agent work the list is a pile of alerts that are all already dealt with.
2. `UserNotificationSink.deliver` uses `identifier: UUID().uuidString` — a
   fresh random id per delivery. Even given a withdrawal call there is **no
   stable handle** to withdraw by, and repeat alerts for one session stack up
   as separate entries instead of coalescing.

`AttentionNotifier` already computes exactly the transition needed (it compares
`previous` against `current`); it just has nowhere to send the other half of it.

## Steps

| # | Change | Verified by |
|---|---|---|
| 1 | `main.swift`: mark both completion handlers `@Sendable`, replace the captured `var done` with a lock-guarded flag (a `@Sendable` closure cannot capture a mutable local) | `--test-notification` prints its report and exits 0; also tells us the real authorization state on this Mac |
| 2 | `UserNotificationSink.deliver`: `identifier: notification.sessionID` | repeat alerts for one session replace rather than stack |
| 3 | `NotificationSink`: add `withdraw(sessionIDs:)`; `AttentionNotifier` withdraws sessions that left the attention state or vanished from `current`; `RecordingNotificationSink` records them; `UserNotificationSink` calls `removeDeliveredNotifications(withIdentifiers:)` | new tests |
| 4 | Tests in `AttentionNotifierTests`: withdraw on leaving attention, withdraw on disappearance, **no** withdraw while still waiting, debounce unaffected | `make test` |
| 5 | Update README known-limitations + `docs/STATUS.md` (add the macOS 15 verification) | — |

Deliberately **not** doing: clearing `lastNotified` on withdrawal. The debounce
exists for state flicker; clearing it would let a flickering session re-alert,
which is the thing rule 2 was written to prevent. `lastNotified` entries for
sessions gone from `current` do get pruned, so the dictionary stays bounded.

## Open decisions

1. **Push target** — branch + PR, or straight to `main`? (`silex_project`'s
   convention is direct-to-main; this repo has no stated rule.)
2. **Withdraw on quit** — also clear vibra's delivered notifications when the
   app terminates? Stale "waiting for you" banners outlive the process today.
   Cheap to add, but it is a behaviour choice, not a bug fix.
