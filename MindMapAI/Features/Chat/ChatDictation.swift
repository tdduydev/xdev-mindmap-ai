import Foundation
import MindMapCapture
import Observation
import SwiftUI

/// Ask by voice (MM-80, FR-AI-21): the microphone in the chat's question field.
///
/// What is heard goes into the draft, after what was typed, so the person can
/// fix it before asking; it never asks on its own [Đề xuất]. Cancel puts the
/// draft back as it was. It uses the same on-device transcriber and Settings ▸
/// Voice Input Language as Add Topics by Voice, and the same Pro gate
/// (FR-STO-01): without Pro the paywall opens and listening starts if Pro is
/// unlocked there. Speech is never logged.
///
/// One per window, as `VoiceInput`: the microphone is not shared with another
/// window on the map, while the draft it writes to is (`MapChat.draft`).
@Observable
final class ChatDictation {
    enum Phase: Equatable {
        case idle
        case preparing
        /// The model for the language is not on the device; downloading waits
        /// for the person to ask (App Review 4.2.3).
        case needsDownload
        case downloading(Double)
        case listening
        case finishing
        case failed(VoiceFailure)
    }

    let chat: MapChat
    private(set) var phase: Phase = .idle
    /// Set when the microphone is tapped without Pro; the panel shows the paywall.
    var paywall: PendingProChoice?
    /// The language of the current or last dictation.
    private(set) var language: VoiceLanguage

    @ObservationIgnored private let transcriber: any VoiceTranscribing
    @ObservationIgnored private let entitlements: any ProEntitlements
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let preferredLanguages: [String]
    @ObservationIgnored private var transcription: (any VoiceTranscriptionSession)?
    /// The running listen loop; tests await it.
    @ObservationIgnored private(set) var listening: Task<Void, Never>?
    /// The draft before the words heard, which Cancel puts back.
    @ObservationIgnored private var base = ""
    /// Final words heard since `base`.
    @ObservationIgnored private var heard = ""
    /// The draft as this dictation last wrote it. Anything else means the
    /// person edited the field meanwhile, and their edit is kept.
    @ObservationIgnored private var written: String?

    init(
        chat: MapChat,
        transcriber: any VoiceTranscribing,
        entitlements: any ProEntitlements,
        defaults: UserDefaults = AppDefaults.store,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.chat = chat
        self.transcriber = transcriber
        self.entitlements = entitlements
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
        language = VoiceInput.language(in: defaults, preferredLanguages: preferredLanguages)
    }

    // MARK: Reading

    var isListening: Bool { phase == .listening }

    /// The microphone is on or about to be: Cancel applies.
    var isActive: Bool {
        switch phase {
        case .preparing, .downloading, .listening, .finishing: true
        default: false
        }
    }

    /// The chat is where AI shows; voice needs nothing more than that here.
    var isAvailable: Bool { chat.showsEntryPoints }

    /// Not while a step is under way, which has nothing to stop yet.
    var canToggle: Bool {
        switch phase {
        case .preparing, .downloading, .finishing: false
        default: isAvailable
        }
    }

    var failure: VoiceFailure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    // MARK: Intents

    /// The microphone button: starts listening, or stops and keeps the words.
    func toggle() {
        guard canToggle else { return }
        isListening ? stop() : start()
    }

    func start() {
        guard isAvailable, !isActive else { return }
        guard entitlements.allows(.voiceInput) else {
            paywall = PendingProChoice(feature: .voiceInput) { [weak self] in self?.start() }
            return
        }
        // Settings may have changed the language since the last dictation.
        language = VoiceInput.language(in: defaults, preferredLanguages: preferredLanguages)
        base = chat.draft
        heard = ""
        written = nil
        listening = Task { await listen() }
    }

    /// Stops the microphone; the last words still arrive, then the phase goes idle.
    func stop() {
        guard isListening, let transcription else { return }
        phase = .finishing
        Task { await transcription.finish() }
    }

    /// Cancel: stops listening and puts the draft back as it was, unless the
    /// person edited it meanwhile.
    func cancel() {
        let restores = written != nil && chat.draft == written
        end()
        if restores { chat.draft = base }
    }

    /// Stops listening at once and leaves the draft as it is: after Ask, or
    /// when the panel closes.
    func end() {
        listening?.cancel()
        listening = nil
        if let transcription {
            self.transcription = nil
            Task { await transcription.cancel() }
        }
        written = nil
        phase = .idle
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
            guard !Task.isCancelled else { return }
            await listen()
        }
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
            guard !Task.isCancelled else { return }
            let transcription = try await transcriber.start(language)
            guard !Task.isCancelled else {
                await transcription.cancel()
                return
            }
            self.transcription = transcription
            phase = .listening
            for try await update in transcription.updates {
                guard !Task.isCancelled else { return }
                apply(update)
            }
            if self.transcription === transcription {
                self.transcription = nil
                written = nil
                phase = .idle
            }
        } catch {
            transcription = nil
            guard !Task.isCancelled else { return }
            phase = .failed(VoiceFailure(error))
            AccessibilityNotification.Announcement(VoiceFailure(error).message).post()
        }
    }

    private func apply(_ update: VoiceTranscriptUpdate) {
        if let written, chat.draft != written {
            // Typed over: what is in the field now is the new start.
            base = chat.draft
            heard = ""
        }
        let pending: String
        switch update {
        case .volatile(let text):
            pending = text
        case .final(let text):
            heard = Self.join(heard, text)
            pending = ""
        }
        let draft = Self.join(base, Self.join(heard, pending))
        chat.draft = draft
        written = draft
    }

    /// Joins with one space, as dictation into a text field does.
    static func join(_ head: String, _ tail: String) -> String {
        let tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return head }
        let trimmedHead = head.trimmingCharacters(in: .whitespaces)
        guard !trimmedHead.isEmpty else { return tail }
        return trimmedHead.last?.isNewline == true ? trimmedHead + tail : trimmedHead + " " + tail
    }
}
