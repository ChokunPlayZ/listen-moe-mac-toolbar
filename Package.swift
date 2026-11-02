// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListenMoe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ListenMoe", targets: ["ListenMoe"]),
        .library(name: "RadioCore", targets: ["RadioCore"]),
    ],
    targets: [
        .target(name: "RadioCore"),
        .executableTarget(name: "ListenMoe", dependencies: ["RadioCore"]),
        .testTarget(name: "RadioCoreTests", dependencies: ["RadioCore"]),
        .testTarget(name: "ListenMoeTests", dependencies: ["ListenMoe", "RadioCore"]),
    ]
)
