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
        .library(name: "MindMapSearch", targets: ["MindMapSearch"]),
        .library(name: "MindMapSharing", targets: ["MindMapSharing"]),
        .library(name: "MindMapIntents", targets: ["MindMapIntents"]),
        .library(name: "MindMapCapture", targets: ["MindMapCapture"]),
        .library(name: "MindMapQuery", targets: ["MindMapQuery"]),
        .library(name: "MindMapMCP", targets: ["MindMapMCP"]),
        .library(name: "MindMapImages", targets: ["MindMapImages"]),
        .library(name: "MindMapAILocal", targets: ["MindMapAILocal"]),
        // Only for the app tests that run the evaluations on the MLX engine (MM-119).
        .library(name: "MindMapAIEvaluation", targets: ["MindMapAIEvaluation"]),
    ],
    targets: [
        .target(name: "MindMapDomain"),
        .target(name: "MindMapGraph", dependencies: ["MindMapDomain"]),
        // AICore for the chat's values, which each map saves (MM-55).
        .target(name: "MindMapPersistence", dependencies: ["MindMapDomain", "MindMapGraph", "MindMapAICore"]),
        .target(name: "MindMapLayout", dependencies: ["MindMapDomain", "MindMapGraph"]),
        .testTarget(name: "MindMapDomainTests", dependencies: ["MindMapDomain"]),
        .testTarget(name: "MindMapGraphTests", dependencies: ["MindMapGraph", "MindMapDomain"]),
        .testTarget(
            name: "MindMapPersistenceTests",
            dependencies: ["MindMapPersistence", "MindMapDomain", "MindMapGraph", "MindMapAICore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "MindMapLayoutTests", dependencies: ["MindMapLayout", "MindMapDomain", "MindMapGraph"]),
        // AICore never imports FoundationModels, so the graph, the UI and tests
        // depend on plain values; only AIApple talks to the model.
        .target(name: "MindMapAICore", dependencies: ["MindMapDomain", "MindMapGraph"]),
        // The chat's tools read maps through MindMapQuery (docs/chat.md).
        .target(name: "MindMapAIApple", dependencies: ["MindMapAICore", "MindMapQuery", "MindMapDomain"]),
        .target(name: "MindMapTestSupport", dependencies: ["MindMapDomain", "MindMapGraph", "MindMapAICore", "MindMapCapture"]),
        .testTarget(
            name: "MindMapAICoreTests",
            dependencies: ["MindMapAICore", "MindMapDomain", "MindMapGraph", "MindMapTestSupport"]
        ),
        .testTarget(
            name: "MindMapAIAppleTests",
            dependencies: [
                "MindMapAIApple", "MindMapAICore", "MindMapGraph", "MindMapTestSupport",
                "MindMapDomain", "MindMapPersistence", "MindMapQuery",
            ]
        ),
        .target(name: "MindMapInterchange", dependencies: ["MindMapDomain", "MindMapGraph"]),
        .testTarget(name: "MindMapInterchangeTests", dependencies: ["MindMapInterchange", "MindMapDomain", "MindMapGraph"]),
        .target(name: "MindMapSearch", dependencies: ["MindMapDomain", "MindMapGraph"]),
        .testTarget(name: "MindMapSearchTests", dependencies: ["MindMapSearch", "MindMapDomain", "MindMapGraph"]),
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
        // App Intents, Shortcuts and Spotlight (MM-11). Here rather than in the
        // app so the intents are an `AppIntentsPackage` any target can include.
        .target(
            name: "MindMapIntents",
            dependencies: ["MindMapDomain", "MindMapPersistence", "MindMapInterchange", "MindMapSharing"]
        ),
        .testTarget(
            name: "MindMapIntentsTests",
            dependencies: ["MindMapIntents", "MindMapDomain", "MindMapGraph", "MindMapPersistence", "MindMapSharing"]
        ),
        // Speech and the microphone sit behind `VoiceTranscribing`, so tests and
        // the Simulator use `FakeVoiceTranscriber` instead of the device models.
        .target(name: "MindMapCapture", dependencies: ["MindMapDomain", "MindMapGraph"]),
        .testTarget(
            name: "MindMapCaptureTests",
            dependencies: ["MindMapCapture", "MindMapDomain", "MindMapGraph", "MindMapTestSupport"]
        ),
        // Reads shared by the MCP server and the chat (docs/mcp.md). No AI and
        // no network, so both consumers and `swift test` link it as is.
        .target(
            name: "MindMapQuery",
            dependencies: ["MindMapDomain", "MindMapGraph", "MindMapPersistence", "MindMapSearch"]
        ),
        .testTarget(
            name: "MindMapQueryTests",
            dependencies: ["MindMapQuery", "MindMapDomain", "MindMapGraph", "MindMapPersistence"]
        ),
        // The MCP server (ADR 0008): our own JSON-RPC over HTTP on loopback with
        // the Network framework, no SDK. Reads only through MindMapQuery.
        .target(name: "MindMapMCP", dependencies: ["MindMapDomain", "MindMapQuery"]),
        .testTarget(
            name: "MindMapMCPTests",
            dependencies: ["MindMapMCP", "MindMapDomain", "MindMapGraph", "MindMapPersistence", "MindMapQuery"],
            resources: [.copy("Fixtures")]
        ),
        // Topic images (MM-63): ImageIO and Core Graphics only, so the same
        // processing runs on every platform and in `swift test`.
        .target(name: "MindMapImages", dependencies: ["MindMapDomain"]),
        .testTarget(name: "MindMapImagesTests", dependencies: ["MindMapImages", "MindMapDomain"]),
        // The downloadable open model (ADR 0011): provider, answer checks and
        // device rules. MLX itself is linked only by the app, behind
        // LocalInferenceEngine, so this target and `swift test` stay dependency-free.
        .target(name: "MindMapAILocal", dependencies: ["MindMapAICore", "MindMapAIApple", "MindMapDomain"]),
        .testTarget(
            name: "MindMapAILocalTests",
            dependencies: [
                "MindMapAILocal", "MindMapAIEvaluation", "MindMapAICore", "MindMapAIApple", "MindMapDomain", "MindMapTestSupport",
            ]
        ),
        // Evaluations of every AI feature and the chat in en, vi and ja (MM-105),
        // and the developer tool that runs them on Foundation Models or MLX.
        .target(name: "MindMapAIEvaluation", dependencies: ["MindMapAICore", "MindMapDomain"]),
        .executableTarget(
            name: "mindmap-ai-eval",
            dependencies: ["MindMapAIEvaluation", "MindMapAILocal", "MindMapAIApple", "MindMapAICore"],
            path: "Sources/MindMapAIEvalTool"
        ),
        // A developer tool, not shipped: serves sample maps so the MCP Inspector
        // and real clients can be pointed at the server before the app hosts it.
        .executableTarget(
            name: "mindmap-mcp-dev",
            dependencies: ["MindMapMCP", "MindMapDomain", "MindMapGraph", "MindMapPersistence", "MindMapQuery"],
            path: "Sources/MindMapMCPDevServer"
        ),
    ]
)

// Warnings are errors in our own code. Set here, not with
// SWIFT_TREAT_WARNINGS_AS_ERRORS on the xcodebuild command line, which also
// reaches remote packages and clashes with their -suppress-warnings (MM-119).
for target in package.targets where target.type == .regular {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
