import Foundation
@testable import MindMapAI
import MindMapAILocal
import Testing

/// The engine factory without weights: the real generation runs in the opt-in
/// MLXEvaluationRun, since a model is gigabytes and not in the repo.
@Suite("Local model engine")
struct LocalModelEngineTests {
    @Test func aFolderWithoutAModelFailsToLoad() async throws {
        let empty = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        await #expect(throws: (any Error).self) {
            _ = try await LocalModelEngines.makeEngine(.qwen3_1_7B, empty)
        }
    }

    @Test func intelAndTheSimulatorHaveNoRuntime() async {
        #if arch(arm64) && !targetEnvironment(simulator)
        // Apple silicon loads MLX; the failure above comes from the missing files.
        #else
        await #expect(throws: LocalModelEngines.LoadError.runtimeUnavailable) {
            _ = try await LocalModelEngines.makeEngine(.qwen3_1_7B, URL.temporaryDirectory)
        }
        #endif
    }
}
