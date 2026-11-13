import Foundation
import Testing
@testable import VibraCore

/// `WaitStats.format`: the shared fixture scenarios byte for byte, then each
/// rule of "Window and arithmetic" and "Output" on hand-computed folds.
struct WaitStatsTests {
    // MARK: - Shared fixtures

    private struct Scenario: Decodable {
        let name: String
        let tz: String
        let args: String
        let expected: String
        let sentinel: String?
    }

    private struct ScenarioFile: Decodable {
        let scenarios: [Scenario]
    }

    private enum FixtureError: Error {
        case missingArgument(String)
        case badWindow(String)
    }

    private func window(from args: String, timeZone identifier: String) throws -> WaitWindow {
        let parts = args.split(separator: " ").map(String.init)
        func value(_ flag: String) throws -> String {
            guard let index = parts.firstIndex(of: flag), index + 1 < parts.count else {
                throw FixtureError.missingArgument(flag)
            }
            return parts[index + 1]
        }
        let from = try value("--from")
        let to = try value("--to")
        let zone = try #require(TimeZone(identifier: identifier))
        guard case .success(let window) = WaitWindow.parse(
            days: nil, from: .some(from), to: .some(to), now: 0, timeZone: zone)
        else { throw FixtureError.badWindow("\(args) \(identifier)") }
        return window
    }

    /// Every scenario the oracle also runs, through `WaitIngest` and the real
    /// fixture tree, compared with the hand-written expected text.
    @Test func everySharedScenarioMatchesByteForByte() async throws {
        let data = try Data(contentsOf: fixtureURL("Fixtures/waits/scenarios.json"))
        let all = try JSONDecoder().decode(ScenarioFile.self, from: data).scenarios
        #expect(all.count >= 8)

        for scenario in all {
            let home = fixtureURL("Fixtures/waits/\(scenario.name)/home")
            let window = try window(from: scenario.args, timeZone: scenario.tz)
            let adapters: [any AgentAdapter] = [
                ClaudeCodeAdapter(projectsRoot: home.appendingPathComponent(".claude/projects")),
                CodexAdapter(sessionsRoot: home.appendingPathComponent(".codex/sessions")),
            ]
            let rows = await WaitIngest(adapters: adapters).collect(since: window.lo)
            let text = WaitStats.format(rows, window: window)
            #expect(text == scenario.expected, "scenario \(scenario.name)")
            if let sentinel = scenario.sentinel {
                #expect(!text.contains(sentinel), "scenario \(scenario.name) leaks its sentinel")
            }
        }
    }

    // MARK: - Builders

    private let base: EpochMs = 1_700_000_000_000

    /// A window that holds every timestamp the unit cases use unless one is
    /// passed explicitly.
    private var wideWindow: WaitWindow {
        WaitWindow(lo: base - 86_400_000, hi: base + 86_400_000)
    }

    private func wait(
        _ kind: WaitKind, _ startOffset: EpochMs, _ endOffset: EpochMs,
        _ answer: WaitAnswer? = nil
    ) -> HumanWait {
        HumanWait(kind: kind, start: base + startOffset, end: base + endOffset, answer: answer)
    }

    private func fold(
        _ waits: [HumanWait], events: [EpochMs] = [], prompt: Bool = true,
        openSince: EpochMs? = nil
    ) -> WaitFold {
        WaitFold(waits: waits, humanEvents: events, hasHumanPrompt: prompt, openSince: openSince)
    }

    private func format(
        _ folds: [WaitFold], agent: AgentKind = .codex, window: WaitWindow? = nil
    ) -> String {
        WaitStats.format(folds.map { (agent: agent, fold: $0) }, window: window ?? wideWindow)
    }

    // MARK: - Quantiles

