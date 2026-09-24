// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeLimit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LimitCore", targets: ["LimitCore"]),
        .executable(name: "limitcheck", targets: ["limitcheck"]),
    ],
    targets: [
        .target(name: "LimitCore"),
        .executableTarget(name: "limitcheck", dependencies: ["LimitCore"]),
        .testTarget(name: "LimitCoreTests", dependencies: ["LimitCore"]),
    ]
)
