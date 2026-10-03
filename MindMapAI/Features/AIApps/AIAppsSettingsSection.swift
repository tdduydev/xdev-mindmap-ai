#if os(macOS)
import MindMapMCP
import OSLog
import SwiftUI

/// Settings ▸ AI Apps, Mac only (docs/settings.md, docs/mcp.md M2): the
/// switch, the port, the apps that hold a token, and Add App…. Everything
/// applies at once; nothing here writes another app's configuration.
struct AIAppsSettingsSection: View {
    @Environment(AIAppsHost.self) private var host: AIAppsHost?

    var body: some View {
        if let host {
            AIAppsSettingsContent(host: host)
        } else {
            Section {
                Text("AI apps are not available because your maps couldn’t be opened.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AIAppsSettingsContent: View {
    let host: AIAppsHost
    @State private var addingApp = false
    @State private var revoking: AIAppsHost.ConnectedApp?
    @State private var invalidPort = false
    @State private var failed: String?

    var body: some View {
        Section {
            Toggle("Allow AI Apps to Read Maps", isOn: Binding(get: { host.isEnabled }, set: { host.setEnabled($0) }))
                .accessibilityIdentifier(AccessibilityID.Settings.aiAppsSwitch)
            LabeledContent("Port") {
                TextField("Port", value: portBinding, format: .number.grouping(.never))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: Metrics.portFieldWidth)
                    .accessibilityIdentifier(AccessibilityID.Settings.aiAppsPort)
            }
            LabeledContent("Status") {
                // A new view per status: a Form row keeps the accessibility
                // value of the first text it showed, so the status still said "Off"
                // after the port had opened (MM-89).
                Text(statusTitle)
                    .id(statusTitle)
                    .accessibilityIdentifier(AccessibilityID.Settings.aiAppsStatus)
            }
            if case .listening(let port) = host.status {
                LabeledContent("Address") {
                    Text(verbatim: AIAppSetup.endpoint(port: port))
                        .textSelection(.enabled)
                }
            }
        } footer: {
            // Said before the switch is turned on (App Review 5.1.2(i)): the
            // switch is the permission.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // System symbol rather than a colour, as the iCloud status does.
                if invalidPort {
                    Label("Choose a port from 1024 to 65535.", systemImage: "exclamationmark.triangle")
                } else if case .portUnavailable(let port) = host.status {
                    Label("Another app may be using port \(String(port)). Choose another port, then update the setup in each connected app.", systemImage: "exclamationmark.triangle")
                }
                Text("AI apps you connect, like Claude or ChatGPT, can read the titles and notes of your maps and may send them to their own AI provider under that app’s terms. xDev receives nothing. Text in a map can try to steer the app that reads it.")
                Text("Turning this off stops every app from reading; connected apps stay in the list.")
            }
        }

        Section {
            Toggle("Allow Suggestions", isOn: Binding(get: { host.allowsSuggestions }, set: { host.setAllowsSuggestions($0) }))
                .accessibilityIdentifier(AccessibilityID.Settings.aiAppsAllowSuggestions)
        } footer: {
            Text("Connected apps can suggest new topics, labelled with the app’s name. Nothing is added until you accept, and apps can’t edit or delete anything.")
        }

        Section {
            if host.keychainFailed {
                Text("Couldn’t read the connected apps from the Keychain.")
                    .foregroundStyle(.secondary)
            } else if host.apps.isEmpty {
                Text("No apps connected yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(host.apps) { app in
                ConnectedAppRow(app: app) { revoking = app }
            }
            Button("Add App…") { addingApp = true }
                .accessibilityIdentifier(AccessibilityID.Settings.aiAppsAdd)
                // On the one row that is always there: a modifier on a Section
                // goes to each of its rows, one sheet per row on one binding (MM-92).
                .sheet(isPresented: $addingApp) {
                    AddAIAppSheet(host: host)
                }
                .confirmationDialog(
                    revokeTitle,
                    isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
                    presenting: revoking
                ) { app in
                    Button("Revoke", role: .destructive) { revoke(app) }
                    Button("Cancel", role: .cancel) {}
                } message: { app in
                    Text("\(app.name) can no longer read your maps. To connect it again, add it again and paste the new setup.")
                }
                .alert(
                    "Couldn’t Revoke Access",
                    isPresented: Binding(get: { failed != nil }, set: { if !$0 { failed = nil } })
                ) {
                    Button("OK") {}
                } message: {
                    Text("The app can no longer read your maps, but its token is still in the Keychain. Try again after reopening MindMap AI.")
                }
        } header: {
            Text("Connected Apps")
        } footer: {
            Text("MindMap AI must be open for AI apps to read your maps. Each app gets its own token, so you can revoke one without the others.")
        }
    }

    private var revokeTitle: Text {
        Text("Revoke Access for “\(revoking?.name ?? "")”?")
    }

    private var portBinding: Binding<Int> {
        Binding(
            get: { Int(host.port) },
            set: { value in
                invalidPort = !(UInt16(exactly: value).map(host.setPort) ?? false)
            }
        )
    }

    private var statusTitle: String {
        switch host.status {
        case .off: String(localized: "Off")
        case .starting: String(localized: "Starting…")
        case .listening: String(localized: "Ready")
        case .portUnavailable(let port): String(localized: "Port \(String(port)) Is Unavailable")
        }
    }

    private func revoke(_ app: AIAppsHost.ConnectedApp) {
        do {
            try host.revoke(app.id)
        } catch {
            Log.mcp.error("Deleting an AI app token failed: \(String(describing: error), privacy: .public)")
            failed = app.name
        }
    }
}

private struct ConnectedAppRow: View {
    let app: AIAppsHost.ConnectedApp
    let revoke: () -> Void

    var body: some View {
        LabeledContent {
            Button("Revoke…", action: revoke)
        } label: {
            Text(app.name)
            // Relative times move on by themselves once a minute.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                if let lastRead = app.lastRead {
                    Text("Read \(lastRead.formatted(.relative(presentation: .named)))")
                } else {
                    Text("Not used since MindMap AI opened")
                }
            }
        }
    }
}

/// Names the app, makes its token and shows the setup once, with Copy.
private struct AddAIAppSheet: View {
    let host: AIAppsHost
    @Environment(\.dismiss) private var dismiss
    @State private var kind = AIAppKind.claudeCode
    @State private var name = AIAppKind.claudeCode.suggestedName
    @State private var token: String?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let token {
                    setup(token: token)
                } else {
                    naming
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                if token == nil {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Add", action: add)
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Spacing.lg)
        }
        .frame(width: Metrics.addAppSheetWidth)
        .alert("Couldn’t Add the App", isPresented: $failed) {
            Button("OK") {}
        } message: {
            Text("The token couldn’t be saved in the Keychain. Try again.")
        }
    }

