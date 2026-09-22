import Foundation
import Testing
@testable import VibraCore

/// A herdr jump moves the user's focus in two places at once - the herdr tab
/// and the terminal window - so each link has to be exact. The process tables
/// here are shaped like real `ps -axo pid=,ppid=,tty=,args=` output from a
/// machine running the default herdr session and a named one side by side.
struct HerdrLocatorTests {

    private let ps = """
      1     0 ??       /sbin/launchd
    21755     1 ??       /Users/demo/.local/bin/herdr server
    32794     1 ??       herdr --session vibra-test server
    40000 21755 ttys001  -zsh
    40010 40000 ttys001  /Users/demo/.local/share/claude/versions/2.1/claude
    41000 32794 ttys010  -zsh
    41010 41000 ttys010  sleep 900
    61615 61614 ttys000  -zsh
    55879 61615 ttys000  herdr
    55900 61615 ttys002  herdr --session vibra-test
    55950 61615 ttys003  herdr pane list
    70000 61615 ttys004  /bin/zsh
    """

    private var table: [Int32: ProcessEntry] { HerdrLocator.parseProcessTable(ps) }

    @Test func parsesProcessTableIncludingArgsWithSpaces() {
        let t = table
        #expect(t[32794]?.args == "herdr --session vibra-test server")
        #expect(t[32794]?.tty == nil)
        #expect(t[40010]?.tty == "ttys001")
    }

    @Test func routesAgentInDefaultSessionToItsPaneShell() {
        let route = HerdrLocator.route(from: 40010, in: table)
        #expect(route == HerdrRoute(
            serverPID: 21755,
            session: nil,
            paneShellPID: 40000,
            executable: "/Users/demo/.local/bin/herdr"
        ))
    }

    @Test func routesNamedSession() {
        let route = HerdrLocator.route(from: 41010, in: table)
        #expect(route?.session == "vibra-test")
        #expect(route?.paneShellPID == 41000)
        #expect(route?.executable == nil)
    }

    @Test func processOutsideHerdrHasNoRoute() {
        #expect(HerdrLocator.route(from: 70000, in: table) == nil)
        // A herdr *client* is not a server: its children are not panes.
        #expect(HerdrLocator.route(from: 55879, in: table) == nil)
    }

    @Test func clientsAreMatchedToTheirSessionOnly() {
        #expect(HerdrLocator.clientTTYs(of: nil, in: table) == ["ttys000"])
        #expect(HerdrLocator.clientTTYs(of: "vibra-test", in: table) == ["ttys002"])
        // One-shot CLI calls are never clients.
        #expect(!HerdrLocator.clientTTYs(of: nil, in: table).contains("ttys003"))
    }

    @Test func sessionAttachCountsAsAClient() {
        let t = HerdrLocator.parseProcessTable("""
        100 1 ttys005  herdr session attach work
        101 1 ttys006  herdr session attach default
        """)
        #expect(HerdrLocator.clientTTYs(of: "work", in: t) == ["ttys005"])
        #expect(HerdrLocator.clientTTYs(of: nil, in: t) == ["ttys006"])
    }

    @Test func serverStopIsNotAServer() {
        #expect(!HerdrLocator.isServer(["herdr", "server", "stop"]))
        #expect(HerdrLocator.isServer(["herdr", "--session", "x", "server"]))
    }

    @Test func parsesHerdrJSON() {
        let list = Data(#"""
        {"id":"cli:pane:list","result":{"type":"pane_list","panes":[
          {"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1"},
          {"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}]}}
        """#.utf8)
        #expect(HerdrLocator.parsePaneList(list).map(\.paneID) == ["w1:p1", "w2:p2"])
        #expect(HerdrLocator.parsePaneList(list).map(\.tabID) == ["w1:t1", "w2:t2"])

        let info = Data(#"""
        {"id":"cli:pane:process_info","result":{"process_info":{"pane_id":"w2:p2","shell_pid":32939},"type":"pane_process_info"}}
        """#.utf8)
        #expect(HerdrLocator.parseShellPID(info) == 32939)
        #expect(HerdrLocator.parseShellPID(Data(#"{"error":{"code":"x"}}"#.utf8)) == nil)
    }
}
