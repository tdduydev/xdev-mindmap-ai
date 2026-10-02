import SwiftUI

struct SidebarView: View {
    @Binding var selection: LibrarySection?
    #if os(iOS)
    @State private var isShowingSettings = false
    #endif

    var body: some View {
        List(LibrarySection.allCases, selection: $selection) { section in
            Label {
                Text(section.title)
            } icon: {
                Image(systemName: section.systemImage)
            }
        }
        .accessibilityIdentifier(AccessibilityID.Sidebar.list)
        .navigationTitle("MindMap AI")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        #else
        // The Mac opens Settings from the app menu (⌘,); iPad and iPhone need a button.
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier(AccessibilityID.Sidebar.settings)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        #endif
    }
}
