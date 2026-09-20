import Foundation
import Testing
@testable import VibraCore

/// The value of a "your turn" alert collapses if it fires when it shouldn't:
/// an alert that repeats for a prompt you already saw is worse than none,
/// because you learn to ignore it.
struct AttentionNotifierTests {

    private func session(
        _ id: String,
        _ state: SessionState,
        cwd: String = "/fake/my-project",
        at: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> Session {
        Session(
            id: id,
            agent: .claudeCode,
            cwd: cwd,
            state: state,
            startedAt: at,
            lastActivity: at
        )
    }

    private func make(debounce: TimeInterval = 60)
        -> (AttentionNotifier, RecordingNotificationSink) {
        let sink = RecordingNotificationSink()
        return (AttentionNotifier(sink: sink, debounceInterval: debounce), sink)
    }

    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    // MARK: - Transitions

    @Test func transitionIntoAwaitingInputNotifies() {
        let (notifier, sink) = make()
        notifier.notifyIfNeeded(
            previous: [session("a", .working)],
            current: [session("a", .awaitingInput)],
            now: t0
        )
        #expect(sink.delivered.count == 1)
        #expect(sink.delivered.first?.sessionID == "a")
        #expect(sink.delivered.first?.body.contains("my-project") == true)
    }

    @Test func transitionIntoBlockedNotifies() {
        let (notifier, sink) = make()
        notifier.notifyIfNeeded(
            previous: [session("a", .working)],
            current: [session("a", .blocked)],
            now: t0
        )
        #expect(sink.delivered.count == 1)
    }

    @Test func stayingInAttentionDoesNotRenotify() {
        let (notifier, sink) = make()
        // Already waiting, still waiting: not a transition.
        notifier.notifyIfNeeded(
            previous: [session("a", .awaitingInput)],
            current: [session("a", .awaitingInput)],
            now: t0
        )
        #expect(sink.delivered.isEmpty)
    }

    @Test func nonAttentionStatesNeverNotify() {
        let (notifier, sink) = make()
        for state in [SessionState.working, .idle, .stalled] {
            notifier.notifyIfNeeded(
                previous: [session("a", .awaitingInput)],
                current: [session("a", state)],
                now: t0
            )
        }
        #expect(sink.delivered.isEmpty)
    }

    // MARK: - Debounce (the Phase 0b acceptance criterion)

    @Test func sameSessionAndStateIsDebouncedWithinWindow() {
        let (notifier, sink) = make(debounce: 60)

        notifier.notifyIfNeeded(
            previous: [session("a", .working)],
            current: [session("a", .awaitingInput)],
            now: t0
        )
        #expect(sink.delivered.count == 1)

        // Flap back to working and into awaiting again, 59s later. This IS a
        // genuine transition, so only the debounce can suppress it.
        notifier.notifyIfNeeded(
            previous: [session("a", .working)],
            current: [session("a", .awaitingInput)],
            now: t0.addingTimeInterval(59)
        )
        #expect(sink.delivered.count == 1, "second alert within 60s must be suppressed")
    }

    @Test func debounceExpiresAfterWindow() {
        let (notifier, sink) = make(debounce: 60)
        notifier.notifyIfNeeded(
            previous: [session("a", .working)],
            current: [session("a", .awaitingInput)],
            now: t0
        )
        notifier.notifyIfNeeded(
            previous: [session("a", .working)],
            current: [session("a", .awaitingInput)],
            now: t0.addingTimeInterval(61)
        )
        #expect(sink.delivered.count == 2)
    }

    @Test func debounceIsPerStateNotPerSession() {
        let (notifier, sink) = make(debounce: 60)
        notifier.notifyIfNeeded(
            previous: [session("a", .working)],
            current: [session("a", .awaitingInput)],
            now: t0
        )
        // A different attention state for the same session is a different
        // event and deserves its own alert.
        notifier.notifyIfNeeded(
            previous: [session("a", .working)],
            current: [session("a", .blocked)],
            now: t0.addingTimeInterval(1)
        )
        #expect(sink.delivered.count == 2)
    }

    @Test func debounceIsPerSessionNotGlobal() {
        let (notifier, sink) = make(debounce: 60)
        notifier.notifyIfNeeded(
            previous: [session("a", .working), session("b", .working)],
            current: [session("a", .awaitingInput), session("b", .awaitingInput)],
            now: t0
        )
        #expect(sink.delivered.count == 2, "two different sessions must each alert")
        #expect(Set(sink.delivered.map(\.sessionID)) == ["a", "b"])
    }

    // MARK: - Edge cases

    @Test func sessionUnseenBeforeStillNotifies() {
        // First sighting of an already-waiting session: there is no previous
        // entry, so it counts as a transition and should alert.
        let (notifier, sink) = make()
        notifier.notifyIfNeeded(previous: [], current: [session("a", .awaitingInput)], now: t0)
        #expect(sink.delivered.count == 1)
    }

    @Test func emptyCurrentListIsHarmless() {
        let (notifier, sink) = make()
        notifier.notifyIfNeeded(previous: [session("a", .awaitingInput)], current: [], now: t0)
        #expect(sink.delivered.isEmpty)
    }
}
