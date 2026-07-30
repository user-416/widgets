// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WidgetsShared",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "WidgetsShared", targets: ["WidgetsShared"]),
    ],
    targets: [
        .target(name: "WidgetsShared"),
        .testTarget(name: "WidgetsSharedTests", dependencies: ["WidgetsShared"]),
    ]
)
