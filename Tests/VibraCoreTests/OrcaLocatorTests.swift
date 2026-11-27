import Foundation
import Testing
@testable import VibraCore

struct TTYOwnerTests {
    @Test(arguments: [
        ("/Users/me/Library/Application Support/orca/daemon-host/macos/terminal-host-153b0a90", ProcessInspector.TTYOwner.multiplexer("Orca")),
        ("/Applications/Orca.app/Contents/Frameworks/Orca Helper.app/Contents/MacOS/Orca Helper", .multiplexer("Orca")),
        ("/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", .emulator("Terminal")),
        ("/Applications/iTerm.app/Contents/MacOS/iTerm2", .emulator("iTerm2")),
        ("iTermServer-3.5.14", .emulator("iTerm2")),
        ("/Applications/Ghostty.app/Contents/MacOS/ghostty", .emulator("Ghostty")),
        ("wezterm-gui", .emulator("WezTerm")),
        ("tmux", .multiplexer("tmux")),
        ("tmux: server", .multiplexer("tmux")),
        ("SCREEN", .multiplexer("screen")),
        ("/Users/me/.local/bin/herdr", .multiplexer("herdr")),
    ])
    func namedOwners(path: String, owner: ProcessInspector.TTYOwner) {
        #expect(ProcessInspector.owner(ofExecutable: path) == owner)
    }

    @Test(arguments: ["terminal-host-153b0a90", "screencapture", "my-terminal-tool", "-/bin/zsh", "/usr/bin/login"])
    func aNameThatOnlyContainsAnOwnersNameIsNotThatOwner(path: String) {
        #expect(ProcessInspector.owner(ofExecutable: path) == nil)
    }
}

struct ProcessEnvironmentTests {
    private func procArgs(arguments: [String], environment: [String], padding: Int = 3) -> [UInt8] {
        var bytes = withUnsafeBytes(of: Int32(arguments.count).littleEndian) { Array($0) }
        bytes += Array("/usr/bin/agent".utf8) + [UInt8](repeating: 0, count: 1 + padding)
        for entry in arguments + environment { bytes += Array(entry.utf8) + [0] }
        bytes += [0] + Array("stack_guard=0x1".utf8) + [0]
        return bytes
    }

    @Test func readsOnlyTheNamedVariable() {
        let bytes = procArgs(arguments: ["agent"], environment: ["ORCA_AGENT_HOOK_TOKEN=secret", "ORCA_TERMINAL_HANDLE=term_a"])
        #expect(ProcessInspector.environmentValue("ORCA_TERMINAL_HANDLE", inProcArgs: bytes) == "term_a")
    }

    @Test func anArgumentSpelledLikeTheVariableDoesNotAnswer() {
        let bytes = procArgs(arguments: ["agent", "ORCA_TERMINAL_HANDLE=term_forged"], environment: ["HOME=/h"])
        #expect(ProcessInspector.environmentValue("ORCA_TERMINAL_HANDLE", inProcArgs: bytes) == nil)
    }

    @Test func nothingAfterTheEnvironmentAnswers() {
        let bytes = procArgs(arguments: ["agent"], environment: ["HOME=/h"])
        #expect(ProcessInspector.environmentValue("stack_guard", inProcArgs: bytes) == nil)
    }

    @Test func aLongerNameDoesNotMatch() {
        let bytes = procArgs(arguments: ["agent"], environment: ["ORCA_TERMINAL_HANDLE_OLD=term_a"])
        #expect(ProcessInspector.environmentValue("ORCA_TERMINAL_HANDLE", inProcArgs: bytes) == nil)
    }

    @Test(arguments: [[UInt8](), [1, 0, 0], [255, 255, 255, 255, 65, 0]])
    func malformedBlocksReadAsNothing(bytes: [UInt8]) {
        #expect(ProcessInspector.environmentValue("HOME", inProcArgs: bytes) == nil)
    }

    @Test func readsThisProcessFromTheKernel() throws {
        let expected = try #require(ProcessInfo.processInfo.environment["PATH"])
        #expect(ProcessInspector.environmentValue("PATH", of: getpid()) == expected)
    }
}

struct OrcaLocatorTests {
    @Test func acceptsTheShapeOrcaIssues() {
        let handle = "term_1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed"
        #expect(OrcaLocator.validHandle(handle) == handle)
    }

    @Test(arguments: ["", "term_", "--json", "term_a b", "term_a;rm", "x_term_a", "term_a\nterm_b"])
    func rejectsAnythingElse(value: String) {
        #expect(OrcaLocator.validHandle(value) == nil)
    }

    @Test func acceptsAnAgentSessionID() {
        let id = "aaca57dd-9549-4e28-92b3-e9afe0988eb5"
        #expect(OrcaLocator.validAgentSessionID(id) == id)
    }

    @Test(arguments: ["", "--json", "aaca57dd", "aaca57dd-9549-4e28-92b3-e9afe0988eb5 --json", "orca_session_id:aaca57dd-9549-4e28-92b3-e9afe0988eb5"])
    func rejectsAnythingButAnAgentSessionID(value: String) {
        #expect(OrcaLocator.validAgentSessionID(value) == nil)
    }

    private func agentShow(places: String) -> Data {
        Data(#"{"ok":true,"result":{"orcaSessionId":"a","kind":"chat","places":[\#(places)]}}"#.utf8)
    }

    @Test func readsTheWorktreeAChatIsOpenIn() {
        let reply = agentShow(places: #"{"kind":"chat","worktreeId":"1ecb0a55::/Users/me/code/app","paneKey":"p"}"#)
        #expect(OrcaLocator.worktreeID(inAgentShow: reply) == "1ecb0a55::/Users/me/code/app")
    }

    @Test func aChatOpenInTwoWorktreesNamesNeither() {
        let reply = agentShow(places: #"{"worktreeId":"a::/one"},{"worktreeId":"b::/two"}"#)
        #expect(OrcaLocator.worktreeID(inAgentShow: reply) == nil)
    }

    @Test func aChatResumedInTwoPanesOfOneWorktreeNamesIt() {
        let reply = agentShow(places: #"{"worktreeId":"a::/one"},{"worktreeId":"a::/one"}"#)
        #expect(OrcaLocator.worktreeID(inAgentShow: reply) == "a::/one")
    }

    @Test(arguments: ["", #"{"worktreeId":"folder:fb165388-6814-4dc6-ae71-d3832637d549"}"#, #"{"paneKey":"p"}"#])
    func aClosedChatOrAFolderWorkspaceNamesNoWorktree(places: String) {
        #expect(OrcaLocator.worktreeID(inAgentShow: agentShow(places: places)) == nil)
    }

    @Test func aChatAlsoOpenInAFolderWorkspaceNamesNeither() {
        let reply = agentShow(places: #"{"worktreeId":"a::/one"},{"worktreeId":"folder:fb165388"}"#)
        #expect(OrcaLocator.worktreeID(inAgentShow: reply) == nil)
    }

    @Test func aReplyThatIsNotAnAgentNamesNoWorktree() {
        #expect(OrcaLocator.worktreeID(inAgentShow: Data(#"{"ok":false,"error":{"code":"not_found"}}"#.utf8)) == nil)
        #expect(OrcaLocator.worktreeID(inAgentShow: Data("not json".utf8)) == nil)
    }
}
