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
        .library(name: "MindMapInterchange", targets: ["MindMapInterchange"]),
        .library(name: "MindMapSharing", targets: ["MindMapSharing"]),
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
        .target(name: "MindMapInterchange", dependencies: ["MindMapDomain", "MindMapGraph"]),
        .testTarget(name: "MindMapInterchangeTests", dependencies: ["MindMapInterchange"]),
        // What the Share Extension and the App Intents do to maps, without UI
        // or AI, so the extension links only the core it needs (NFR-PERF-08).
        .target(
            name: "MindMapSharing",
            dependencies: ["MindMapDomain", "MindMapGraph", "MindMapPersistence", "MindMapInterchange"]
        ),
        .testTarget(
            name: "MindMapSharingTests",
            dependencies: ["MindMapSharing", "MindMapDomain", "MindMapGraph", "MindMapPersistence", "MindMapInterchange"]
        ),
    ]
)
