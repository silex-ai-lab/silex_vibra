import Testing
@testable import VibraCore

/// Names are the executables seen in real ancestries, as `ps -o comm=` prints them.
struct TTYOwnerTests {

    @Test func orcaDaemonsAreMultiplexersNotTheTerminalApp() {
        #expect(ProcessInspector.ttyOwner(executable: "orca-terminal-host") == .multiplexer("orca"))
        #expect(ProcessInspector.ttyOwner(
            executable: "/Applications/Orca.app/Contents/Frameworks/Orca Helper.app/Contents/MacOS/Orca Helper"
        ) == .multiplexer("orca"))
    }

    @Test func existingEmulatorsAndMultiplexersKeepTheirResults() {
        #expect(ProcessInspector.ttyOwner(
            executable: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
        ) == .emulator("Terminal"))
        #expect(ProcessInspector.ttyOwner(executable: "iTermServer-3.7.6") == .emulator("iTerm2"))
        #expect(ProcessInspector.ttyOwner(executable: "herdr") == .multiplexer("herdr"))
        #expect(ProcessInspector.ttyOwner(executable: "tmux") == .multiplexer("tmux"))
    }

    @Test func shellsAndAgentsSayNothingAboutTheTerminal() {
        #expect(ProcessInspector.ttyOwner(executable: "-zsh") == nil)
        #expect(ProcessInspector.ttyOwner(executable: "login") == nil)
        #expect(ProcessInspector.ttyOwner(executable: "claude") == nil)
    }
}

struct OrcaTerminalHandleTests {

    @Test func readsHandleFromPsEnvironmentTail() {
        let line = "claude --dangerously-skip-permissions TERM_PROGRAM=Orca ORCA_TAB_ID=abc ORCA_TERMINAL_HANDLE=term_1111 HOME=/Users/x"
        #expect(ProcessInspector.orcaTerminalHandle(psCommandWithEnvironment: line) == "term_1111")
    }

    @Test func absentOrEmptyHandleIsNil() {
        #expect(ProcessInspector.orcaTerminalHandle(psCommandWithEnvironment: "claude TERM_PROGRAM=iTerm.app HOME=/Users/x") == nil)
        #expect(ProcessInspector.orcaTerminalHandle(psCommandWithEnvironment: "claude ORCA_TERMINAL_HANDLE= HOME=/Users/x") == nil)
    }
}
