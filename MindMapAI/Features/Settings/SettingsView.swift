import SwiftUI

/// Settings: a tabbed window on the Mac (⌘,), a sheet on iPad and iPhone.
struct SettingsView: View {
    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        #if os(macOS)
        TabView {
            Tab("General", systemImage: "gearshape") {
                Form {
                    GeneralSettingsSection()
                    AISettingsSection()
                    ExportSettingsSection()
                }
            }
            Tab("Privacy", systemImage: "hand.raised") {
                Form { PrivacySettingsSection() }
            }
            Tab("About", systemImage: "info.circle") {
                Form { AboutSettingsSection() }
            }
        }
        .formStyle(.grouped)
        .frame(width: Metrics.settingsWidth)
        #else
        NavigationStack {
            Form {
                GeneralSettingsSection()
                AISettingsSection()
                ExportSettingsSection()
                PrivacySettingsSection()
                AboutSettingsSection()
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #endif
    }
}

struct GeneralSettingsSection: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    var body: some View {
        Section("General") {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearancePreference.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
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
