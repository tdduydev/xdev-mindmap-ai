// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MindMapCore",
    platforms: [
        .iOS(.v26),
        // macOS ships too (ADR 0006), and lets `swift test` run the core tests on
        // the Mac in seconds, without a simulator.
        .macOS(.v26),
    ],
    products: [
        .library(name: "MindMapDomain", targets: ["MindMapDomain"]),
        .library(name: "MindMapGraph", targets: ["MindMapGraph"]),
        .library(name: "MindMapPersistence", targets: ["MindMapPersistence"]),
        .library(name: "MindMapLayout", targets: ["MindMapLayout"]),
        .library(name: "MindMapAICore", targets: ["MindMapAICore"]),
        .library(name: "MindMapAIApple", targets: ["MindMapAIApple"]),
        .library(name: "MindMapTestSupport", targets: ["MindMapTestSupport"]),
    ],
    targets: [
        .target(name: "MindMapDomain"),
        .target(name: "MindMapGraph", dependencies: ["MindMapDomain"]),
        .target(name: "MindMapPersistence", dependencies: ["MindMapDomain", "MindMapGraph"]),
        .target(name: "MindMapLayout", dependencies: ["MindMapDomain", "MindMapGraph"]),
        .testTarget(name: "MindMapDomainTests", dependencies: ["MindMapDomain"]),
        .testTarget(name: "MindMapGraphTests", dependencies: ["MindMapGraph"]),
        .testTarget(name: "MindMapPersistenceTests", dependencies: ["MindMapPersistence"]),
        .testTarget(name: "MindMapLayoutTests", dependencies: ["MindMapLayout"]),
        // AICore never imports FoundationModels, so the graph, the UI and tests
        // depend on plain values; only AIApple talks to the model.
        .target(name: "MindMapAICore", dependencies: ["MindMapDomain", "MindMapGraph"]),
        .target(name: "MindMapAIApple", dependencies: ["MindMapAICore"]),
        .target(name: "MindMapTestSupport", dependencies: ["MindMapDomain", "MindMapGraph", "MindMapAICore"]),
        .testTarget(
            name: "MindMapAICoreTests",
            dependencies: ["MindMapAICore", "MindMapDomain", "MindMapGraph", "MindMapTestSupport"]
        ),
        .testTarget(
            name: "MindMapAIAppleTests",
            dependencies: ["MindMapAIApple", "MindMapAICore", "MindMapGraph", "MindMapTestSupport"]
        ),
    ]
)
