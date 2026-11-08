import Foundation

public struct SessionDetailModel: Sendable, Equatable {
    public let heading: String
    public let agentName: String
    public let branch: String
    public let stateLine: String
    public let evidenceLine: String
    public let lastObservedLine: String
    public let healthLine: String
    public let tokensLine: String
    public let cwd: String
    public let returnRoute: ReturnRoute
    public let isLive: Bool
    public let historyAvailable: Bool

    public static func build(session: Session, snapshot: StatusSnapshot, now: Date) -> SessionDetailModel {
        SessionDetailModel(
            heading: "", agentName: "", branch: "", stateLine: "", evidenceLine: "",
            lastObservedLine: "", healthLine: "", tokensLine: "", cwd: session.cwd,
            returnRoute: .none, isLive: false, historyAvailable: false
        )
    }
}
