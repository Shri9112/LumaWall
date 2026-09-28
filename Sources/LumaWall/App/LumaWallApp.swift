import SwiftUI
import LumaWallKit

@main
struct LumaWallApp: App {
    init() {
        LumaLogger.app.info("LumaWall application initialized")
    }

    var body: some Scene {
        WindowGroup("LumaWall", id: "main") {
            VideoPreviewView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 800, height: 560)
    }
}
