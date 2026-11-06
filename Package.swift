// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Lax",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "Lax", targets: ["Lax"]),
        .library(name: "LaxKit", targets: ["LaxKit"]),
    ],
    targets: [
        // Slack layer: credentials, Web API, WebSocket, cache. No UI.
        .target(name: "LaxKit"),
        .executableTarget(name: "Lax", dependencies: ["LaxKit"]),
        .testTarget(name: "LaxKitTests", dependencies: ["LaxKit"]),
    ]
)
