import SwiftUI

struct SidebarView: View {
    @Binding var selection: LibrarySection?

    var body: some View {
        List(LibrarySection.allCases, selection: $selection) { section in
            Label {
                Text(section.title)
            } icon: {
                Image(systemName: section.systemImage)
            }
        }
        .navigationTitle("MindMap AI")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        #endif
    }
}
