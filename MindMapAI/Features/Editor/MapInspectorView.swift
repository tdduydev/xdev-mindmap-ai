import MindMapDomain
import SwiftUI

/// The inspector beside an open map: settings of the map itself. Topic
/// details (the note of FR-EDT-13) belong in here too when they arrive.
struct MapInspectorView: View {
    let session: EditorSession

    var body: some View {
        Form {
            Section("Map") {
                Picker("Theme", selection: themeBinding) {
                    ForEach(MindMapTheme.allCases) { theme in
                        HStack(spacing: Spacing.sm) {
                            Text(theme.title)
                            ThemeSwatch(theme: theme)
                        }
                        .tag(theme)
                    }
                }
                .pickerStyle(.inline)
            }
        }
        .formStyle(.grouped)
    }

    /// Every pick goes through the session, so it is one "Change Theme" undo step.
    private var themeBinding: Binding<MindMapTheme> {
        Binding(get: { session.map.theme }, set: { session.changeTheme(to: $0) })
    }
}
