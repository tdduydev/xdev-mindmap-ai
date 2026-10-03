import Foundation
import MindMapAICore

/// One downloadable model: the files a runtime needs, each with the size and
/// SHA-256 the download must match. Weights are data the runtime reads, never
/// code, which is what keeps the download inside guideline 2.5.2 [Chưa kiểm chứng].
public struct LocalModel: Hashable, Sendable, Identifiable {
    public struct File: Hashable, Sendable {
        /// Path inside the model's folder, e.g. "model.safetensors".
        public var name: String
        public var url: URL
        public var byteCount: Int64
        /// Lowercase hex.
        public var sha256: String

        public init(name: String, url: URL, byteCount: Int64, sha256: String) {
            self.name = name
            self.url = url
            self.byteCount = byteCount
            self.sha256 = sha256
        }
    }

    public var id: String
    public var displayName: String
    /// Shown next to the download button, e.g. "Apache-2.0".
    public var license: String
    public var languages: Set<AILanguage>
    public var contextSize: Int
    /// Below this much physical memory the model is not offered: on iPhone the
    /// app would be killed while loading it [Đề xuất: weights × 2].
    public var minimumPhysicalMemory: UInt64
    public var files: [File]

    public init(
        id: String,
        displayName: String,
        license: String,
        languages: Set<AILanguage>,
        contextSize: Int,
        minimumPhysicalMemory: UInt64,
        files: [File]
    ) {
        self.id = id
        self.displayName = displayName
        self.license = license
        self.languages = languages
        self.contextSize = contextSize
        self.minimumPhysicalMemory = minimumPhysicalMemory
        self.files = files
    }

    public var downloadByteCount: Int64 { files.reduce(0) { $0 + $1.byteCount } }

    /// "1.1 GB", as the download button shows it.
    public var formattedDownloadSize: String {
        ByteCountFormatter.string(fromByteCount: downloadByteCount, countStyle: .file)
    }
}
