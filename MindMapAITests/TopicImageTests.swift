import CoreGraphics
import Foundation
import ImageIO
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import SwiftUI
import Testing
import UniformTypeIdentifiers

@Suite("Topic images")
struct TopicImageTests {
    private struct OpenFailed: Error {}
    private func sourceImage() throws -> Data {
        let context = try #require(CGContext(data: nil, width: 8, height: 8,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func addResizeDescribeRemoveUndoRedoAndReopen() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let graph = GraphState.newMap(title: "Pictures")
        try await repository.create(graph)
        guard case .ready(let session) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        let root = try #require(session.rootID)
        let manager = UndoManager()
        manager.groupsByEvent = false
        session.undoManager = manager

        manager.beginUndoGrouping()
        await session.addImage(try sourceImage(), to: root)
        manager.endUndoGrouping()
        let first = try #require(session.selectedImage)
        let bytes = try #require(session.engine.imageData[first.id])
        #expect(!bytes.isEmpty)

        manager.beginUndoGrouping()
        session.setImageSize(CanvasMetrics.imageWidthLarge, for: first.id)
        session.setImageDescription("Red square", for: first.id)
        manager.endUndoGrouping()
        #expect(session.selectedImage?.altText == "Red square")
        #expect(session.selectedImage?.displayWidth == CanvasMetrics.imageWidthLarge)

        await session.flush()
        guard case .ready(let reopened) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        let stored = try #require(reopened.selectedImage)
        #expect(await reopened.imageBytes(for: stored) == bytes)

        manager.beginUndoGrouping()
        await session.addImage(try sourceImage(), to: root)
        manager.endUndoGrouping()
        let replacement = try #require(session.selectedImage)
        #expect(replacement.id != first.id)
        manager.undo()
        #expect(session.selectedImage?.id == first.id)
        #expect(session.engine.imageData[first.id] == bytes)
        manager.redo()
        #expect(session.selectedImage?.id == replacement.id)
        manager.undo()

        manager.beginUndoGrouping()
        await session.removeImage(from: root)
        manager.endUndoGrouping()
        #expect(session.selectedImage == nil)
        manager.undo()
        #expect(session.selectedImage?.id == first.id)
        #expect(session.engine.imageData[first.id] == bytes)
        manager.redo()
        #expect(session.selectedImage == nil)
    }

    @Test func pngDrawsTheStoredPictureAndMarkdownOmitsIt() async throws {
        let graph = GraphState.newMap(title: "Picture")
        let root = try #require(graph.map.rootNodeID)
        var engine = try GraphEngine(state: graph)
        let bytes = try sourceImage()
        let image = MindImage(mapID: graph.map.id, nodeID: root, data: bytes,
            uniformType: UTType.png.identifier, pixelWidth: 8, pixelHeight: 8)
        try engine.execute(SetNodeImageCommand(nodeID: root, image: image))
        let picture = await MapPicture.make(engine.state, imageData: [image.id: bytes])
        let topic = try #require(picture.scene.topics.first)
        var options = ExportOptions()
        options.format = .png
        options.imageScale = .standard
        let png = try await MapExporter.data(for: engine.state, options: options,
            colorScheme: .light, imageData: [image.id: bytes])
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let output = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let x = Int(topic.frame.midX - picture.frame.minX)
        let y = Int(topic.frame.midY - picture.frame.minY - CanvasMetrics.imageWidthMedium / 4)
        let pixel = try #require(CGContext(data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        pixel.draw(output, in: CGRect(x: -x, y: -(output.height - 1 - y), width: output.width, height: output.height))
        let channels = try #require(pixel.data?.assumingMemoryBound(to: UInt8.self))
        #expect(channels[0] > 200 && channels[1] < 100 && channels[2] < 100)

        options.format = .markdown
        let markdown = try await MapExporter.data(for: engine.state, options: options, colorScheme: .light)
        #expect(String(decoding: markdown, as: UTF8.self) == "# Picture\n")
    }
}
