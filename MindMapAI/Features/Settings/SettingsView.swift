import MindMapDomain
import SwiftUI

/// Settings: a window of panes on the Mac (⌘,), a list with one page per pane
/// on iPad and iPhone, the way the system Settings app reads (docs/settings.md).
struct SettingsView: View {
    @Environment(AIService.self) private var ai
    #if os(macOS)
    @AppStorage(SettingsPane.storageKey, store: AppDefaults.store) private var storedPane = SettingsPane.general
    #else
    @Environment(ProEntitlement.self) private var pro
    @Environment(\.dismiss) private var dismiss
    #endif

    private var panes: [SettingsPane] { SettingsPane.available(showsAI: ai.showsEntryPoints) }

    var body: some View {
        #if os(macOS)
        // The last pane reopens (HIG Settings); the window title follows the pane by itself.
        TabView(selection: Binding(get: { storedPane.resolved(in: panes) }, set: { storedPane = $0 })) {
            ForEach(panes) { pane in
                Tab(value: pane) {
                    SettingsPaneView(pane: pane)
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
                SettingsPaneView(pane: pane)
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

    var body: some View {
        Form {
            switch pane {
            case .general: GeneralSettingsSection()
            case .export: ExportSettingsSection()
            case .ai: AISettingsSection()
            case .pro: ProSettingsSection()
            case .privacy: PrivacySettingsSection()
            case .about: AboutSettingsSection()
            }
        }
        .formStyle(.grouped)
    }
}

/// The panes, in the order of docs/settings.md. Data (MM-45) and AI Apps
/// (MM-46, Mac only) slot in after AI once they are built.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case export
    case ai
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
        case .pro: "star"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }

    /// AI goes where Apple Intelligence can never run, like every AI entry point.
    static func available(showsAI: Bool) -> [SettingsPane] {
        allCases.filter { showsAI || $0 != .ai }
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

/// Plain statements of where data goes. Each row must stay true: change Data
/// Storage when iCloud sync ships, and the AI row if AI ever leaves the device.
struct PrivacySettingsSection: View {
    var body: some View {
        Section {
            LabeledContent("Data Storage", value: String(localized: "On this device"))
            LabeledContent("xDev Servers", value: String(localized: "None. Your maps are never sent to xDev."))
            LabeledContent("Analytics", value: String(localized: "None"))
            LabeledContent("AI", value: String(localized: "On this device. Nothing is sent to xDev."))
            Link("Privacy Policy", destination: AppLinks.privacyPolicy)
        } header: {
            Text("Privacy")
        } footer: {
            Text("MindMap AI keeps your maps on your devices. There is no account and no tracking.")
        }
    }
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
