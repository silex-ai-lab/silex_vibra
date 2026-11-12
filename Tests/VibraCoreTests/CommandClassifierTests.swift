import Foundation
import Testing
@testable import VibraCore

/// `Fixtures/evidence-cases.json` is the contract. `tools/evidence-oracle`
/// runs the same file, so a behaviour pinned there is pinned in both.
struct EvidenceCases: Decodable {
    struct Classify: Decodable { let script: String; let kind: String?; let proof: String? }
    struct Summary: Decodable { let tail: String; let kind: String; let verdict: Bool? }
    let classify: [Classify]
    let summary: [Summary]

    static func load() throws -> EvidenceCases {
        try JSONDecoder().decode(EvidenceCases.self, from: Data(contentsOf: fixtureURL("Fixtures/evidence-cases.json")))
    }
}

struct CommandClassifierTests {
    @Test func everyCaseInTheSharedFile() throws {
        let cases = try EvidenceCases.load().classify
        #expect(cases.count > 100)
        for item in cases {
            let found = CommandClassifier.classify(script: item.script)
            #expect(found?.kind.rawValue == item.kind, "kind of \(item.script)")
            #expect(found.map { $0.soleCommand ? "full" : "none" } == item.proof, "proof of \(item.script)")
        }
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
        #expect(CommandClassifier.classify(script: script)?.kind == kind)
    }
}
