import Foundation
import MindMapAIApple
import MindMapAICore
import Observation

/// What the app's AI can do on this device, shared by every window. The
/// provider is made on first use, and asking for capabilities does not load
/// the model (NFR-PERF-05).
@Observable
final class AIService {
    /// Nil until the first check.
    private(set) var capabilities: AICapabilities?

    /// Settings ▸ AI ▸ Use AI Features. Kept per device, because whether AI
    /// can run differs per device. Off takes AI out of the editor at once;
    /// suggestions already on a canvas stay until accepted or discarded.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    @ObservationIgnored let entitlements: any ProEntitlements
    @ObservationIgnored private let makeProvider: () -> any AIProvider
    @ObservationIgnored private var cachedProvider: (any AIProvider)?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    static let enabledKey = "ai.enabled"

    /// How long to wait before asking again while the model downloads.
    static let downloadRetryInterval: Duration = .seconds(30)

    init(
        provider: @escaping () -> any AIProvider = { AppleFoundationModelProvider() },
        entitlements: any ProEntitlements,
        defaults: UserDefaults = AppDefaults.store
    ) {
        makeProvider = provider
        self.entitlements = entitlements
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    var provider: any AIProvider {
        if let cachedProvider { return cachedProvider }
        let provider = makeProvider()
        cachedProvider = provider
        return provider
    }

    /// False until the first check, so a device that can never run the model
    /// (an Intel Mac) does not show AI even for a moment (FR-AI-02).
    var showsEntryPoints: Bool { capabilities?.showsAIEntryPoints ?? false }

    /// Whether the editor shows its AI buttons and menus: the device can run
    /// AI and the person has not turned it off. The menu bar keeps its AI
    /// menu either way, disabled with the reason, since Mac menus never hide items.
    var showsControls: Bool { showsEntryPoints && isEnabled }

    var modelState: AIAvailability { capabilities?.model ?? .unknown }

    /// The one line AI menus show when they cannot run; nil when ready.
    var unavailableReason: String? {
        isEnabled ? AIAvailabilityText.explanation(for: modelState) : AIAvailabilityText.turnedOff
    }

    /// Asks again; called when the app becomes active, since Apple Intelligence
    /// can be turned on or off meanwhile. While the model downloads it keeps
    /// asking, so "Getting ready" clears by itself.
    func refresh() async {
        let current = await provider.capabilities()
        capabilities = current
        retry?.cancel()
        retry = nil
        guard current.model == .modelDownloading else { return }
        retry = Task { [weak self] in
            try? await Task.sleep(for: Self.downloadRetryInterval)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
}