    @Test func quantilesForOneTwoFourAndFiveValues() {
        let one = format([fold([wait(.turn, 0, 1_000)])])
        #expect(one.contains("seconds agent=codex kind=turn p25=1 p50=1 p75=1 n=1"))

        // 1000 and 3000 ms: h = 0.25, 0.5, 0.75 -> 1500, 2000, 2500 ms.
        let two = format([fold([wait(.turn, 0, 1_000), wait(.turn, 0, 3_000)])])
        #expect(two.contains("seconds agent=codex kind=turn p25=1 p50=2 p75=2 n=2"))

        // 1..4 s: h = 0.75, 1.5, 2.25 -> 1750, 2500, 3250 ms.
        let four = format([fold((1...4).map { wait(.turn, 0, EpochMs($0) * 1_000) })])
        #expect(four.contains("seconds agent=codex kind=turn p25=1 p50=2 p75=3 n=4"))

        // 1..5 s: h = 1, 2, 3 -> exactly 2000, 3000, 4000 ms.
        let five = format([fold((1...5).map { wait(.turn, 0, EpochMs($0) * 1_000) })])
        #expect(five.contains("seconds agent=codex kind=turn p25=2 p50=3 p75=4 n=5"))

        // Every line ends in exactly one newline; with lines the output is not
        // empty and does not end in a blank line.
        #expect(five.hasSuffix("\n"))
        #expect(!five.hasSuffix("\n\n"))
    }

