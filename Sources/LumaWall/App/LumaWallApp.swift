import SwiftUI
import LumaWallKit

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles.tv")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(.tint)

            Text("LumaWall")
                .font(.system(size: 28, weight: .bold))

            Text("Native macOS Live Wallpaper Engine")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            Text("Phase 0 Initialization Complete")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 480, minHeight: 320)
        .padding()
    }
}

@main
struct LumaWallApp: App {
    init() {
        LumaLogger.app.info("LumaWall application initialized")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
