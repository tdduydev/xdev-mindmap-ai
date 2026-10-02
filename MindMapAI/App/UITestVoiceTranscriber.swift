#if DEBUG
import MindMapCapture

/// Voice input in the UI test mode, in debug builds only: the Simulator has no
/// speech model, so listening hears `UITestVoice.heard` and nothing more.
final class UITestVoiceTranscriber: VoiceTranscribing {
    func availability(for language: VoiceLanguage) async -> VoiceAvailability { .ready }
    func prepare(_ language: VoiceLanguage, progress: @escaping @Sendable (Double) -> Void) async throws {}
    func requestPermissions() async throws {}

    func start(_ language: VoiceLanguage) async throws -> any VoiceTranscriptionSession {
        Session()
    }

    private final class Session: VoiceTranscriptionSession {
        let updates: AsyncThrowingStream<VoiceTranscriptUpdate, any Error>
        private let continuation: AsyncThrowingStream<VoiceTranscriptUpdate, any Error>.Continuation

        init() {
            (updates, continuation) = AsyncThrowingStream.makeStream()
            continuation.yield(.final(UITestVoice.heard))
        }

        func finish() async { continuation.finish() }
        func cancel() async { continuation.finish() }
    }
}
#endif
