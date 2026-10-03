import Foundation
import MindMapAICore

/// One open model the app can run (ADR 0011, decision 3). Downloading it is
/// MM-106; this only says what it is and where it may run.
public struct LocalModel: Hashable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    /// Shown next to the download button and in Acknowledgements.
    public var license: String
    /// The Hugging Face repository the MLX weights come from, for the
    /// evaluation script and MM-106's download source.
    public var repository: String
    public var languages: Set<AILanguage>
    public var contextSize: Int
    /// Below this much physical memory the model is not offered: on iPhone the
    /// app would be killed while loading it. Devices report a little less than
    /// their nominal memory, so each value is 90 % of the size sold.
    public var minimumPhysicalMemory: UInt64

    public init(
        id: String,
        displayName: String,
        license: String,
        repository: String,
        languages: Set<AILanguage>,
        contextSize: Int,
        minimumPhysicalMemory: UInt64
    ) {
        self.id = id
        self.displayName = displayName
        self.license = license
        self.repository = repository
        self.languages = languages
        self.contextSize = contextSize
        self.minimumPhysicalMemory = minimumPhysicalMemory
    }

    /// The default: 0.98 GB of weights, 1.3 GB peak while generating (MM-77),
    /// so it fits the 6 GB of iPhone 15 and 15 Plus.
    public static let qwen3_1_7B = LocalModel(
        id: "qwen3-1.7b-4bit",
        displayName: "Qwen3 1.7B",
        license: "Apache-2.0",
        repository: "mlx-community/Qwen3-1.7B-4bit",
        languages: Set(AILanguage.allCases),
        contextSize: 8_192,
        minimumPhysicalMemory: 6 * gibibyte * 9 / 10
    )

    /// 2.3 GB of weights, 2.7 GB peak: only for 8 GB devices and Macs.
    public static let qwen3_4B = LocalModel(
        id: "qwen3-4b-4bit",
        displayName: "Qwen3 4B",
        license: "Apache-2.0",
        repository: "mlx-community/Qwen3-4B-4bit",
        languages: Set(AILanguage.allCases),
        contextSize: 8_192,
        minimumPhysicalMemory: 8 * gibibyte * 9 / 10
    )

    public static let all = [qwen3_1_7B, qwen3_4B]

    static let gibibyte: UInt64 = 1 << 30
}
