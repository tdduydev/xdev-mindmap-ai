// swift-tools-version: 6.2
import PackageDescription

// MM-77 prototype: an AIProvider backed by a small open model downloaded on
// request. It stays outside the app and outside Packages/MindMapCore until an
// ADR accepts it (docs/adr/0011-local-llm-fallback.md, a draft), and it has no
// external dependency: the runtime (MLX, llama.cpp) plugs in behind
// LocalInferenceEngine, so main never resolves a third-party package.
let package = Package(
    name: "LocalLLM",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "LocalLLM", targets: ["LocalLLM"])],
    dependencies: [.package(path: "../../Packages/MindMapCore")],
    targets: [
        .target(name: "LocalLLM", dependencies: [
            .product(name: "MindMapAICore", package: "MindMapCore"),
            .product(name: "MindMapAIApple", package: "MindMapCore"),
            .product(name: "MindMapDomain", package: "MindMapCore"),
        ]),
        .testTarget(name: "LocalLLMTests", dependencies: [
            "LocalLLM",
            .product(name: "MindMapAICore", package: "MindMapCore"),
            .product(name: "MindMapDomain", package: "MindMapCore"),
        ]),
    ]
)
