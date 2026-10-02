// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MindMapCore",
    platforms: [
        .iOS(.v26),
        // The product ships on iOS and iPadOS only. macOS is listed so `swift test`
        // can run the core tests on a Mac in seconds, without a simulator.
        .macOS(.v26),
    ],
    products: [
        .library(name: "MindMapDomain", targets: ["MindMapDomain"]),
        .library(name: "MindMapGraph", targets: ["MindMapGraph"]),
    ],
    targets: [
        .target(name: "MindMapDomain"),
        .target(name: "MindMapGraph", dependencies: ["MindMapDomain"]),
        .testTarget(name: "MindMapDomainTests", dependencies: ["MindMapDomain"]),
        .testTarget(name: "MindMapGraphTests", dependencies: ["MindMapGraph"]),
    ]
)
