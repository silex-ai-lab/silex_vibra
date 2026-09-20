import XCTest
@testable import VibraCore

final class ClaudeCodeAdapterTests: XCTestCase {
    func testDiscoversSessionWithUsageAndCwd() throws {
        let adapter = ClaudeCodeAdapter(projectsRoot: fixtureURL("Fixtures/claude"))
        XCTAssertTrue(adapter.isAvailable)

        let sessions = try adapter.discoverSessions()
        XCTAssertEqual(sessions.count, 1)

        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.agent, .claudeCode)
        XCTAssertEqual(session.id, "3f3f3f3f-3f3f-3f3f-3f3f-3f3f3f3f3f3f")
        XCTAssertEqual(session.cwd, "/Users/jianwang/workplace/vibra")
        XCTAssertEqual(session.model, "claude-opus-5")
        XCTAssertEqual(session.gitBranch, "main")

        // usage summed across both assistant records
        XCTAssertEqual(session.usage.input, 130)
        XCTAssertEqual(session.usage.output, 70)
        XCTAssertEqual(session.usage.cacheCreation, 10)
        XCTAssertEqual(session.usage.cacheRead, 240)
        XCTAssertTrue(session.usage.total > 0)

        // oldest timestamp -> startedAt, newest -> lastActivity
        XCTAssertLessThan(session.startedAt, session.lastActivity)
    }

    func testMissingRootYieldsEmpty() throws {
        let adapter = ClaudeCodeAdapter(projectsRoot: fixtureURL("Fixtures/does-not-exist"))
        XCTAssertFalse(adapter.isAvailable)
        XCTAssertEqual(adapter.discoverSessionsSafely(), [])
    }
}
