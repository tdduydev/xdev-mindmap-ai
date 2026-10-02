import AVFoundation
import Foundation
import Speech
import Synchronization

/// Voice input with `SpeechAnalyzer`, entirely on the device (FR-AI-21).
///
/// Vietnamese uses `DictationTranscriber`; English uses `SpeechTranscriber`,
/// falling back to `DictationTranscriber` on devices without it. Never
/// `SFSpeechRecognizer` for recognition: it sends Vietnamese to a server
/// (docs/on-device-ai.md); it is only asked for the permission.
public struct AppleSpeechTranscriber: VoiceTranscribing {
    public init() {}

    public func availability(for language: VoiceLanguage) async -> VoiceAvailability {
        guard let module = await Self.module(for: language) else { return .unsupported }
        switch await AssetInventory.status(forModules: [module]) {
        case .installed: return .ready
        case .downloading: return .downloading
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    public func prepare(_ language: VoiceLanguage, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let module = await Self.module(for: language) else { throw VoiceInputError.unsupportedLanguage }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
        // Progress is KVO-observable only; polling keeps this free of NSObject observers.
        let reporter = Task {
            while !Task.isCancelled {
                progress(request.progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { reporter.cancel() }
        try await request.downloadAndInstall()
        progress(1)
    }

    public func requestPermissions() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw VoiceInputError.microphoneDenied }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw VoiceInputError.speechRecognitionDenied }
    }

    public func start(_ language: VoiceLanguage) async throws -> any VoiceTranscriptionSession {
        guard let locale = await Self.supportedLocale(for: language) else { throw VoiceInputError.unsupportedLanguage }
        if language == .english, SpeechTranscriber.isAvailable {
            return try await AppleTranscriptionSession.start(
                SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
            )
        }
        return try await AppleTranscriptionSession.start(
            DictationTranscriber(
                locale: locale,
                contentHints: [],
                transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
        )
    }

    // MARK: Modules

    private static func supportedLocale(for language: VoiceLanguage) async -> Locale? {
        if language == .english, SpeechTranscriber.isAvailable {
            return await SpeechTranscriber.supportedLocale(equivalentTo: language.locale)
        }
        return await DictationTranscriber.supportedLocale(equivalentTo: language.locale)
    }

    /// A module only for asking about assets; each session makes its own.
    private static func module(for language: VoiceLanguage) async -> (any SpeechModule)? {
        guard let locale = await supportedLocale(for: language) else { return nil }
        if language == .english, SpeechTranscriber.isAvailable {
            return SpeechTranscriber(locale: locale, preset: .transcription)
        }
        return DictationTranscriber(locale: locale, preset: .longDictation)
    }
}

/// The two transcribers' results, which share no protocol for their text.
private protocol TranscribedText: SpeechModuleResult {
    var text: AttributedString { get }
}

extension SpeechTranscriber.Result: TranscribedText {}
extension DictationTranscriber.Result: TranscribedText {}

/// Microphone → converter → `SpeechAnalyzer` → updates.
private final class AppleTranscriptionSession: VoiceTranscriptionSession {
    let updates: AsyncThrowingStream<VoiceTranscriptUpdate, any Error>
    private let output: AsyncThrowingStream<VoiceTranscriptUpdate, any Error>.Continuation
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let analyzer: SpeechAnalyzer
    private let microphone: Microphone
    private let reader: Mutex<Task<Void, Never>?> = Mutex(nil)

    private init<Module: SpeechModule>(module: Module, input continuation: AsyncStream<AnalyzerInput>.Continuation, microphone: Microphone) where Module.Result: TranscribedText {
        (updates, output) = AsyncThrowingStream.makeStream()
        input = continuation
        analyzer = SpeechAnalyzer(modules: [module])
        self.microphone = microphone
        let output = output
        reader.withLock {
            $0 = Task {
                do {
                    for try await result in module.results {
                        let text = String(result.text.characters)
                        output.yield(result.isFinal ? .final(text) : .volatile(text))
                    }
                    output.finish()
                } catch {
                    output.finish(throwing: VoiceInputError.transcriptionFailed)
                }
            }
        }
    }

    static func start<Module: SpeechModule>(_ module: Module) async throws -> AppleTranscriptionSession where Module.Result: TranscribedText {
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw VoiceInputError.unsupportedLanguage
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let microphone = try Microphone(analyzerFormat: format, input: continuation)
        let session = AppleTranscriptionSession(module: module, input: continuation, microphone: microphone)
        do {
            try await session.analyzer.prepareToAnalyze(in: format)
            try await session.analyzer.start(inputSequence: stream)
            try microphone.start()
        } catch {
            await session.cancel()
            throw error as? VoiceInputError ?? .transcriptionFailed
        }
        return session
    }

    func finish() async {
        microphone.stop()
        input.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            await analyzer.cancelAndFinishNow()
        }
        // The results end once the analyzer finishes; wait so the last words arrive.
        await reader.withLock { $0 }?.value
    }

    func cancel() async {
        microphone.stop()
        input.finish()
        await analyzer.cancelAndFinishNow()
        reader.withLock { $0 }?.cancel()
        output.finish()
    }
}

/// The audio engine's input, converted to the analyzer's format.
private final class Microphone: @unchecked Sendable {
    // Touched from the caller and the audio thread; the engine and converter are
    // set up once in `init`, and AVAudioEngine allows start/stop from any thread.
    private let engine = AVAudioEngine()
    private let input: AsyncStream<AnalyzerInput>.Continuation

    init(analyzerFormat: AVAudioFormat, input: AsyncStream<AnalyzerInput>.Continuation) throws {
        self.input = input
        #if os(iOS)
        // AVAudioSession exists only on iOS; the Mac needs no audio session.
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let node = engine.inputNode
        let micFormat = node.outputFormat(forBus: 0)
        guard micFormat.channelCount > 0, micFormat.sampleRate > 0 else { throw VoiceInputError.noMicrophone }
        guard let converter = AVAudioConverter(from: micFormat, to: analyzerFormat) else { throw VoiceInputError.transcriptionFailed }
        // The default priming swallows the first frames of each buffer.
        converter.primeMethod = .none
        node.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            guard let converted = Self.convert(buffer, with: converter, to: analyzerFormat) else { return }
            input.yield(AnalyzerInput(buffer: converted))
        }
    }

    func start() throws {
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw VoiceInputError.noMicrophone
        }
    }

    /// Also undoes a failed start: the tap and the iOS audio session are set
    /// up in `init`, before the engine runs.
    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : converted
    }
}
