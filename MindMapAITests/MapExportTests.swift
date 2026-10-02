import CoreGraphics
import Foundation
import ImageIO
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import PDFKit
import SwiftUI
import Testing

/// File ▸ Export…: text through `MindMapInterchange`, pictures drawn from the
/// canvas's layout (FR-IO-03, FR-IO-04, FR-IO-05).
@Suite("Map export")
struct MapExportTests {
    private func graph(_ title: String = "Trip", children: [String] = ["Flights", "Hotels"]) throws -> GraphState {
        let graph = GraphState.newMap(title: title)
        let rootID = try #require(graph.map.rootNodeID)
        var engine = try GraphEngine(state: graph)
        for child in children {
            try engine.execute(AddNodeCommand(.child(of: rootID), title: child))
        }
        return engine.state
    }

    private func options(_ format: ExportFormat) -> ExportOptions {
        var options = ExportOptions()
        options.format = format
        return options
    }

    // MARK: Text

    @Test func markdownExportsTheWholeMap() async throws {
        let data = try await MapExporter.data(for: try graph(), options: options(.markdown), colorScheme: .light)

        #expect(String(decoding: data, as: UTF8.self) == "# Trip\n\n## Flights\n\n## Hotels\n")
    }

    @Test func textExportsOneBranchWithoutNotes() async throws {
        var state = try graph()
        let rootID = try #require(state.map.rootNodeID)
        let flights = try #require(state.children(of: rootID).first?.id)
        var engine = try GraphEngine(state: state)
        try engine.execute(AddNodeCommand(.child(of: flights), title: "Hanoi"))
        try engine.execute(UpdateNodeCommand(nodeID: flights, .note("Book early")))
        state = engine.state
        var options = options(.plainText)
        options.branch = flights
        options.includeNotes = false

        let data = try await MapExporter.data(for: state, options: options, colorScheme: .light)

        #expect(String(decoding: data, as: UTF8.self) == "Flights\n\tHanoi\n")
    }

    @Test func fileNamesAreSafe() {
        #expect(MapExporter.fileName(for: "Q1/Q2: plan") == "Q1-Q2- plan")
        #expect(MapExporter.fileName(for: "   ") == String(localized: "Untitled Map"))
        #expect(MapExporter.fileName(for: "Thiết kế") == "Thiết kế")
    }

    // MARK: PNG

    @Test func pngIsTheMapAtTheChosenScale() async throws {
        let state = try graph()
        let picture = await MapPicture.make(state)
        var options = options(.png)
        options.imageScale = .double

        let data = try await MapExporter.data(for: state, options: options, colorScheme: .light)

        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(abs(CGFloat(image.width) - picture.size.width * 2) <= 1)
        #expect(abs(CGFloat(image.height) - picture.size.height * 2) <= 1)
    }

    @Test func pictureHasRoomAroundEveryTopic() async throws {
        let picture = await MapPicture.make(try graph())

        #expect(picture.scene.topics.count == 3)
        for topic in picture.scene.topics {
            #expect(picture.frame.insetBy(dx: CanvasMetrics.exportPadding - 1, dy: CanvasMetrics.exportPadding - 1).contains(topic.frame))
        }
    }

    @Test func whiteBackgroundIsWhiteInDarkMode() async throws {
        var options = options(.png)
        options.imageScale = .standard
        options.background = .white

        let data = try await MapExporter.data(for: try graph(), options: options, colorScheme: .dark)

        let corner = try #require(pixel(atX: 1, y: 1, of: data))
        #expect(corner == [255, 255, 255])
    }

    @Test func appearanceBackgroundFollowsDarkMode() async throws {
        var options = options(.png)
        options.imageScale = .standard
        options.background = .appearance

        let light = try #require(pixel(atX: 1, y: 1, of: try await MapExporter.data(for: try graph(), options: options, colorScheme: .light)))
        let dark = try #require(pixel(atX: 1, y: 1, of: try await MapExporter.data(for: try graph(), options: options, colorScheme: .dark)))

        #expect(light.reduce(0, +) > dark.reduce(0, +))
    }

    @Test func aHugeMapIsScaledDownToAnImageOthersCanOpen() {
        let size = CGSize(width: 12_000, height: 3_000)

        #expect(MapRenderer.fittedScale(3, for: size) * size.width <= CanvasMetrics.exportMaximumPixels)
        #expect(MapRenderer.fittedScale(2, for: CGSize(width: 800, height: 600)) == 2)
    }

    // MARK: PDF

    @Test func pdfFitsTheMapOnOnePageAsText() async throws {
        var options = options(.pdf)
        options.pageMode = .singlePage
        options.paper = .a4

        let data = try await MapExporter.data(for: try graph("Thiết kế"), options: options, colorScheme: .light)

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        // Text, not pixels: the titles can be searched (FR-IO-05, vector).
        let text = try #require(document.string)
        #expect(text.contains("Thiết kế"))
        #expect(text.contains("Flights"))
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Thiết kế")
    }

