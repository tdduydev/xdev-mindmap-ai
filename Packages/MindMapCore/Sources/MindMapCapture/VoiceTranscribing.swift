import Foundation

/// The languages voice input supports (FR-AI-21): those of the app's interface.
public enum VoiceLanguage: String, CaseIterable, Hashable, Sendable {
    case english
    case vietnamese
    case japanese

    public var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .vietnamese: Locale(identifier: "vi_VN")
        case .japanese: Locale(identifier: "ja_JP")
        }
    }

    /// Whether `SpeechTranscriber` is tried before `DictationTranscriber`. It
    /// does not hear Vietnamese; for the others it is the newer, better model.
    public var prefersSpeechTranscriber: Bool {
        self != .vietnamese
    }

    /// The first preferred language voice input can hear, else English.
    public static func preferred(from identifiers: [String] = Locale.preferredLanguages) -> VoiceLanguage {
        for identifier in identifiers {
            switch Locale(identifier: identifier).language.languageCode?.identifier {
            case "vi": return .vietnamese
            case "ja": return .japanese
            case "en": return .english
            default: continue
            }
        }
        return .english
    }
}

/// Whether a language can be transcribed on this device right now.
public enum VoiceAvailability: Hashable, Sendable {
    case ready
    /// The on-device model is supported but not installed; `prepare` downloads it.
    case needsDownload
    /// The system is downloading it already.
    case downloading
    /// This device cannot transcribe the language on the device.
    case unsupported
}

/// One piece of a running transcription. Volatile text is a guess that later
/// updates replace; final text never changes again.
public enum VoiceTranscriptUpdate: Hashable, Sendable {
    case volatile(String)
    case final(String)
}

public enum VoiceInputError: Error, Hashable, Sendable {
    case microphoneDenied
    case speechRecognitionDenied
    case unsupportedLanguage
    case noMicrophone
    /// The model or audio pipeline failed; nothing the user can fix.
    case transcriptionFailed
}

/// A transcription in progress. `updates` ends after `finish()` once the last
/// words are final, or right after `cancel()`.
public protocol VoiceTranscriptionSession: AnyObject, Sendable {
    var updates: AsyncThrowingStream<VoiceTranscriptUpdate, any Error> { get }
    /// Stops listening and finalizes what was heard.
    func finish() async
    /// Stops listening and drops what has not been finalized yet.
    func cancel() async
}

/// Turns speech into text on the device. The app uses
/// `AppleSpeechTranscriber`; tests and previews use a fake, since the Speech
/// models are not in the Simulator nor on test machines.
public protocol VoiceTranscribing: Sendable {
    func availability(for language: VoiceLanguage) async -> VoiceAvailability
    /// Downloads the model for `language` when needed, reporting 0...1.
    func prepare(_ language: VoiceLanguage, progress: @escaping @Sendable (Double) -> Void) async throws
    /// Asks for the permissions the first time; throws `VoiceInputError`.
    func requestPermissions() async throws
    func start(_ language: VoiceLanguage) async throws -> any VoiceTranscriptionSession
}
