import Foundation

public enum DisplayMode: String, Codable, Sendable, CaseIterable {
    case unified = "unified"
    case individual = "individual"

    public var title: String {
        switch self {
        case .unified:
            return "Same on All Displays"
        case .individual:
            return "Individual per Display"
        }
    }

    public var description: String {
        switch self {
        case .unified:
            return "Play the same live wallpaper across all connected monitors."
        case .individual:
            return "Choose a distinct live wallpaper for each physical display."
        }
    }
}

public struct DisplaySettings: Codable, Sendable, Equatable {
    public var mode: DisplayMode
    public var unifiedWallpaperId: UUID?
    public var assignments: [UInt32: UUID]

    public init(
        mode: DisplayMode = .unified,
        unifiedWallpaperId: UUID? = nil,
        assignments: [UInt32: UUID] = [:]
    ) {
        self.mode = mode
        self.unifiedWallpaperId = unifiedWallpaperId
        self.assignments = assignments
    }
}
