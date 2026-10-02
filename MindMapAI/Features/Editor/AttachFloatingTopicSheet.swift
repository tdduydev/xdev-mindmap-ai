import MindMapDomain
import SwiftUI

struct AttachFloatingTopicSheetPresenter: ViewModifier {
    @Bindable var session: EditorSession

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { session.attachTarget != nil },
            set: { if !$0 { session.attachTarget = nil } }
        )) {
            if let id = session.attachTarget {
                AttachFloatingTopicSheet(session: session, nodeID: id)
            }
        }
    }
}

/// A keyboard and VoiceOver path to the same attach command as canvas drop.
struct AttachFloatingTopicSheet: View {
    @Bindable var session: EditorSession
    let nodeID: NodeID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.rows.filter { session.canMove([nodeID], to: .child(of: $0.id)) }) { row in
                    Button {
                        session.attach(nodeID, to: row.id)
                        dismiss()
                    } label: {
                        Text(row.node.title.isEmpty ? String(localized: "Untitled Topic") : row.node.title)
                            .padding(.leading, CGFloat(row.depth) * Spacing.outlineIndent)
                    }
                }
            }
            .navigationTitle("Attach to Topic")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
