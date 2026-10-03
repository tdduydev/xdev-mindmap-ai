import Foundation
import MindMapAIApple
import MindMapAICore
import MindMapAILocal

/// The app's AI provider (ADR 0011): Foundation Models wherever it is ready,
/// the downloaded open model where it cannot run, and Foundation Models' own
/// state when no model is downloaded, which is how the app looked before.
enum AIProviders {
    static func standard() -> any AIProvider {
        let model = LocalDeviceEligibility.recommendedModel(physicalMemory: ProcessInfo.processInfo.physicalMemory)
        let local = LocalLLMProvider(
            model: model,
            isInstalled: { LocalModelFolder.isInstalled(model) },
            engine: { try await LocalModelEngines.shared.engine(for: model) }
        )
        return FallbackAIProvider(apple: AppleFoundationModelProvider(), local: local)
    }
}

/// Where a model's files live: Application Support/LocalModels/<id>, not
/// Caches, which the system may purge while the model is in use. MM-106
/// downloads into it; until then nothing is there and the fallback is off.
nonisolated enum LocalModelFolder {
    static let root = URL.applicationSupportDirectory.appending(path: "LocalModels", directoryHint: .isDirectory)

    static func folder(for model: LocalModel) -> URL {
        root.appending(path: model.id, directoryHint: .isDirectory)
    }

    /// The files MLX needs to load a model. MM-106 moves each one into place
    /// only after its checksum passed, so their presence means a full install.
    static let requiredFiles = ["config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors"]

    static func isInstalled(_ model: LocalModel) -> Bool {
        let folder = folder(for: model)
        return requiredFiles.allSatisfy { FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }
    }
}
