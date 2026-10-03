import CoreGraphics
import Foundation
import ImageIO
import MindMapDomain
import MindMapGraph
import MindMapLayout
import SwiftUI
import UniformTypeIdentifiers

/// The whole map laid out the way the canvas lays it out, ready to draw as a
/// PNG or a PDF (FR-IO-04, FR-IO-05).
///
/// It has its own layout rather than the open canvas's scene: that scene holds
/// AI suggestions while they are shown, and on iOS it follows Dynamic Type. An
/// export is the map itself at design sizes, so it looks the same wherever it
/// is made. Collapsed branches stay collapsed, as on screen.
struct MapPicture {
    let scene: CanvasScene
    let theme: MapTheme
    let specs: TopicTextSpecs
    let imageData: [ImageID: Data]

    /// The map's bounds with room around it, in canvas points.
    var frame: CGRect {
        let padding = CanvasMetrics.exportPadding
        return scene.bounds.insetBy(dx: -padding, dy: -padding)
    }

    var size: CGSize { frame.size }

    /// Measures and lays out off the main actor, like a canvas pass.
    ///
    /// Coloured topics always carry their colour's shape: the file is for
    /// other people, who may need it whatever this device's settings are.
    static func make(_ graph: GraphState, imageData: [ImageID: Data] = [:]) async -> MapPicture {
        let specs = TopicTextSpecs.designSizes(showsColorShapes: true)
        let pass = CanvasLayoutPass(
            graph: graph,
            previous: nil,
            measures: [:],
            changed: [],
            specs: specs,
            options: CanvasModel.layoutOptions
        )
        let output = await pass.runInBackground()
        return MapPicture(scene: output.scene, theme: MapTheme(graph.map.theme), specs: specs, imageData: imageData)
    }
}

/// Draws a `MapPicture` into PNG and PDF data. Pictures are SwiftUI views
/// rendered by `ImageRenderer`, so they come out as the canvas draws them,
/// and as vectors and text in a PDF.
enum MapRenderer {
    enum Failure: Error {
        case couldNotDraw
    }

    /// - Parameter scale: Pixels per point. Lowered for a map too large for an
    ///   image other apps can open (`CanvasMetrics.exportMaximumPixels`).
    static func png(_ picture: MapPicture, scale: CGFloat, background: ExportBackground, colorScheme: ColorScheme) throws -> Data {
        let renderer = ImageRenderer(content: content(picture, background: background, colorScheme: colorScheme))
        renderer.scale = fittedScale(scale, for: picture.size)
        guard let image = renderer.cgImage else { throw Failure.couldNotDraw }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.couldNotDraw
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.couldNotDraw }
        return data as Data
    }

    static func pdf(_ picture: MapPicture, layout: PDFPageLayout, background: ExportBackground, colorScheme: ColorScheme, title: String) throws -> Data {
        let renderer = ImageRenderer(content: content(picture, background: background, colorScheme: colorScheme))
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: layout.pageSize)
        // The title is document metadata the user chose to export, like the map itself.
        let info = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "MindMap AI"] as CFDictionary
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info) else {
            throw Failure.couldNotDraw
        }
        var drew = false
        renderer.render { size, draw in
            drew = true
            for page in layout.pages {
                context.beginPDFPage(nil)
                context.saveGState()
                context.clip(to: layout.clip(for: page))
                context.concatenate(layout.transform(for: page, pictureHeight: size.height))
                draw(context)
                context.restoreGState()
                context.endPDFPage()
            }
        }
        context.closePDF()
        guard drew else { throw Failure.couldNotDraw }
        return data as Data
    }

    /// The scale, lowered so neither side passes the pixel limit.
    static func fittedScale(_ scale: CGFloat, for size: CGSize) -> CGFloat {
        let longest = max(size.width, size.height, 1)
        return min(scale, CanvasMetrics.exportMaximumPixels / longest)
    }

    private static func content(_ picture: MapPicture, background: ExportBackground, colorScheme: ColorScheme) -> some View {
        // White paper takes the light colours, which are made for a light ground.
        let scheme = background == .white ? .light : colorScheme
        return MapPictureView(picture: picture, background: background, colorScheme: scheme)
            .environment(\.colorScheme, scheme)
    }
}

/// Every topic and edge of a picture at actual size. Exports use the standard
/// contrast variant: the file is for other people, whose settings may differ.
struct MapPictureView: View {
    let picture: MapPicture
    let background: ExportBackground
    let colorScheme: ColorScheme

