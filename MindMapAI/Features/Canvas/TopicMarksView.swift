import MindMapDomain
import SwiftUI

/// A topic's title with its colour shape and symbol before it (MM-32), at the
/// widths `TopicMeasurer` reserved. Shared by the canvas, the title editor
/// and export, so the three line up.
struct TopicTitleRow<Title: View>: View {
    let marks: TopicMark
    let markSpec: TopicMarkSpec?
    let spec: TopicTextSpec
    /// The width inside the card's padding.
    let width: CGFloat
    let textColor: Color
    /// The topic's line colour: the shape shows the colour as well as its form.
    let shapeColor: Color
    /// Gets the width left for the title.
    @ViewBuilder let title: (_ width: CGFloat, _ hugsText: Bool) -> Title

    var body: some View {
        if let markSpec, !marks.isEmpty {
            let markWidth = markSpec.width(of: marks, pointSize: spec.pointSize)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                TopicMarksView(marks: marks, markSpec: markSpec, spec: spec, textColor: textColor, shapeColor: shapeColor)
                // Hugs its text, so a short title sits beside its marks in the
                // middle of the card rather than across a gap from them.
                title(max(width - markWidth, 0), true)
            }
        } else {
            title(width, false)
        }
    }
}

/// The marks alone. Drawn as text so they sit on the title's first baseline.
struct TopicMarksView: View {
    let marks: TopicMark
    let markSpec: TopicMarkSpec
    let spec: TopicTextSpec
    let textColor: Color
    let shapeColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let shape = marks.shape {
                Text(Image(systemName: shape.shapeSymbol))
                    .font(.system(size: markSpec.shapeSize))
                    .foregroundStyle(shapeColor)
                    .frame(width: markSpec.shapeSize + markSpec.gap, alignment: .leading)
            }
            if let symbol = marks.symbol {
                symbolText(symbol)
                    .font(.custom(spec.postScriptName, fixedSize: spec.pointSize))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: markSpec.symbolWidth(pointSize: spec.pointSize), alignment: .center)
                    .padding(.trailing, markSpec.gap)
            }
        }
        // The topic element reads colour and symbol as custom content.
        .accessibilityHidden(true)
    }

    private func symbolText(_ symbol: TopicMark.Symbol) -> Text {
        switch symbol {
        case .system(let name): Text(Image(systemName: name))
        case .emoji(let emoji): Text(verbatim: emoji)
        }
    }
}

/// The colour and symbol in VoiceOver's "more content", as tags are (FR-ORG-24).
struct TopicStyleCustomContent: ViewModifier {
    let color: TopicColor?
    let symbol: TopicMark.Symbol?

    func body(content: Content) -> some View {
        content
            .modifier(OptionalCustomContent(label: Text("Color"), value: color?.title))
            .modifier(OptionalCustomContent(label: Text("Symbol"), value: symbol.map(TopicSymbolCatalog.spokenName(of:))))
    }
}

/// Custom content only when there is a value, so VoiceOver lists no empty row.
private struct OptionalCustomContent: ViewModifier {
    let label: Text
    let value: String?

    func body(content: Content) -> some View {
        if let value {
            content.accessibilityCustomContent(label, Text(verbatim: value))
        } else {
            content
        }
    }
}
