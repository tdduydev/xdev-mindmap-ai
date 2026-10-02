import SwiftUI

/// Find in the open map: a field, the match count, Previous, Next and Done.
/// It sits above the canvas or the outline; ⌘F, ⌘G and ⇧⌘G reach it from the Edit menu.
struct FindBar: View {
    @Bindable var session: EditorSession
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Find in map", text: $session.findText, prompt: Text("Find in map"))
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .onSubmit(session.findNext)
                .autocorrectionDisabled()
                .accessibilityIdentifier(AccessibilityID.Find.field)
            if !session.findText.isEmpty {
                status
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier(AccessibilityID.Find.status)
            }
            Button(action: session.findPrevious) {
                Label("Find Previous", systemImage: "chevron.up")
                    .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
            }
            .disabled(!session.hasFindMatches)
            .accessibilityIdentifier(AccessibilityID.Find.previous)
            Button(action: session.findNext) {
                Label("Find Next", systemImage: "chevron.down")
                    .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
            }
            .disabled(!session.hasFindMatches)
            .accessibilityIdentifier(AccessibilityID.Find.next)
            Button("Done", action: session.endFind)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(AccessibilityID.Find.done)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(.bar)
        .onAppear { focusIfRequested() }
        .onChange(of: session.findFocusRequest) { _, _ in focusIfRequested() }
    }

    @ViewBuilder
    private var status: some View {
        let total = session.findMatches.count
        if total == 0 {
            Text("No Results")
        } else if let current = session.currentMatchNumber {
            Text("\(current) of \(total)")
        } else {
            Text("^[\(total) match](inflect: true)")
        }
    }

    private func focusIfRequested() {
        guard session.findFocusRequest else { return }
        isFieldFocused = true
        session.findFocusRequest = false
    }
}
