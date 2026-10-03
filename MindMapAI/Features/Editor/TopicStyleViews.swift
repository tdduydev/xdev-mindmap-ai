import MindMapDomain
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Format ▸ Topic Color and the context menus' Color: None, then each colour
/// with its shape and name, so no choice is told by hue alone (FR-ORG-02).
/// Pickers have no keys of their own (docs/node-organization.md).
struct TopicColorMenu: View {
    let title: LocalizedStringKey
    let session: EditorSession
    /// The topics it acts on; the selection when nil.
    var targets: [NodeID]?

    var body: some View {
        Menu(title) {
            let coverage = session.colorCoverage(targets)
            Toggle("None", isOn: binding(nil, coverage))
            Divider()
            ForEach(TopicColor.all, id: \.self) { color in
                Toggle(isOn: binding(color, coverage)) {
                    Label(color.title, systemImage: color.shapeSymbol)
                }
            }
        }
        .disabled(session.colorTargets(targets).isEmpty)
    }

    /// On when every target has the colour; choosing it gives it to them all.
    private func binding(_ color: TopicColor?, _ coverage: StyleCoverage<TopicColor?>) -> Binding<Bool> {
        Binding(get: { coverage == .all(color) }, set: { _ in session.setColor(color, on: targets) })
    }
}

/// Format ▸ Topic Symbol and the context menus' Symbol.
struct TopicSymbolMenu: View {
    let title: LocalizedStringKey
    let session: EditorSession
    var targets: [NodeID]?

    var body: some View {
        Menu(title) {
            Button("Choose Symbol…") { session.beginChoosingSymbol(for: targets) }
            Button("Remove Symbol") { session.setSymbol(nil, on: targets) }
                .disabled(session.symbolCoverage(targets) == .all(nil))
        }
        .disabled(session.symbolTargets(targets).isEmpty)
    }
}

/// The inspector's Style section: colour and symbol of every selected topic,
/// a mixed selection shown as such.
struct TopicStyleInspector: View {
    let session: EditorSession

    var body: some View {
        let color = session.colorCoverage()
        LabeledContent("Color") {
            Menu {
                Button("None") { session.setColor(nil) }
                Divider()
                ForEach(TopicColor.all, id: \.self) { item in
                    Button { session.setColor(item) } label: {
                        Label(item.title, systemImage: item.shapeSymbol)
                    }
                }
            } label: {
                switch color {
                case .all(let value?): TopicColorLabel(color: value)
                case .mixed: Text("Mixed")
                default: Text("None")
                }
            }
            .fixedSize()
            .disabled(!session.canColorSelection)
            .accessibilityIdentifier(AccessibilityID.Inspector.topicColor)
        }
        LabeledContent("Symbol") {
            HStack(spacing: Spacing.sm) {
                switch session.symbolCoverage() {
                case .all(let symbol?):
                    if let drawable = TopicSymbolCatalog.drawable(symbol) {
                        TopicSymbolImage(symbol: drawable)
                            .accessibilityLabel(Text(verbatim: TopicSymbolCatalog.spokenName(of: drawable)))
                    }
                case .mixed: Text("Mixed").foregroundStyle(.secondary)
                default: EmptyView()
                }
                Button("Choose Symbol…") { session.beginChoosingSymbol() }
                    .accessibilityIdentifier(AccessibilityID.Inspector.topicSymbol)
            }
        }
        if session.selectedIDs.contains(where: { $0 == session.rootID }) {
            Text("The central topic keeps its own color.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A colour as the chrome shows it: its shape in the colour, then its name.
struct TopicColorLabel: View {
    let color: TopicColor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Label {
            Text(color.title)
        } icon: {
            Image(systemName: color.shapeSymbol)
                .foregroundStyle(color.token[ColorVariant(colorScheme: colorScheme, contrast: contrast)].color)
        }
    }
}

/// A catalogue symbol or an emoji at the surrounding font.
struct TopicSymbolImage: View {
    let symbol: TopicMark.Symbol

    var body: some View {
        switch symbol {
        case .system(let name): Image(systemName: name)
        case .emoji(let emoji): Text(verbatim: emoji)
        }
    }
}

/// Choose Symbol…: the catalogue as a grid, an emoji field, Remove Symbol.
/// Each pick is one "Change Symbol" step and closes the sheet.
struct TopicSymbolPicker: View {
    let session: EditorSession
    let targets: [NodeID]
    @State private var emoji = ""
    @FocusState private var isEmojiFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Symbols") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.minimumHitTarget), spacing: Spacing.xs)], spacing: Spacing.xs) {
                        ForEach(TopicSymbolCatalog.entries) { entry in
                            symbolButton(entry)
                        }
                    }
                }
                Section {
                    HStack {
                        TextField("Emoji", text: $emoji, prompt: Text("Type or paste an emoji"))
                            .focused($isEmojiFocused)
                            .onSubmit(useEmoji)
                            .accessibilityIdentifier(AccessibilityID.SymbolPicker.emoji)
                        #if os(macOS)
                        Button("Emoji & Symbols") {
                            isEmojiFocused = true
                            NSApp.orderFrontCharacterPalette(nil)
                        }
                        #endif
                        Button("Use Emoji", action: useEmoji)
                            .disabled(TopicSymbol.emoji(TopicSymbol.normalized(emoji)) == nil)
                    }
                } header: {
                    Text("Emoji")
                }
                Section {
                    Button("Remove Symbol", role: .destructive) { choose(nil) }
                        .disabled(session.symbolCoverage(targets) == .all(nil))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Choose Symbol"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: Metrics.symbolPickerWidth, minHeight: Metrics.symbolPickerHeight)
        #endif
    }

    private func symbolButton(_ entry: TopicSymbolCatalog.Entry) -> some View {
        let isCurrent = session.symbolCoverage(targets) == .all(entry.name)
        return Button { choose(entry.name) } label: {
            Image(systemName: entry.name)
                .font(.title3)
                .frame(minWidth: Metrics.minimumHitTarget, minHeight: Metrics.minimumHitTarget)
                .background {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.accent, lineWidth: CanvasMetrics.mainStrokeWidthHighContrast)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(entry.title))
        .accessibilityLabel(Text(entry.title))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func useEmoji() {
        guard TopicSymbol.emoji(TopicSymbol.normalized(emoji)) != nil else { return }
        choose(emoji)
    }

    private func choose(_ symbol: String?) {
        session.setSymbol(symbol, on: targets)
        dismiss()
    }
}

/// Shows the symbol picker for `EditorSession.symbolPickerTargets`.
struct TopicSymbolPickerPresenter: ViewModifier {
    @Bindable var session: EditorSession

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { session.symbolPickerTargets != nil },
            set: { if !$0 { session.symbolPickerTargets = nil } }
        )) {
            if let targets = session.symbolPickerTargets {
                TopicSymbolPicker(session: session, targets: targets)
            }
        }
    }
}
