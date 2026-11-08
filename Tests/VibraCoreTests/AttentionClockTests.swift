import Foundation
import Testing
@testable import VibraCore

/// The label a waiting row carries is only as good as this clock: "your turn
/// for 4 minutes" has to mean Vibra saw the turn end four minutes ago, and
/// "first seen" has to mean it did not.
struct AttentionClockTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func session(
        _ id: String,
        _ state: SessionState,
        cwd: String = "/fake/proj",
        at: Date? = nil
    ) -> Session {
        let stamp = at ?? t0
        return Session(
            id: id, agent: .claudeCode, cwd: cwd, state: state,
            startedAt: stamp, lastActivity: stamp)
    }

    private func key(_ id: String) -> SessionKey { SessionKey(agent: .claudeCode, id: id) }

    @Test func firstPassOfAWaitingSessionIsFirstSeen() {
        var clock = AttentionClock()
        let starts = clock.advance(to: [session("a", .awaitingInput)], now: t0)
        #expect(starts[key("a")] == .firstSeen(t0))
    }

    @Test func unchangedStateKeepsItsOriginalStart() {
        var clock = AttentionClock()
        _ = clock.advance(to: [session("a", .awaitingInput)], now: t0)
        let later = clock.advance(to: [session("a", .awaitingInput)], now: t0.addingTimeInterval(240))
        #expect(later[key("a")] == .firstSeen(t0), "waiting longer is still the same wait")
    }

    @Test func eachObservedTransitionToAnAttentionStateIsObserved() {
        var clock = AttentionClock()
        let t1 = t0.addingTimeInterval(10)
        let t2 = t0.addingTimeInterval(20)
        let t3 = t0.addingTimeInterval(30)

        #expect(clock.advance(to: [session("a", .working)], now: t0).isEmpty)

        // A session Vibra watched start working and then finish is observed,
        // not merely first seen.
        #expect(clock.advance(to: [session("a", .awaitingInput)], now: t1)[key("a")] == .observed(t1))

        // Answered: the wait is over and its start is gone.
        #expect(clock.advance(to: [session("a", .working)], now: t2).isEmpty)

        // Upgraded to an approval prompt: a second observed transition.
        #expect(clock.advance(to: [session("a", .blocked)], now: t3)[key("a")] == .observed(t3))
    }

    @Test func vanishThenReturnIsFirstSeenAgain() {
        var clock = AttentionClock()
        _ = clock.advance(to: [session("a", .awaitingInput)], now: t0)

        // Gone from the snapshot: the entry is pruned.
        #expect(clock.advance(to: [], now: t0.addingTimeInterval(60)).isEmpty)

        let back = clock.advance(to: [session("a", .awaitingInput)], now: t0.addingTimeInterval(120))
        #expect(back[key("a")] == .firstSeen(t0.addingTimeInterval(120)))
    }

    @Test func twoSessionsInOneProjectAreTrackedSeparately() {
        var clock = AttentionClock()
        let t1 = t0.addingTimeInterval(60)
        let sameCwd = "/fake/payments"

        let first = clock.advance(
            to: [session("a", .awaitingInput, cwd: sameCwd), session("b", .working, cwd: sameCwd)],
            now: t0)
        #expect(first[key("a")] == .firstSeen(t0))
        #expect(first[key("b")] == nil)

        let second = clock.advance(
            to: [session("a", .awaitingInput, cwd: sameCwd), session("b", .awaitingInput, cwd: sameCwd)],
            now: t1)
        #expect(second[key("a")] == .firstSeen(t0), "a's wait is untouched by b")
        #expect(second[key("b")] == .observed(t1))
    }

    @Test func onlyWaitingSessionsAreReturned() {
        var clock = AttentionClock()
        let starts = clock.advance(
            to: [session("a", .idle), session("b", .stalled), session("c", .awaitingInput)],
            now: t0)
        #expect(Set(starts.keys) == [key("c")])
    }
}
