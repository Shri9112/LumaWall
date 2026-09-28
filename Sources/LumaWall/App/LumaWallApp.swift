import SwiftUI
import LumaWallKit

@main
struct LumaWallApp: App {
    init() {
        LumaLogger.app.info("LumaWall application initialized")
        AppCoordinator.shared.startup()
    }

    var body: some Scene {
        WindowGroup("LumaWall", id: "main") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 640)

        MenuBarExtra("LumaWall", systemImage: "sparkles.tv") {
            MenuBarContentView()
        }
    }
}
