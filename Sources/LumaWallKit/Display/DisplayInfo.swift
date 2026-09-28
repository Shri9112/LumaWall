import AppKit
import Foundation

public struct DisplayInfo: Identifiable, Sendable, Equatable {
    public let id: CGDirectDisplayID
    public let name: String
    public let frame: NSRect
    public let isMain: Bool
    public let backingScaleFactor: CGFloat

    public init(
        id: CGDirectDisplayID,
        name: String,
        frame: NSRect,
        isMain: Bool,
        backingScaleFactor: CGFloat = 2.0
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.isMain = isMain
        self.backingScaleFactor = backingScaleFactor
    }

    public var resolutionDescription: String {
        let pixelWidth = Int((frame.width * backingScaleFactor).rounded())
        let pixelHeight = Int((frame.height * backingScaleFactor).rounded())
        return "\(pixelWidth) × \(pixelHeight)"
    }
}

extension NSScreen {
    public var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    public var displayInfo: DisplayInfo {
        let id = displayID ?? 0
        let isMain = self == NSScreen.main
        return DisplayInfo(
            id: id,
            name: localizedName,
            frame: frame,
            isMain: isMain,
            backingScaleFactor: backingScaleFactor
        )
    }
}
