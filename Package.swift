// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumaWall",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LumaWall", targets: ["LumaWall"]),
        .library(name: "LumaWallKit", targets: ["LumaWallKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LumaWallKit",
            dependencies: [],
            path: "Sources/LumaWallKit"
        ),
        .executableTarget(
            name: "LumaWall",
            dependencies: ["LumaWallKit"],
            path: "Sources/LumaWall"
        ),
        .executableTarget(
            name: "LumaWallTests",
            dependencies: ["LumaWallKit"],
            path: "Tests/LumaWallTests"
        )
    ]
)
