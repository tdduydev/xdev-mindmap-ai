import Foundation

/// The AI actions the app offers. Each one is a separate entry point in the UI,
/// so capabilities and errors are reported per feature.
public enum AIFeature: String, Hashable, Sendable, CaseIterable, Codable {
    case generateMap
    case expandTopic
    case brainstorm
    case rewrite
    case summarize
    case findMissingTopics
    case suggestTags
    case suggestGroups
    case summarizeBoundary
}

/// Whether an AI feature can run right now, and if not, why. The UI maps each
/// state to one behaviour (docs/on-device-ai.md, "Behaviour by availability").
public enum AIAvailability: String, Hashable, Sendable, CaseIterable {
    case ready
    /// The model runs, but not in the language the request needs.
    case languageUnsupported
    /// The hardware cannot run Apple Intelligence (for example a Mac with an
    /// Intel processor). AI entry points are hidden, not disabled.
    case deviceNotEligible
    /// The person has not turned on Apple Intelligence.
    case appleIntelligenceOff
    /// The model is still downloading or being prepared.
    case modelDownloading
    /// A reason this version of the app does not know about.
    case unknown

    public var isReady: Bool { self == .ready }
}

/// What the on-device model offers on this device, checked again each time the
/// app becomes active because Apple Intelligence can be turned on or off.
public struct AICapabilities: Hashable, Sendable {
    /// The state of the language model itself, never `.languageUnsupported`:
    /// language support is per request, see `availability(for:in:)`.
    public var model: AIAvailability
    public var supportedLanguages: Set<AILanguage>
    /// Tokens the model accepts per session. Nil when the model is not ready.
    public var contextSize: Int?

    public init(model: AIAvailability, supportedLanguages: Set<AILanguage> = [], contextSize: Int? = nil) {
        self.model = model
        self.supportedLanguages = model == .ready ? supportedLanguages : []
        self.contextSize = model == .ready ? contextSize : nil
    }

    /// Every feature uses the same model today. The feature is still part of
    /// the question so a later feature with its own requirement (image input,
    /// a Pro entitlement) does not change every call site.
    public func availability(for feature: AIFeature, in language: AILanguage) -> AIAvailability {
        guard model == .ready else { return model }
        return supportedLanguages.contains(language) ? .ready : .languageUnsupported
    }

    /// False only when the device can never run the model. Other states keep
    /// the entry points visible with one line of explanation.
    public var showsAIEntryPoints: Bool { model != .deviceNotEligible }

    /// Hardware that cannot run Apple Intelligence, such as an Intel Mac.
    public static let notEligible = AICapabilities(model: .deviceNotEligible)
}