    var body: some View {
        let frame = picture.frame
        let styles = TopicStyleCache(theme: picture.theme, colorScheme: colorScheme)
        let drawing = CanvasDrawing.make(
            scene: picture.scene,
            rect: frame,
            shapes: nil,
            selection: nil,
            style: styles.style(for:)
        )
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(background == .white ? Color.white : Palette.canvasBackground)
            EdgeLayer(
                drawing: drawing,
                viewport: CanvasViewport(scale: 1, offset: CGPoint(x: -frame.minX, y: -frame.minY), size: frame.size),
                aiStyle: AnyShapeStyle(Palette.crossLink)
            )
            ForEach(picture.scene.topics) { topic in
                StaticTopicCard(
                    topic: topic,
                    style: styles.style(for: topic),
                    spec: picture.specs.spec(level: topic.level),
                    chipSpec: picture.specs.chip,
                    markSpec: picture.specs.mark,
                    imageData: topic.topicImage.flatMap { picture.imageData[$0.id] },
                    variant: ColorVariant(colorScheme: colorScheme, contrast: .standard)
                )
                    .position(x: topic.frame.midX - frame.minX, y: topic.frame.midY - frame.minY)
            }
        }
        .frame(width: frame.width, height: frame.height)
    }
}

/// A topic card at rest: fill, outline, title, tag chips and collapse badge,
/// as `TopicView` draws them, without selection, hover or editing.
private struct StaticTopicCard: View {
    let topic: CanvasTopic
    let style: TopicStyle
    let spec: TopicTextSpec
    let chipSpec: TopicChipSpec
    let markSpec: TopicMarkSpec
    let imageData: Data?
    let variant: ColorVariant

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.box.cornerRadius, style: .continuous)
        ZStack {
            shape.fill(style.fill.color)
            if let stroke = style.stroke {
                shape.strokeBorder(stroke.color, lineWidth: style.strokeWidth)
            }
            VStack(spacing: topic.topicImage == nil ? 0 : CanvasMetrics.imageGap) {
                if let image = topic.topicImage {
                    TopicImageView(image: image, level: topic.level, spec: spec, data: imageData)
                }
                TopicTitleWithChips(chips: topic.chips, spec: chipSpec) {
                    TopicTitleRow(
                        marks: topic.marks, markSpec: markSpec, spec: spec,
                        width: max(topic.frame.width - 2 * spec.horizontalPadding, 0),
                        textColor: style.textColor.color, shapeColor: style.edgeColor.color
                    ) { width, hugsText in
                        TopicTitleText(
                            title: topic.title,
                            spec: spec,
                            color: style.textColor.color,
                            placeholderColor: style.secondaryTextColor.color,
                            width: width,
                            hugsText: hugsText
                        )
                    }
                } chip: { chip in
                    TopicChipLabel(chip: chip, spec: chipSpec, variant: variant)
                }
            }
        }
        .frame(width: topic.frame.width, height: topic.frame.height)
        .overlay(alignment: .bottomTrailing) {
            if let link = topic.link {
                TopicLinkSymbol(link: link)
                    .font(.system(size: CanvasMetrics.linkSymbolSize))
                    .foregroundStyle(style.secondaryTextColor.color)
                    .padding(Spacing.xxs)
                    .background(Palette.canvasBackground, in: Circle())
                    .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
                    .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] }
            }
        }
        .overlay(alignment: topic.side == .left ? .leading : .trailing) {
            if topic.hiddenDescendantCount > 0 {
                CollapseBadgeLabel(count: topic.hiddenDescendantCount, style: style)
                    .modifier(CollapseBadgePlacement())
            }
        }
    }
}

/// Styles resolved once per level and branch, as `CanvasModel` keeps them.
private final class TopicStyleCache {
    private let theme: MapTheme
    private let colorScheme: ColorScheme
    private var styles: [Key: TopicStyle] = [:]

    private struct Key: Hashable {
        let level: Int
        let branch: Int
        let color: TopicColor?
    }

    init(theme: MapTheme, colorScheme: ColorScheme) {
        self.theme = theme
        self.colorScheme = colorScheme
    }

    func style(for topic: CanvasTopic) -> TopicStyle {
        // Levels past 3 look like level 3, as on the canvas.
        let key = Key(level: min(topic.level, 3), branch: topic.branch, color: topic.color)
        if let style = styles[key] { return style }
        let style = TopicStyle.resolve(
            level: key.level, branch: key.branch, color: key.color, theme: theme, colorScheme: colorScheme, contrast: .standard
        )
        styles[key] = style
        return style
    }
}
