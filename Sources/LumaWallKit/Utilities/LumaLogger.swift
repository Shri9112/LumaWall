import Foundation
import OSLog

public enum LumaLogger {
    public static let subsystem = "com.lumawall.app"

    public static let app = Logger(subsystem: subsystem, category: "App")
    public static let video = Logger(subsystem: subsystem, category: "Video")
    public static let display = Logger(subsystem: subsystem, category: "Display")
    public static let library = Logger(subsystem: subsystem, category: "Library")
    public static let performance = Logger(subsystem: subsystem, category: "Performance")
    public static let power = Logger(subsystem: subsystem, category: "Power")
}
