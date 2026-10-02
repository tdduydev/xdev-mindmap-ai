import Foundation
import MindMapAICore

/// Why an AI request ended without a result, as the person needs to hear it:
/// what happened, then what to do (FR-AI-14, NFR-UX-04). None of these means
/// the map changed.
enum AIFailure: Hashable {
    /// The model's guardrails blocked the request, or it declined. The app
    /// suggests rewording and never rewrites the request itself.
    case rephrase
    case smallerBranch
    case busy
    case unavailable(AIAvailability)
    case unsupportedLanguage
    /// The answer could not be turned into topics.
    case unusable
    case nothingSuggested
    /// The topic the request was about was deleted.
    case topicGone
    case requiresPro

    init(_ error: any Error) {
        switch error {
        case let error as AIError:
            switch error {
            case .guardrailViolation, .refusal: self = .rephrase
            case .contextSizeExceeded: self = .smallerBranch
            case .rateLimited: self = .busy
            case .unavailable(let availability): self = .unavailable(availability)
            case .unsupportedLanguage: self = .unsupportedLanguage
            case .invalidResponse, .generationFailed: self = .unusable
            }
        case ProposalError.anchorNotFound:
            self = .topicGone
        default:
            self = .unusable
        }
    }

    var message: String {
        switch self {
        case .rephrase:
            String(localized: "This request couldn’t be completed. Try wording it differently.")
        case .smallerBranch:
            String(localized: "This branch is too large. Select a smaller branch and try again.")
        case .busy:
            String(localized: "Apple Intelligence is busy. Try again in a moment.")
        case .unavailable(let availability):
            AIAvailabilityText.explanation(for: availability) ?? String(localized: "Apple Intelligence isn’t available right now.")
        case .unsupportedLanguage:
            String(localized: "Apple Intelligence doesn’t support this language yet.")
        case .unusable:
            String(localized: "The suggestions couldn’t be used. Try again.")
        case .nothingSuggested:
            String(localized: "No suggestions this time. Try again or reword the request.")
        case .topicGone:
            String(localized: "The topic was deleted, so its suggestions were removed.")
        case .requiresPro:
            String(localized: "This is part of MindMap AI Pro.")
        }
    }
}

/// One line per availability state, from the table in docs/on-device-ai.md.
enum AIAvailabilityText {
    /// Nil when the feature is ready.
    static func explanation(for availability: AIAvailability) -> String? {
        switch availability {
        case .ready:
            nil
        case .modelDownloading:
            String(localized: "Getting ready. Apple Intelligence is still downloading; AI actions will be available soon.")
        case .appleIntelligenceOff:
            turnOnInstructions
        case .languageUnsupported:
            String(localized: "Apple Intelligence doesn’t support this language yet.")
        case .deviceNotEligible:
            String(localized: "This device can’t run Apple Intelligence.")
        case .unknown:
            String(localized: "Apple Intelligence isn’t available right now.")
        }
    }

    /// Short status for Settings.
    static func status(for availability: AIAvailability) -> String {
        switch availability {
        case .ready: String(localized: "Ready")
        case .modelDownloading: String(localized: "Getting Ready")
        case .appleIntelligenceOff: String(localized: "Apple Intelligence Is Off")
        case .languageUnsupported: String(localized: "Language Not Supported")
        case .deviceNotEligible: String(localized: "Not Available on This Device")
        case .unknown: String(localized: "Not Available")
        }
    }

    static var turnOnInstructions: String {
        #if os(macOS)
        String(localized: "To use AI, turn on Apple Intelligence in System Settings ▸ Apple Intelligence & Siri.")
        #else
        String(localized: "To use AI, turn on Apple Intelligence in Settings ▸ Apple Intelligence & Siri.")
        #endif
    }
}
