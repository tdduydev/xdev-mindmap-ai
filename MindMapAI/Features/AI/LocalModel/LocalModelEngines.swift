import Foundation
import MindMapAICore
import MindMapAILocal

/// Keeps one loaded local model for the app, loaded on the first request and
/// never at launch (NFR-PERF-05); loading takes seconds and 1–3 GB, so every
/// request shares it.
actor LocalModelEngines {
    static let shared = LocalModelEngines()

    enum LoadError: Error {
        /// This build has no runtime linked; see `makeEngine`.
        case runtimeUnavailable
    }

    private var loaded: (id: String, engine: any LocalInferenceEngine)?

    func engine(for model: LocalModel) async throws -> any LocalInferenceEngine {
        if let loaded, loaded.id == model.id { return loaded.engine }
        loaded = nil
        let engine = try await Self.makeEngine(model, LocalModelFolder.folder(for: model))
        loaded = (model.id, engine)
        return engine
    }

    /// Frees the weights, for memory pressure and when Settings removes a model.
    func unload() {
        loaded = nil
    }

    /// The MLX engine (ADR 0011, decision 2) plugs in here. Until it is
    /// linked no model can be installed either, so this is never reached.
    static var makeEngine: @Sendable (LocalModel, URL) async throws -> any LocalInferenceEngine = { _, _ in
        throw LoadError.runtimeUnavailable
    }
}
