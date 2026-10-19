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
