import Testing
@testable import VibraCore

struct CommandClassifierTests {
    private func classify(_ script: String) -> (kind: CheckKind, exitVisible: Bool)? {
        CommandClassifier.classify(script: script)
    }

    @Test(arguments: [
        "uv run --with x --python 3.12 pytest -q",
        "timeout 600 uv run --extra dev python -m pytest",
        "poetry run --quiet pytest",
        "(cd x && swift test) 2>&1",
    ])
    func runnersBehindOptionsAndSubshellsAreFound(script: String) {
        #expect(classify(script)?.kind == .test)
        #expect(classify(script)?.exitVisible == true)
    }

    @Test(arguments: [
        "python3 - <<'EOF'\nprint(1)\nEOF\nswift test",
        "cat <<-EOF\n\tswift build\n\tEOF\nswift test",
        "cat <<\"A B\"\nx\nA B\nswift test",
    ])
    func parsingResumesAfterAHeredoc(script: String) {
        #expect(classify(script)?.kind == .test)
        #expect(classify(script)?.exitVisible == true)
    }

    @Test func anUnterminatedHeredocSwallowsTheRest() {
        #expect(classify("cat <<EOF\nswift test") == nil)
    }

    @Test func aRunWrapperAroundAnotherProgramIsNotACheck() {
        #expect(classify("uv run script.py") == nil)
    }

    @Test func aLoopBodyIsACheckWithAMaskedExitStatus() {
        #expect(classify("for x in a; do swift test; done")?.kind == .test)
        #expect(classify("for x in a; do swift test; done")?.exitVisible == false)
    }

    @Test func theReceivingSideOfAPipeIsNotACheck() {
        #expect(classify("cat list | pytest") == nil)
    }

    @Test func aBackgroundedCheckHasNoVisibleExitStatus() {
        #expect(classify("swift test &")?.exitVisible == false)
    }

    @Test(arguments: [
        ("swift test", CheckKind.test), ("make test", .test), ("make check", .test),
        ("xcodebuild test -scheme X", .test), ("pytest -q", .test), ("python3 -m pytest", .test),
        ("python -m unittest", .test), ("npm test", .test), ("pnpm run test", .test),
        ("yarn test", .test), ("bun run test", .test), ("vitest run", .test), ("jest", .test),
        ("cargo test", .test), ("go test ./...", .test),
        ("swift build", .build), ("make build", .build), ("xcodebuild -scheme X build", .build),
        ("npm run build", .build), ("cargo build", .build), ("cargo check", .build),
        ("go build ./...", .build), ("tsc --noEmit", .build),
        ("make lint", .lint), ("npm run lint", .lint), ("pnpm typecheck", .lint),
        ("cargo clippy", .lint), ("go vet ./...", .lint), ("ruff check .", .lint),
        ("mypy src", .lint), ("eslint .", .lint),
    ])
    func runnerTable(script: String, kind: CheckKind) {
        #expect(classify(script)?.kind == kind)
    }

    @Test(arguments: [
        "git commit -m \"make test\"", "echo swift test", "ls", "swift package resolve",
        "make install", "grep -r 'pytest' .", "cat <<EOF\nswift test\nEOF", "",
    ])
    func notAChecks(script: String) {
        #expect(classify(script) == nil)
    }

    @Test(arguments: [
        "cd x && swift test", "(cd x && swift test)", "FOO=1 swift test", "env FOO=1 swift test",
        "time swift test", "command swift test", "timeout 60 swift test", "/usr/bin/swift test",
        "npx vitest", "bunx -y vitest", "pnpm exec vitest", "uv run pytest", "poetry run pytest",
        "swift test\n", "swift test;",
    ])
    func prefixesAreSkipped(script: String) {
        #expect(classify(script) != nil)
    }

    @Test func wholeCommandIsExitVisible() {
        #expect(classify("swift test")?.exitVisible == true)
        #expect(classify("cd x && swift test")?.exitVisible == true)
        #expect(classify("cd x && swift build && swift test")?.exitVisible == true)
        #expect(classify("swift test 2>&1")?.exitVisible == true)
        #expect(classify("swift test &> out.log")?.exitVisible == true)
    }

    @Test func pipeIsNeverExitProvenWithoutPipefail() {
        #expect(classify("swift test 2>&1 | tail -5")?.exitVisible == false)
        #expect(classify("swift test | grep FAIL")?.exitVisible == false)
        #expect(classify("swift test | grep FAIL")?.kind == .test)
    }

    @Test func pipefailMakesAPipeVisible() {
        #expect(classify("set -o pipefail; swift test | tail -5")?.exitVisible == true)
        #expect(classify("set -o pipefail && swift test | tail -5")?.exitVisible == true)
        #expect(classify("set -euo pipefail\nswift test | tail -5")?.exitVisible == true)
        #expect(classify("set -o pipefail; swift test | tail -5; echo done")?.exitVisible == false)
        #expect(classify("swift test | tail -5 && set -o pipefail")?.exitVisible == false)
    }

    @Test func maskingRule() {
        #expect(classify("swift test; echo done")?.exitVisible == false)
        #expect(classify("swift test || true")?.exitVisible == false)
        #expect(classify("swift test && echo ok")?.exitVisible == true)
        #expect(classify("swift test & wait")?.exitVisible == false)
        #expect(classify("swift test\necho done")?.exitVisible == false)
        #expect(classify("swift test && echo ok; echo done")?.exitVisible == false)
    }

    @Test func strongestKindWinsAndVisibilityNeedsAllChecks() {
        #expect(classify("swift build && swift test")?.kind == .test)
        #expect(classify("make lint && swift build")?.kind == .build)
        #expect(classify("swift build | tail -1; swift test")?.exitVisible == false)
        #expect(classify("swift build && swift test")?.exitVisible == true)
    }

    @Test func quotesAndEscapesDoNotSplit() {
        #expect(classify("git commit -m 'a && swift test'") == nil)
        #expect(classify("echo \"x; swift test\"") == nil)
        #expect(classify("swift test --filter 'a|b'")?.exitVisible == true)
        #expect(classify("swift test --filter a\\|b")?.exitVisible == true)
        #expect(classify("swift test \\\n  --parallel")?.exitVisible == true)
    }

    @Test func heredocBodyIsIgnored() {
        let script = "cat > f.sh <<'EOF'\nswift test | tail\nEOF"
        #expect(classify(script) == nil)
        #expect(classify("swift test <<EOF\nrm -rf x; echo done\nEOF")?.exitVisible == true)
    }

    @Test func commentsAreIgnored() {
        #expect(classify("swift test # && echo | done")?.exitVisible == true)
        #expect(classify("# swift test") == nil)
    }
}
