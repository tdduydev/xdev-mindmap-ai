import Foundation
import MindMapCapture
import Synchronization

/// A `VoiceTranscribing` that plays a script, for tests, previews and the
/// Simulator, where the Speech models are not available.
///
/// A started session yields `heard` straight away, then `heardOnFinish` when
/// it is finished, as the analyzer finalizes the last words.
public final class FakeVoiceTranscriber: VoiceTranscribing {
    private struct State {
        var availability: [VoiceLanguage: VoiceAvailability] = [:]
        var permissionError: VoiceInputError?
        var startError: VoiceInputError?
        var heard: [VoiceTranscriptUpdate] = []
        var heardOnFinish: [VoiceTranscriptUpdate] = []
        var prepared: [VoiceLanguage] = []
        var started: [VoiceLanguage] = []
        var sessions: [FakeSession] = []
    }

    private let state = Mutex(State())

    public init(heard: [VoiceTranscriptUpdate] = [], heardOnFinish: [VoiceTranscriptUpdate] = []) {
        state.withLock {
            $0.heard = heard
            $0.heardOnFinish = heardOnFinish
        }
    }

    public func setAvailability(_ availability: VoiceAvailability, for language: VoiceLanguage) {
        state.withLock { $0.availability[language] = availability }
    }

    public func setPermissionError(_ error: VoiceInputError?) {
        state.withLock { $0.permissionError = error }
    }

    public func setStartError(_ error: VoiceInputError?) {
        state.withLock { $0.startError = error }
    }

    public func script(heard: [VoiceTranscriptUpdate], onFinish: [VoiceTranscriptUpdate] = []) {
        state.withLock {
            $0.heard = heard
            $0.heardOnFinish = onFinish
        }
    }

    /// Sends more words to the running session, as if the user kept talking.
    public func hear(_ update: VoiceTranscriptUpdate) {
        state.withLock { $0.sessions.last }?.yield(update)
    }

    public var preparedLanguages: [VoiceLanguage] { state.withLock { $0.prepared } }
    public var startedLanguages: [VoiceLanguage] { state.withLock { $0.started } }

    // MARK: VoiceTranscribing

    public func availability(for language: VoiceLanguage) async -> VoiceAvailability {
        state.withLock { $0.availability[language] ?? .ready }
    }

    public func prepare(_ language: VoiceLanguage, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.5)
        state.withLock {
            $0.prepared.append(language)
            $0.availability[language] = .ready
        }
        progress(1)
    }

    public func requestPermissions() async throws {
        if let error = state.withLock({ $0.permissionError }) { throw error }
    }

    public func start(_ language: VoiceLanguage) async throws -> any VoiceTranscriptionSession {
        let (error, heard, onFinish) = state.withLock { ($0.startError, $0.heard, $0.heardOnFinish) }
        if let error { throw error }
        let session = FakeSession(heard: heard, onFinish: onFinish)
        state.withLock {
            $0.started.append(language)
            $0.sessions.append(session)
        }
        return session
    }
}

private final class FakeSession: VoiceTranscriptionSession {
    let updates: AsyncThrowingStream<VoiceTranscriptUpdate, any Error>
    private let continuation: AsyncThrowingStream<VoiceTranscriptUpdate, any Error>.Continuation
    private let onFinish: [VoiceTranscriptUpdate]

    init(heard: [VoiceTranscriptUpdate], onFinish: [VoiceTranscriptUpdate]) {
        (updates, continuation) = AsyncThrowingStream.makeStream()
        self.onFinish = onFinish
        heard.forEach { continuation.yield($0) }
    }

    func yield(_ update: VoiceTranscriptUpdate) {
        continuation.yield(update)
    }

    func finish() async {
        onFinish.forEach { continuation.yield($0) }
        continuation.finish()
    }

    func cancel() async {
        continuation.finish()
    }
}