    @Test func secondsAndMinutesAreFloored() {
        // 119 999 ms is 119.999 s and 1.999 min.
        let text = format([fold([wait(.turn, 0, 119_999)], events: [base - 1_000])])
        #expect(text.contains("seconds agent=codex kind=turn p25=119 p50=119 p75=119 n=1"))
        #expect(text.contains(
            "blocked agent=codex scope=all unit=min p25=1 p50=1 p75=1 total=1 n=1"))
    }

    /// Exactly the cap is not over it; one millisecond more is.
    @Test func capBoundaryIsStrictlyGreaterThanTwoHours() {
        let exact = format([fold([wait(.turn, 0, 7_200_000)])])
        #expect(!exact.contains("over_cap"))
        #expect(exact.contains("seconds agent=codex kind=turn p25=7200 p50=7200 p75=7200 n=1"))

        let over = format([fold([wait(.turn, 0, 7_200_000), wait(.turn, 0, 7_200_001)])])
        #expect(over.contains("over_cap agent=codex kind=turn n=1"))
        #expect(over.contains("seconds agent=codex kind=turn p25=7200 p50=7200 p75=7200 n=2"))
    }

    // MARK: - Blocked time

    @Test func blockedUnionsOverlappingTouchingAndNestedIntervals() {
        // [0,120s) and [60s,180s) overlap: 3 min, not the 4 min of a sum.
        let overlapping = format([fold([wait(.turn, 0, 120_000), wait(.turn, 60_000, 180_000)])])
        #expect(overlapping.contains(
            "blocked agent=codex scope=all unit=min p25=3 p50=3 p75=3 total=3 n=1"))

        // Touching halves join without a lost or doubled millisecond.
        let touching = format([fold([wait(.turn, 0, 90_000), wait(.turn, 90_000, 150_000)])])
        #expect(touching.contains(
            "blocked agent=codex scope=all unit=min p25=2 p50=2 p75=2 total=2 n=1"))

        // A nested wait adds nothing to the outer one.
        let nested = format([fold([wait(.turn, 0, 180_000), wait(.turn, 30_000, 120_000)])])
        #expect(nested.contains(
            "blocked agent=codex scope=all unit=min p25=3 p50=3 p75=3 total=3 n=1"))

        // A zero-length wait contributes nothing.
        let empty = format([fold([wait(.turn, 50_000, 50_000), wait(.turn, 0, 60_000)])])
        #expect(empty.contains(
            "blocked agent=codex scope=all unit=min p25=1 p50=1 p75=1 total=1 n=1"))
    }

    /// A session with a prompt and no waits is a session, and counts as 0.
    @Test func aSessionWithoutWaitsCountsAsZero() {
        let text = format([
            fold([wait(.turn, 0, 120_000)]),
            fold([], events: [base + 10_000]),
        ])
        // 0 and 120 000 ms: h = 0.25, 0.5, 0.75 -> 30 000, 60 000, 90 000 ms.
        #expect(text.contains(
            "blocked agent=codex scope=all unit=min p25=0 p50=1 p75=1 total=2 n=2"))
    }

    @Test func withinCapLeavesOverCapWaitsOutOfTheUnion() {
        let text = format([fold([
            wait(.turn, 0, 10_000_000),
            wait(.turn, 20_000_000, 20_060_000),
        ])])
        #expect(text.contains("over_cap agent=codex kind=turn n=1"))
        #expect(text.contains(
            "blocked agent=codex scope=all unit=min p25=121 p50=121 p75=121 total=121 n=1"))
        #expect(text.contains(
            "blocked agent=codex scope=within_cap unit=min p25=1 p50=1 p75=1 total=1 n=1"))
    }

    // MARK: - Window

    /// A wait is in the window by its END, on a half-open interval: `end == lo`
    /// counts and `end == hi` does not.
    @Test func windowMembershipIsByEndAndHalfOpen() {
        let window = WaitWindow(lo: base, hi: base + 1_000_000)

        let atLo = format(
            [fold([wait(.turn, -50_000, 0)], events: [base])], window: window)
        #expect(atLo.contains("sessions agent=codex n=1"))
        #expect(atLo.contains("waits agent=codex kind=turn n=1"))
        #expect(atLo.contains("seconds agent=codex kind=turn p25=50 p50=50 p75=50 n=1"))

        let beforeHi = format([fold([wait(.turn, 900_000, 999_999)])], window: window)
        #expect(beforeHi.contains("waits agent=codex kind=turn n=1"))

        let atHi = format(
            [fold([wait(.turn, 900_000, 1_000_000)], events: [base])], window: window)
        #expect(atHi.contains("sessions agent=codex n=1"))
        #expect(!atHi.contains("waits agent=codex kind=turn"))
        #expect(atHi.contains(
            "blocked agent=codex scope=all unit=min p25=0 p50=0 p75=0 total=0 n=1"))
    }

    /// A session is in the window by a human event or by a wait in it, so a
    /// dialog answered inside counts even when every prompt came before.
    @Test func aSessionCountsByItsPromptOrByAWaitInTheWindow() {
        let window = WaitWindow(lo: base, hi: base + 1_000_000)

        let byEvent = format([fold([], events: [base + 10_000])], window: window)
        #expect(byEvent.contains("sessions agent=codex n=1"))
        #expect(byEvent.contains(
            "blocked agent=codex scope=all unit=min p25=0 p50=0 p75=0 total=0 n=1"))
        #expect(!byEvent.contains("waits agent=codex"))

        let byWait = format(
            [fold([wait(.question, 500_000, 600_000, .accept)],
                  events: [base - 86_400_000])], window: window)
        #expect(byWait.contains("sessions agent=codex n=1"))
        #expect(byWait.contains("waits agent=codex kind=question answer=accept n=1"))

        // Neither: no lines at all, for this agent.
        let neither = format(
            [fold([wait(.question, 500_000, 600_000, .accept)],
                  events: [base - 86_400_000])],
            window: WaitWindow(lo: base + 2_000_000, hi: base + 3_000_000))
        #expect(neither.isEmpty)
    }

    /// Ordinals are numbered over the whole transcript, so a window that cuts
    /// the early questions does not renumber the rest.
    @Test func ordinalsAreAssignedBeforeTheWindowFilter() {
        let window = WaitWindow(lo: base + 150_000, hi: base + 1_000_000)
        let waits = (0..<4).map {
            wait(.question, EpochMs($0) * 100_000, EpochMs($0) * 100_000 + 10_000, .accept)
        }
        let text = format([fold(waits, events: [base + 200_000])], window: window)
        // The two in-window waits are ordinals 3 and 4, so the buckets are 2-3
        // and 4-7: renumbering inside the window would print ordinal=1.
        #expect(text.contains(
            "seconds agent=codex kind=question ordinal=2-3 p25=10 p50=10 p75=10 n=1"))
        #expect(text.contains(
            "seconds agent=codex kind=question ordinal=4-7 p25=10 p50=10 p75=10 n=1"))
        #expect(!text.contains("ordinal=1 "))
    }

    /// Buckets number from 1 across both kinds: 1, 2-3, 4-7, 8+.
    @Test func ordinalBucketsNumberAcrossBothKinds() {
        let kinds: [WaitKind] = [.question, .approval]
        let waits = (0..<8).map { index in
            let start = EpochMs(index) * 1_000_000
            return wait(kinds[index % 2], start, start + 60_000, .accept)
        }
        let text = format([fold(waits)])
        // Questions are ordinals 1, 3, 5, 7; approvals 2, 4, 6, 8.
        #expect(text.contains("seconds agent=codex kind=question ordinal=1 p25=60 p50=60 p75=60 n=1"))
        #expect(text.contains(
            "seconds agent=codex kind=question ordinal=2-3 p25=60 p50=60 p75=60 n=1"))
        #expect(text.contains(
            "seconds agent=codex kind=question ordinal=4-7 p25=60 p50=60 p75=60 n=2"))
        #expect(text.contains(
            "seconds agent=codex kind=approval ordinal=2-3 p25=60 p50=60 p75=60 n=1"))
        #expect(text.contains(
            "seconds agent=codex kind=approval ordinal=4-7 p25=60 p50=60 p75=60 n=2"))
        #expect(text.contains("seconds agent=codex kind=approval ordinal=8+ p25=60 p50=60 p75=60 n=1"))
    }

    // MARK: - Groups, order and omission

    @Test func linesAreGroupedInOrderAndEmptyOnesAreOmitted() {
        let text = format([fold([
            wait(.turn, 0, 60_000),
            wait(.question, 100_000, 130_000, .accept),
            wait(.approval, 200_000, 7_400_001, .reject),
        ], events: [base - 1_000], openSince: base + 9_000_000)])
        let expected = """
            sessions agent=codex n=1
            open agent=codex n=1
            waits agent=codex kind=approval answer=reject n=1
            waits agent=codex kind=question answer=accept n=1
            waits agent=codex kind=turn n=1
            over_cap agent=codex kind=approval n=1
            seconds agent=codex kind=approval p25=7200 p50=7200 p75=7200 n=1
            seconds agent=codex kind=question p25=30 p50=30 p75=30 n=1
            seconds agent=codex kind=turn p25=60 p50=60 p75=60 n=1
            seconds agent=codex kind=approval ordinal=2-3 p25=7200 p50=7200 p75=7200 n=1
            seconds agent=codex kind=question ordinal=1 p25=30 p50=30 p75=30 n=1
            blocked agent=codex scope=all unit=min p25=121 p50=121 p75=121 total=121 n=1
            blocked agent=codex scope=within_cap unit=min p25=1 p50=1 p75=1 total=1 n=1

            """
        #expect(text == expected)
        // No zero-count line for an answer or kind that never appears.
        #expect(!text.contains("n=0"))
        #expect(!text.contains("answer=unknown"))
    }

    @Test func bothAgentsPrintWithTheAgentInTheKey() {
        let text = WaitStats.format([
            (agent: .codex, fold: fold([wait(.turn, 0, 60_000)])),
            (agent: .claudeCode, fold: fold([wait(.turn, 0, 120_000)])),
        ], window: wideWindow)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.first == "sessions agent=claudeCode n=1")
        #expect(lines.dropFirst().first == "sessions agent=codex n=1")
        #expect(text.contains("seconds agent=claudeCode kind=turn p25=120 p50=120 p75=120 n=1"))
        #expect(text.contains("seconds agent=codex kind=turn p25=60 p50=60 p75=60 n=1"))
    }

    @Test func noLinesWhenNothingIsEligible() {
        #expect(WaitStats.format([], window: wideWindow).isEmpty)
        // Ineligible: waits but no human prompt anywhere.
        #expect(format([fold([wait(.turn, 0, 60_000)], prompt: false)]).isEmpty)
        // A session with neither a human event nor a wait in the window.
        #expect(format(
            [fold([wait(.turn, 0, 60_000)], events: [base - 10_000])],
            window: WaitWindow(lo: base + 1_000_000, hi: base + 2_000_000)).isEmpty)
    }
}
