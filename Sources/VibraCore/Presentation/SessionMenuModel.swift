import Foundation

public enum MenuSectionKind: Sendable, CaseIterable {
    case needsYou, running, recent
}

public enum RowClick: Sendable, Equatable {
    case returnToSession, openDetails
}

public struct MenuRow: Sendable, Equatable {
    public let key: SessionKey
    public let title: String
    public let tooltip: String
    public let click: RowClick
}

public struct MenuSection: Sendable, Equatable {
    public let kind: MenuSectionKind
    public let rows: [MenuRow]
}

public struct SessionMenuModel: Sendable, Equatable {
    public let sections: [MenuSection]
    public let detailRows: [MenuRow]
    public let emptyMessage: String?
    public let notices: [String]

    public static func build(_ snapshot: StatusSnapshot, now: Date) -> SessionMenuModel {
        SessionMenuModel(sections: [], detailRows: [], emptyMessage: nil, notices: [])
    }

    public func diagnosticLines(_ snapshot: StatusSnapshot, now: Date) -> [String] {
        []
    }
}
