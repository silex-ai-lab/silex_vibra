import Foundation

/// `--evidence-stats`: counts per agent, evidence case, check and change.
/// Never a command, a path or output.
public enum EvidenceStats {
    public static func format(_ rows: [(agent: AgentKind, fold: EvidenceFold)]) -> String {
        var sessions: [String: Int] = [:]
        var cases: [String: Int] = [:]
        var checks: [String: Int] = [:]
        var changes: [String: Int] = [:]
        var reported: [String: Int] = [:]
        var qualified: [String: Int] = [:]
        for (agent, fold) in rows {
            let name = agent.rawValue
            sessions["sessions agent=\(name)", default: 0] += 1
            let evidence = DeliveryEvidence.build(events: fold.events, sawToolRecords: fold.sawToolRecords)
            cases["case agent=\(name) case=\(evidence.caseName)", default: 0] += 1
            if case .checkedAfterLastChange(let check, let testEdits) = evidence {
                reported["reported agent=\(name) kind=\(check.kind.rawValue) result=\(check.result.statsName)", default: 0] += 1
                for effect in testEdits?.effects ?? [] {
                    qualified["qualified agent=\(name) effect=\(effect.rawValue)", default: 0] += 1
                }
            }
            for event in fold.events {
                switch event {
                case .check(let check):
                    checks["check agent=\(name) kind=\(check.kind.rawValue) result=\(check.result.statsName)", default: 0] += 1
                case .codeChange(let change):
                    changes["change agent=\(name) target=\(change.target.statsName)", default: 0] += 1
                }
            }
        }
        return [sessions, cases, reported, checks, changes, qualified]
            .flatMap { group in group.sorted { $0.key < $1.key }.map { "\($0.key) n=\($0.value)\n" } }
            .joined()
    }
}

extension CodeChangeTarget {
    /// `test.compared`: pattern counts present; `test.unseen`: not available.
    var statsName: String {
        switch self {
        case .source: "source"
        case .test(_, before: .some, after: .some): "test.compared"
        case .test: "test.unseen"
        }
    }
}
