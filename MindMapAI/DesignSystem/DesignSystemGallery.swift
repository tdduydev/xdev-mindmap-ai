#if DEBUG
import SwiftUI

/// Every token and topic state, light and dark side by side, for review and
/// screenshots. Debug builds only; the text is verbatim so none of it reaches
/// the string catalog.
struct DesignSystemGallery: View {
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: Spacing.xxl) {
                GalleryColumn()
                    .environment(\.colorScheme, .light)
                GalleryColumn()
                    .environment(\.colorScheme, .dark)
            }
            .padding(Spacing.xl)
        }
    }
}

private enum GalleryLayout {
    static let columnWidth: CGFloat = 520
    static let swatch: CGFloat = 28
    static let branchSwatch: CGFloat = 44
}

private struct GalleryColumn: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let theme = MapTheme.standard

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text(verbatim: colorScheme == .dark ? "Dark" : "Light")
                .font(Typography.Content.display.font)
                .foregroundStyle(Palette.topicText)

            section("Semantic colours") {
                ForEach(semanticColors, id: \.name) { item in
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(item.value)
                            .frame(width: GalleryLayout.swatch, height: GalleryLayout.swatch)
                        Text(verbatim: item.name)
                            .font(Typography.rowDetail)
                            .foregroundStyle(Palette.topicText)
                    }
                }
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(Palette.ai(colorScheme: colorScheme, contrast: contrast, reduceTransparency: reduceTransparency))
            }

            section("Branch palette") {
                HStack(spacing: Spacing.sm) {
                    ForEach(0..<theme.branches.colors.count, id: \.self) { index in
                        let colors = theme.branch(index, in: variant)
                        VStack(spacing: Spacing.xxs) {
                            Rectangle().fill(colors.line.color)
                            Rectangle().fill(colors.mainFill.color)
                            Rectangle().fill(colors.subFill.color)
                        }
                        .frame(width: GalleryLayout.branchSwatch, height: GalleryLayout.branchSwatch * 2)
                    }
                }
            }

            section("Typography") {
                ForEach(contentStyles, id: \.name) { item in
                    Text(verbatim: "\(item.name): Chủ đề tiếng Việt 123")
                        .font(item.value.font)
                        .foregroundStyle(Palette.topicText)
                }
                ForEach(BrandFont.allCases, id: \.self) { font in
                    Text(verbatim: "\(font.postScriptName): \(BrandFont.registered.contains(font) ? "loaded" : "MISSING")")
                        .font(Typography.rowDetail)
                        .foregroundStyle(BrandFont.registered.contains(font) ? Palette.success : Palette.danger)
                }
            }

            section("Topics") {
                HStack(alignment: .center, spacing: Spacing.lg) {
                    TopicSample(title: "Central", style: style(level: 0))
                    TopicSample(title: "Main", style: style(level: 1))
                    TopicSample(title: "Sub", style: style(level: 2))
                    TopicSample(title: "Deep", style: style(level: 3))
                }
                HStack(alignment: .center, spacing: Spacing.lg) {
                    TopicSample(title: "Hover", style: style(level: 1, branch: 1), state: .hover)
                    TopicSample(title: "Selected", style: style(level: 1, branch: 2), state: .selected)
                    TopicSample(title: "Has note", style: style(level: 2, branch: 3), state: .hasNote)
                    TopicSample(title: "Collapsed", style: style(level: 1, branch: 4), state: .collapsed(12))
                }
                HStack(alignment: .center, spacing: Spacing.lg) {
                    TopicSample(title: "Search match", style: style(level: 2, branch: 5), state: .searchMatch)
                    TopicSample(title: "AI suggestion", style: style(level: 2), state: .suggestion)
                    TopicSample(title: "Dragged", style: style(level: 1), state: .dragged)
                }
            }
        }
        .padding(Spacing.xl)
        .frame(width: GalleryLayout.columnWidth, alignment: .leading)
        .background(Palette.canvasBackground)
    }

    private var variant: ColorVariant { ColorVariant(colorScheme: colorScheme, contrast: contrast) }

    private func style(level: Int, branch: Int = 0) -> TopicStyle {
        TopicStyle.resolve(level: level, branch: branch, theme: theme, colorScheme: colorScheme, contrast: contrast)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: title)
                .font(Typography.rowTitle)
                .foregroundStyle(Palette.topicTextSecondary)
            content()
        }
    }

    private struct Named<Value> {
        let name: String
        let value: Value
    }

    private var semanticColors: [Named<Color>] {
        [
            Named(name: "accent / selectionRing", value: Palette.accent),
            Named(name: "canvasBackground", value: Palette.canvasBackground),
            Named(name: "topicText", value: Palette.topicText),
            Named(name: "topicTextSecondary", value: Palette.topicTextSecondary),
            Named(name: "centralFill", value: Palette.centralFill),
            Named(name: "centralText", value: Palette.centralText),
            Named(name: "crossLink", value: Palette.crossLink),
            Named(name: "searchMatchFill", value: Palette.searchMatchFill),
            Named(name: "searchMatchBorder", value: Palette.searchMatchBorder),
            Named(name: "favorite", value: Palette.favorite),
            Named(name: "warningFill", value: Palette.warningFill),
            Named(name: "warningText", value: Palette.warningText),
            Named(name: "danger", value: Palette.danger),
            Named(name: "success", value: Palette.success),
        ]
    }

    private var contentStyles: [Named<ContentStyle>] {
        [
            Named(name: "central", value: Typography.Content.central),
            Named(name: "main", value: Typography.Content.main),
            Named(name: "sub", value: Typography.Content.sub),
            Named(name: "deep", value: Typography.Content.deep),
            Named(name: "outlineTopic", value: Typography.Content.outlineTopic),
            Named(name: "note", value: Typography.Content.note),
            Named(name: "badge", value: Typography.Content.badge),
            Named(name: "display", value: Typography.Content.display),
        ]
    }
}