    @Test func pdfSplitsALargeMapOverPages() async throws {
        let state = try graph(children: (1...120).map { "Topic \($0)" })
        var options = options(.pdf)
        options.pageMode = .multiplePages
        options.paper = .letter

        let data = try await MapExporter.data(for: state, options: options, colorScheme: .light)

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount > 1)
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        #expect(text.contains("Topic 1"))
        #expect(text.contains("Topic 120"))
    }

    // MARK: Pro

    @Test func onlyHighResolutionAndSeveralPagesNeedPro() {
        var options = ExportOptions()
        options.format = .markdown
        #expect(options.requiredFeature == nil)
        options.format = .png
        options.imageScale = .standard
        #expect(options.requiredFeature == nil)
        options.imageScale = .triple
        #expect(options.requiredFeature == .highResolutionImage)
        options.format = .pdf
        options.pageMode = .singlePage
        #expect(options.requiredFeature == nil)
        options.pageMode = .multiplePages
        #expect(options.requiredFeature == .multiPagePDF)
    }

    /// The red, green and blue of one pixel of a PNG.
    private func pixel(atX x: Int, y: Int, of data: Data) -> [Int]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        // Draw so the wanted pixel lands on the 1×1 context (origin bottom-left).
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        return [Int(bytes[0]), Int(bytes[1]), Int(bytes[2])]
    }
}

@Suite("PDF page layout")
struct PDFPageLayoutTests {
    let a4 = PaperSize.a4.size
    let margin: CGFloat = 36

    @Test func aSmallMapStaysAtActualSizeInTheMiddle() {
        let layout = PDFPageLayout(content: CGSize(width: 200, height: 100), paper: a4, mode: .singlePage, margin: margin)

        #expect(layout.scale == 1)
        #expect(layout.pages.count == 1)
        // Wider than tall: landscape.
        #expect(layout.pageSize.width > layout.pageSize.height)
        let destination = layout.pages[0].destination
        #expect(abs(destination.midX - layout.pageSize.width / 2) < 0.001)
        #expect(abs(destination.midY - layout.pageSize.height / 2) < 0.001)
    }

    @Test func aLargeMapShrinksToFitInsideTheMargins() {
        let layout = PDFPageLayout(content: CGSize(width: 900, height: 3_000), paper: a4, mode: .singlePage, margin: margin)

        #expect(layout.pageSize == a4)
        #expect(layout.scale < 1)
        let printable = CGRect(origin: .zero, size: layout.pageSize).insetBy(dx: margin, dy: margin)
        #expect(printable.insetBy(dx: -0.001, dy: -0.001).contains(layout.pages[0].destination))
    }

    @Test func pagesTileTheMapWithoutGapsOrOverlap() {
        let content = CGSize(width: 1_700, height: 2_300)
        let layout = PDFPageLayout(content: content, paper: a4, mode: .multiplePages, margin: margin)

        #expect(layout.scale == 1)
        #expect(layout.pages.count > 1)
        let area = layout.pages.reduce(0) { $0 + $1.source.width * $1.source.height }
        #expect(abs(area - content.width * content.height) < 1)
        for (index, page) in layout.pages.enumerated() {
            for other in layout.pages[(index + 1)...] {
                let overlap = page.source.intersection(other.source)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.001)
            }
            // Each piece is drawn at actual size inside the margins.
            #expect(page.destination.size == page.source.size)
            #expect(page.destination.minX >= margin - 0.001 && page.destination.maxX <= layout.pageSize.width - margin + 0.001)
            #expect(page.destination.minY >= margin - 0.001 && page.destination.maxY <= layout.pageSize.height - margin + 0.001)
        }
    }

    @Test func pagesReadLeftToRightThenDown() {
        let layout = PDFPageLayout(content: CGSize(width: 1_500, height: 1_500), paper: a4, mode: .multiplePages, margin: margin)

        let origins = layout.pages.map(\.source.origin)
        let sorted = origins.sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }
        #expect(origins == sorted)
    }

    @Test func aMapThatFitsExactlyIsOnePage() {
        let printable = CGSize(width: a4.width - 2 * margin, height: a4.height - 2 * margin)

        let layout = PDFPageLayout(content: printable, paper: a4, mode: .multiplePages, margin: margin)

        #expect(layout.pages.count == 1)
    }

    /// A picture point lands where the page's top-left based destination says,
    /// once flipped into PDF's bottom-left coordinates.
    @Test func transformPlacesThePictureOnThePage() {
        let content = CGSize(width: 1_200, height: 900)
        let layout = PDFPageLayout(content: content, paper: a4, mode: .multiplePages, margin: margin)
        let page = layout.pages[0]
        let transform = layout.transform(for: page, pictureHeight: content.height)

        // The source's top-left corner, as the renderer draws it (y up from the bottom).
        let drawn = CGPoint(x: page.source.minX, y: content.height - page.source.minY)
        let onPage = drawn.applying(transform)

        #expect(abs(onPage.x - page.destination.minX) < 0.001)
        #expect(abs(onPage.y - (layout.pageSize.height - page.destination.minY)) < 0.001)
        #expect(layout.clip(for: page).maxY == layout.pageSize.height - page.destination.minY)
    }
}
