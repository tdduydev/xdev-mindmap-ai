import MindMapDomain
import MindMapPersistence
import SwiftUI

/// Settings: a window of panes on the Mac (⌘,), a list with one page per pane
/// on iPad and iPhone, the way the system Settings app reads (docs/settings.md).
struct SettingsView: View {
    let environment: AppEnvironment?
    let showRecentlyDeleted: (() -> Void)?
    @Environment(AIService.self) private var ai
    #if os(macOS)
    @AppStorage(SettingsPane.storageKey, store: AppDefaults.store) private var storedPane = SettingsPane.general
    #else
    @Environment(ProEntitlement.self) private var pro
    @Environment(\.dismiss) private var dismiss
    #endif

    init(environment: AppEnvironment? = nil, showRecentlyDeleted: (() -> Void)? = nil) {
        self.environment = environment
        self.showRecentlyDeleted = showRecentlyDeleted
    }

    private var panes: [SettingsPane] {
        #if os(macOS)
        SettingsPane.available(showsAI: ai.showsEntryPoints, showsAIApps: true)
        #else
        // No iPad or iPhone client reaches a server on the device (docs/mcp.md).
        SettingsPane.available(showsAI: ai.showsEntryPoints, showsAIApps: false)
        #endif
    }

    var body: some View {
        #if os(macOS)
        // The last pane reopens (HIG Settings); the window title follows the pane by itself.
        TabView(selection: Binding(get: { storedPane.resolved(in: panes) }, set: { storedPane = $0 })) {
            ForEach(panes) { pane in
                Tab(value: pane) {
                    SettingsPaneView(pane: pane, environment: environment, showRecentlyDeleted: showRecentlyDeleted)
                } label: {
                    Label { Text(pane.title) } icon: { Image(systemName: pane.systemImage) }
                }
                .accessibilityIdentifier(AccessibilityID.Settings.pane(pane.rawValue))
            }
        }
        .frame(width: Metrics.settingsWidth)
        #else
        NavigationStack {
            List {
                // Pro status on top, as the system app puts the account first.
                Section {
                    paneLink(.pro, value: pro.isUnlocked ? String(localized: "Unlocked") : String(localized: "Not unlocked"))
                }
                Section {
                    ForEach(panes.filter { $0 != .pro }) { paneLink($0) }
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsPane.self) { pane in
                SettingsPaneView(pane: pane, environment: environment, showRecentlyDeleted: showRecentlyDeleted)
                    .navigationTitle(Text(pane.title))
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.Settings.done)
                }
            }
        }
        #endif
    }

    #if os(iOS)
    private func paneLink(_ pane: SettingsPane, value: String? = nil) -> some View {
        NavigationLink(value: pane) {
            LabeledContent {
                if let value { Text(value) }
            } label: {
                Label { Text(pane.title) } icon: { Image(systemName: pane.systemImage) }
            }
        }
        .accessibilityIdentifier(AccessibilityID.Settings.pane(pane.rawValue))
    }
    #endif
}

/// One pane, the same view on every platform; only its container differs.
struct SettingsPaneView: View {
    let pane: SettingsPane
    var environment: AppEnvironment?
    var showRecentlyDeleted: (() -> Void)?
    @Environment(AIService.self) private var ai

    var body: some View {
        Form {
            switch pane {
            case .general:
                GeneralSettingsSection()
                // No AI pane where Apple Intelligence can never run (an Intel Mac).
                if !ai.showsEntryPoints { VoiceInputSettingsSection() }
            case .export: ExportSettingsSection()
            case .ai: AISettingsSection()
            case .data:
                CloudSyncSettingsSection()
                if let environment {
                    DataSettingsSection(environment: environment, showRecentlyDeleted: showRecentlyDeleted)
                }
            case .aiApps:
                #if os(macOS)
                AIAppsSettingsSection()
                #endif
            case .pro: ProSettingsSection()
            case .privacy: PrivacySettingsSection()
            case .about: AboutSettingsSection()
            }
        }
        .formStyle(.grouped)
    }
}

/// The panes, in the order of docs/settings.md. Data holds iCloud (MM-6);
/// MM-45 adds the rest of it. AI Apps (MM-46) is on the Mac only.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case export
    case ai
    case data
    case aiApps
    case pro
    case privacy
    case about

    /// The Mac's last pane (HIG Settings: reopen the most recently viewed pane).
    static let storageKey = "settings.pane"

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .general: "General"
        case .export: "Export"
        case .ai: "AI"
        case .data: "Data"
        case .aiApps: "AI Apps"
        case .pro: "Pro"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .export: "square.and.arrow.up"
        case .ai: "sparkles"
        case .data: "icloud"
        case .aiApps: "point.3.connected.trianglepath.dotted"
        case .pro: "star"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }

    /// AI goes where Apple Intelligence can never run, like every AI entry
    /// point; AI Apps everywhere but the Mac.
    static func available(showsAI: Bool, showsAIApps: Bool) -> [SettingsPane] {
        allCases.filter { (showsAI || $0 != .ai) && (showsAIApps || $0 != .aiApps) }
    }

    /// A stored pane that is not offered here opens General.
    func resolved(in panes: [SettingsPane]) -> SettingsPane {
        panes.contains(self) ? self : .general
    }
}

