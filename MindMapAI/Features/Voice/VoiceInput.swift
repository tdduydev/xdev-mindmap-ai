import Foundation
import MindMapCapture
import MindMapDomain
import MindMapGraph
import Observation
import SwiftUI

/// Dictating topics into the open map (FR-AI-21).
///
/// What is heard stays in the sheet, where it can be edited, until Add Topics
/// turns it into one command: the whole dictation is one undo step. Speech is
/// transcribed on the device and never logged.
@Observable
final class VoiceInput {
    enum Phase: Equatable {
        case idle
        /// Pro is locked (FR-STO-01); the sheet says so and nothing listens.
        case locked
        case preparing
        /// The model for the language is not on the device; downloading waits
        /// for the user to ask (App Review 4.2.3).
        case needsDownload
        case downloading(Double)
        case listening
        case finishing
        case failed(VoiceFailure)
    }

    var isPresented = false
    private(set) var phase: Phase = .idle
    var transcript = VoiceTranscript()
    var language: VoiceLanguage {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: Self.languageKey)
            // Words already heard stay; listening restarts in the new language.
            if isListening {
                Task { await restart() }
            } else if phase != .locked {
                phase = .idle
            }
        }
    }

    let session: EditorSession
    /// The topic the dictation goes under, fixed when the sheet opens.
    private(set) var parentID: NodeID?

    @ObservationIgnored private let transcriber: any VoiceTranscribing
    @ObservationIgnored private let entitlements: any ProEntitlements
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var transcription: (any VoiceTranscriptionSession)?
    /// The running listen loop; tests await it.
    @ObservationIgnored private(set) var listening: Task<Void, Never>?

    static let languageKey = "voiceInput.language"

    init(
        session: EditorSession,
        transcriber: any VoiceTranscribing,
        entitlements: any ProEntitlements,
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.session = session
        self.transcriber = transcriber
        self.entitlements = entitlements
        self.defaults = defaults
        language = defaults.string(forKey: Self.languageKey).flatMap(VoiceLanguage.init(rawValue:))
            ?? VoiceLanguage.preferred(from: preferredLanguages)
    }

    // MARK: Reading

    var isListening: Bool { phase == .listening }
    var isBusy: Bool {
        switch phase {
        case .preparing, .downloading, .listening, .finishing: true
        default: false
        }
    }

    /// Not while a step is under way: a download in flight would go on and start
    /// listening on its own, alongside one the user starts.
    var canChangeLanguage: Bool {
        switch phase {
        case .preparing, .downloading, .finishing: false
        default: true
        }
    }

    var canAddTopics: Bool { !transcript.titles.isEmpty && phase != .finishing && phase != .locked }

    // MARK: Intents

    /// Opens the sheet under the selected topic and starts listening.
    func present() {
        guard !isPresented, let parent = session.selection ?? session.rootID else { return }
        parentID = parent
        transcript = VoiceTranscript()
        isPresented = true
        guard entitlements.allows(.voiceInput) else {
            phase = .locked
            return
        }
        startListening()
    }

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    func startListening() {
        guard !isBusy, phase != .locked else { return }
        listening = Task { await listen() }
    }

    /// Stops the microphone; the last words still arrive before the phase goes idle.
    func stopListening() {
        guard isListening, let transcription else { return }
        phase = .finishing
        Task { await transcription.finish() }
    }

    func download() {
        guard phase == .needsDownload else { return }
        listening = Task {
            phase = .downloading(0)
            do {
                try await transcriber.prepare(language) { fraction in
                    Task { @MainActor in
                        guard case .downloading = self.phase else { return }
                        self.phase = .downloading(fraction)
                    }
                }
            } catch {
                phase = .failed(VoiceFailure(error))
                return
            }
            phase = .idle
            await listen()
        }
    }

    func removeTopics(at offsets: IndexSet) {
        transcript.topics.remove(atOffsets: offsets)
    }

    func removeTopic(_ id: VoiceTranscript.Topic.ID) {
        transcript.topics.removeAll { $0.id == id }
    }

    /// One command for the whole dictation; the first new topic is selected.
    func addTopics() {
        guard canAddTopics, let parentID else { return }
        let (command, ids) = SpokenTopics.command(adding: transcript.titles, under: parentID)
        if session.perform(command, named: String(localized: "Add Topics by Voice")), let first = ids.first {
            session.selection = first
        }
        close()
    }

    /// Cancel: nothing heard is added.
    func close() {
        isPresented = false
        sheetDismissed()
    }

    /// Also called when the sheet is swiped away.
    func sheetDismissed() {
        listening?.cancel()
        listening = nil
        if let transcription {
            self.transcription = nil
            Task { await transcription.cancel() }
        }
        transcript = VoiceTranscript()
        phase = .idle
        parentID = nil
    }

    // MARK: Listening

    private func listen() async {
        phase = .preparing
        do {
            try await transcriber.requestPermissions()
            switch await transcriber.availability(for: language) {
            case .ready:
                break
            case .needsDownload:
                phase = .needsDownload
                return
            case .downloading:
                phase = .downloading(0)
                try await transcriber.prepare(language) { _ in }
            case .unsupported:
                throw VoiceInputError.unsupportedLanguage
            }
            guard !Task.isCancelled, isPresented else { return }
            let transcription = try await transcriber.start(language)
            guard !Task.isCancelled, isPresented else {
                await transcription.cancel()
                return
            }
            self.transcription = transcription
            phase = .listening
            for try await update in transcription.updates {
                transcript.apply(update)
            }
            if self.transcription === transcription {
                self.transcription = nil
                phase = .idle
            }
        } catch {
            transcription = nil
            guard !Task.isCancelled, isPresented else { return }
            phase = .failed(VoiceFailure(error))
            AccessibilityNotification.Announcement(VoiceFailure(error).message).post()
        }
    }

    private func restart() async {
        guard let transcription else { return }
        self.transcription = nil
        phase = .finishing
        await transcription.finish()
        await listening?.value
        phase = .idle
        startListening()
    }
}

/// Why voice input stopped, in words the user can act on.
enum VoiceFailure: Equatable {
    case microphoneDenied
    case speechRecognitionDenied
    case unsupportedLanguage
    case noMicrophone
    case failed

    init(_ error: any Error) {
        switch error as? VoiceInputError {
        case .microphoneDenied: self = .microphoneDenied
        case .speechRecognitionDenied: self = .speechRecognitionDenied
        case .unsupportedLanguage: self = .unsupportedLanguage
        case .noMicrophone: self = .noMicrophone
        case .transcriptionFailed, nil: self = .failed
        }
    }

    var message: String {
        switch self {
        case .microphoneDenied:
            String(localized: "MindMap AI can’t use the microphone. Turn it on in Privacy & Security settings.")
        case .speechRecognitionDenied:
            String(localized: "MindMap AI can’t use speech recognition. Turn it on in Privacy & Security settings.")
        case .unsupportedLanguage:
            String(localized: "This device can’t transcribe this language on the device.")
        case .noMicrophone:
            String(localized: "No microphone is available.")
        case .failed:
            String(localized: "Voice input stopped unexpectedly. Try again.")
        }
    }
}

extension VoiceLanguage {
    var title: LocalizedStringResource {
        switch self {
        case .english: "English"
        case .vietnamese: "Vietnamese"
        }
    }
}
