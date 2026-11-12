import Foundation
import Testing
@testable import VibraCore

struct HandledTurnsTests {
    let finished = Date(timeIntervalSince1970: 1_800_000_000)

    func session(_ id: String, _ state: SessionState, lastActivity: Date? = nil) -> Session {
        Session(id: id, agent: .codex, cwd: "/p", state: state,
                startedAt: finished, lastActivity: lastActivity ?? finished)
    }

    @Test func aTurnYouWentBackToIsNoLongerYourTurn() {
        var handled = HandledTurns()
        handled.markHandled(session("a", .awaitingInput), now: finished + 60)
        let shown = handled.applied(to: [session("a", .awaitingInput), session("b", .awaitingInput)])
        #expect(shown.map(\.state) == [.idle, .awaitingInput])
    }

    @Test func theNextTurnAsksAgain() {
        var handled = HandledTurns()
        handled.markHandled(session("a", .awaitingInput), now: finished + 60)
        let nextTurn = session("a", .awaitingInput, lastActivity: finished + 600)
        #expect(handled.applied(to: [nextTurn]).map(\.state) == [.awaitingInput])
    }

    @Test func onlyYourTurnCanBeHandled() {
        // Jumping to an approval prompt does not answer it.
        var handled = HandledTurns()
        handled.markHandled(session("a", .blocked), now: finished + 60)
        handled.markHandled(session("b", .working), now: finished + 60)
        #expect(handled == HandledTurns())
        #expect(handled.applied(to: [session("a", .blocked)]).map(\.state) == [.blocked])
    }

    @Test func survivesARelaunch() {
        let store = DictionarySettingsStore()
        var handled = HandledTurns()
        handled.markHandled(session("a", .awaitingInput), now: finished + 60)
        handled.save(to: store)
        let reloaded = HandledTurns.load(from: store)
        #expect(reloaded.applied(to: [session("a", .awaitingInput)]).map(\.state) == [.idle])
    }

    @Test func malformedPreferenceLoadsEmpty() {
        let store = DictionarySettingsStore([HandledTurns.key: ["nonsense": "x", "codex|a": "soon"]])
        #expect(HandledTurns.load(from: store) == HandledTurns())
    }

    @Test func pruningDropsWhatCanNoLongerApply() {
        var handled = HandledTurns()
        handled.markHandled(session("gone", .awaitingInput), now: finished + 60)
        handled.markHandled(session("replied", .awaitingInput), now: finished + 60)
        handled.markHandled(session("waiting", .awaitingInput), now: finished + 60)
        let current = [
            session("replied", .working, lastActivity: finished + 120),
            session("waiting", .awaitingInput),
        ]
        handled.prune(keeping: current)
        var expected = HandledTurns()
        expected.markHandled(session("waiting", .awaitingInput), now: finished + 60)
        #expect(handled == expected)
    }
}