struct GeneralSettingsSection: View {
    @AppStorage(AppearancePreference.storageKey, store: AppDefaults.store) private var appearance = AppearancePreference.system
    @AppStorage(NewMapPreferences.themeKey, store: AppDefaults.store) private var newMapTheme = MindMapTheme.standard
    @Environment(ProEntitlement.self) private var pro
    @State private var paywall: PendingProChoice?

    private var themesLocked: Bool { !pro.allows(.extraThemes) }

    var body: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearancePreference.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Settings.appearance)
            Picker("Theme for New Maps", selection: Binding(get: { newMapTheme }, set: choose)) {
                ForEach(MindMapTheme.allCases) { theme in
                    ProChoiceLabel(title: theme.title, isLocked: theme.requiresPro && themesLocked)
                        .tag(theme)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Settings.newMapTheme)
        } footer: {
            if newMapTheme.requiresPro && themesLocked {
                Text("New maps use Standard until MindMap AI Pro is unlocked.")
            } else {
                Text("Each map keeps its own theme, which you can change while the map is open.")
            }
        }
        .proChoicePaywall($paywall)
    }

    private func choose(_ theme: MindMapTheme) {
        if theme.requiresPro && themesLocked {
            paywall = PendingProChoice(feature: .extraThemes) { newMapTheme = theme }
        } else {
            newMapTheme = theme
        }
    }
}

/// Plain statements of where data goes. Each row must stay true: Data
/// Storage follows sync, AI follows Use AI Features, AI Apps its switch;
/// change the AI row if AI ever leaves the device.
struct PrivacySettingsSection: View {
    @Environment(CloudSyncMonitor.self) private var sync
    @Environment(AIService.self) private var ai
    #if os(macOS)
    @Environment(AIAppsHost.self) private var aiApps: AIAppsHost?
    #endif

    var body: some View {
        Section {
            LabeledContent(
                "Data Storage",
                value: sync.state.isActive
                    ? String(localized: "On this device and in your private iCloud")
                    : String(localized: "On this device")
            )
            LabeledContent("xDev Servers", value: String(localized: "None. Your maps are never sent to xDev."))
            LabeledContent("Analytics", value: String(localized: "None"))
            if let aiRow = PrivacyRows.ai(showsEntryPoints: ai.showsEntryPoints, isEnabled: ai.isEnabled) {
                LabeledContent("AI", value: aiRow)
                    .accessibilityIdentifier(AccessibilityID.Settings.privacyAI)
            }
            LabeledContent("Voice Input", value: PrivacyRows.voiceInput)
                .accessibilityIdentifier(AccessibilityID.Settings.privacyVoiceInput)
            #if os(macOS)
            LabeledContent(
                "AI Apps",
                value: aiApps?.isEnabled == true
                    ? String(localized: "On: apps you connect can read your maps and handle them under their own terms")
                    : String(localized: "Off")
            )
            .accessibilityIdentifier(AccessibilityID.Settings.aiAppsPrivacy)
            #endif
            Link("Privacy Policy", destination: AppLinks.privacyPolicy)
        } header: {
            Text("Privacy")
        } footer: {
            Text("MindMap AI keeps your maps on your devices. There is no account and no tracking.")
        }
    }
}

/// The Privacy rows that depend on a setting, apart from the view so tests can read them.
enum PrivacyRows {
    /// Nil where AI can never run, so the row is not shown.
    static func ai(showsEntryPoints: Bool, isEnabled: Bool) -> String? {
        guard showsEntryPoints else { return nil }
        return isEnabled ? String(localized: "On this device. Nothing is sent to xDev.") : String(localized: "Turned off")
    }

    /// Speech is transcribed by SpeechAnalyzer on the device (docs/privacy.md).
    static var voiceInput: String { String(localized: "On this device. Audio is not kept.") }
}

/// No Acknowledgements row: the fonts' SIL OFL asks for its notice to travel
/// with the fonts, which `Fonts/OFL.txt` in the bundle does (docs/settings.md).
struct AboutSettingsSection: View {
    var body: some View {
        Section("About") {
            BrandMark()
                .padding(.vertical, Spacing.xs)
            LabeledContent("Version", value: Self.version)
            Text("Think. Draw. Connect.")
                .foregroundStyle(.secondary)
            Link("Website", destination: AppLinks.website)
            Link("Support", destination: AppLinks.support)
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        // Under a "Version" label, so the numbers alone; they read the same in every language.
        return "\(marketing) (\(build))"
    }
}