/// A static drawing of one topic, enough to review the tokens. The real topic
/// view comes with the canvas (MM-3).
private struct TopicSample: View {
    enum SampleState: Equatable {
        case rest, hover, selected, hasNote, collapsed(Int), searchMatch, suggestion, dragged
    }

    let title: String
    let style: TopicStyle
    var state: SampleState = .rest

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.box.cornerRadius)
        HStack(spacing: Spacing.xs) {
            if state == .suggestion {
                Image(systemName: "sparkles").foregroundStyle(aiStyle)
            }
            Text(verbatim: title)
                .font(style.text.font)
                .foregroundStyle(state == .suggestion ? style.secondaryTextColor.color : style.textColor.color)
                .padding(.horizontal, state == .searchMatch ? Spacing.xxs : 0)
                .background {
                    if state == .searchMatch {
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(Palette.searchMatchFill)
                            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.searchMatchBorder))
                    }
                }
            if state == .hasNote {
                Image(systemName: "note.text")
                    .font(.system(size: CanvasMetrics.noteSymbolSize))
                    .foregroundStyle(style.secondaryTextColor.color)
            }
        }
        .padding(.horizontal, style.box.horizontalPadding)
        .padding(.vertical, style.box.verticalPadding)
        .frame(minWidth: style.box.minimumWidth, maxWidth: style.box.maximumWidth)
        .background(fill, in: shape)
        .overlay {
            if state == .suggestion {
                shape.strokeBorder(aiStyle, style: StrokeStyle(lineWidth: CanvasMetrics.suggestionEdgeWidth, dash: CanvasMetrics.suggestionDash))
            } else if let stroke = style.stroke {
                shape.strokeBorder(stroke.color, lineWidth: style.strokeWidth)
            }
        }
        .padding(CanvasMetrics.selectionRingGap)
        .overlay {
            if state == .selected {
                RoundedRectangle(cornerRadius: style.box.cornerRadius + CanvasMetrics.selectionRingGap)
                    .strokeBorder(Palette.selectionRing, lineWidth: style.selectionRingWidth)
            }
        }
        .overlay(alignment: .trailing) {
            if case .collapsed(let count) = state {
                Text(verbatim: "\(count)")
                    .font(Typography.Content.badge.font)
                    .foregroundStyle(style.badgeText.color)
                    .padding(.horizontal, Spacing.xs)
                    .frame(minHeight: CanvasMetrics.collapseBadgeHeight)
                    .background(style.badgeFill.color, in: Capsule())
                    .offset(x: CanvasMetrics.collapseBadgeHeight)
            }
        }
        .modifier(DraggedLook(isDragged: state == .dragged))
    }

    private var fill: Color {
        switch state {
        case .hover: style.hoverFill.color
        case .suggestion: Palette.canvasBackground
        default: style.fill.color
        }
    }

    private var aiStyle: AnyShapeStyle {
        Palette.ai(colorScheme: colorScheme, contrast: contrast, reduceTransparency: reduceTransparency)
    }
}

private struct DraggedLook: ViewModifier {
    let isDragged: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isDragged {
            content.dragElevation()
        } else {
            content
        }
    }
}

#Preview("Design system") {
    DesignSystemGallery()
}
#endif
