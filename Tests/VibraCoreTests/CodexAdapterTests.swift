import XCTest
@testable import VibraCore

final class CodexAdapterTests: XCTestCase {
    func testDiscoversSessionWithModelAndCwd() throws {
        let adapter = CodexAdapter(sessionsRoot: fixtureURL("Fixtures/codex"))
        XCTAssertTrue(adapter.isAvailable)

        let sessions = try adapter.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.agent, .codex)
        XCTAssertEqual(session.id, "codex-fixture-0001")
        XCTAssertEqual(session.cwd, "/Users/jianwang/workplace/vibra")
        XCTAssertEqual(session.model, "gpt-5.6-sol")

        // last thread_token_usage wins (cumulative)
        XCTAssertEqual(session.usage.input, 2400)
        XCTAssertEqual(session.usage.output, 700) // 640 output + 60 reasoning
        XCTAssertEqual(session.usage.cacheRead, 1500)
        XCTAssertEqual(session.usage.cacheCreation, 25)
    }
}