    private var naming: some View {
        Section {
            Picker("App", selection: $kind) {
                ForEach(AIAppKind.allCases) { kind in
                    Text(verbatim: kind.title).tag(kind)
                }
            }
            .onChange(of: kind) { old, new in
                // Keep a name the person typed; follow the picker otherwise.
                if name == old.suggestedName { name = new.suggestedName }
            }
            TextField("Name", text: $name, prompt: Text(verbatim: "Claude Code"))
        } header: {
            Text("Add App")
        } footer: {
            Text("The name is only for you, to tell apps apart in this list.")
        }
    }

    @ViewBuilder
    private func setup(token: String) -> some View {
        let snippet = AIAppSetup.snippet(for: kind, port: host.port, token: token)
        Section {
            Text(verbatim: snippet)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Copy") { SystemClipboard().setText(snippet) }
        } header: {
            Text(verbatim: name.trimmingCharacters(in: .whitespacesAndNewlines))
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(kind.instructions)
                Text("This is the only time the token is shown. If you lose it, revoke this app and add it again.")
                if !host.isEnabled {
                    Text("Turn on Allow AI Apps to Read Maps so the app can connect.")
                }
            }
        }
    }

    private func add() {
        do {
            token = try host.addApp(named: name)
        } catch {
            Log.mcp.error("Saving an AI app token failed: \(String(describing: error), privacy: .public)")
            failed = true
        }
    }
}
#endif
