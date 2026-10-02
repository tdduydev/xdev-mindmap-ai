import Foundation
import FoundationModels
import MindMapAICore

/// Reads what Foundation Models offers on this device right now.
enum AppleCapabilityProbe {
    static func current() -> AICapabilities {
        #if arch(x86_64)
        // Apple Intelligence needs Apple silicon, so an Intel Mac, and the
        // Intel slice running under Rosetta, never get the model. Answering
        // here keeps every AI entry point hidden there (MM-21) without relying
        // on how the framework reports an unsupported processor: under Rosetta
        // on Apple silicon it says the model is available (macOS 27.0.1).
        return .notEligible
        #else
        let model = SystemLanguageModel.default
        let status = status(of: model.availability)
        guard status == .ready else { return AICapabilities(model: status) }
        let languages = Set(AILanguage.allCases.filter { model.supportsLocale($0.locale) })
        return AICapabilities(model: .ready, supportedLanguages: languages, contextSize: contextSize(of: model))
        #endif
    }

    // `if case` instead of `switch`: the framework's enums can gain cases, and
    // this keeps an unknown reason from becoming a build warning or a crash.
    static func status(of availability: SystemLanguageModel.Availability) -> AIAvailability {
        if case .available = availability { return .ready }
        if case .unavailable(.deviceNotEligible) = availability { return .deviceNotEligible }
        if case .unavailable(.appleIntelligenceNotEnabled) = availability { return .appleIntelligenceOff }
        if case .unavailable(.modelNotReady) = availability { return .modelDownloading }
        return .unknown
    }

    private static func contextSize(of model: SystemLanguageModel) -> Int {
        if #available(macOS 26.4, iOS 26.4, *) {
            return model.contextSize
        }
        return AIContextLimits.assumedContextSize
    }
}
