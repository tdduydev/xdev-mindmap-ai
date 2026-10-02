import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Image commands")
struct ImageCommandTests {
    static let bytes = Data(repeating: 7, count: 64)
    static let otherBytes = Data(repeating: 9, count: 32)

    static func fixture() throws -> GraphFixture {
        try GraphFixture("""
        Root
          A
            A1
          B
        """)
    }

    static func image(_ fixture: GraphFixture, data: Data? = bytes) -> MindImage {
        MindImage(mapID: fixture.state.map.id, nodeID: NodeID(), data: data, pixelWidth: 400, pixelHeight: 300, byteCount: 1)
    }

    @Test func addImageUndoRedo() throws {
        var fixture = try Self.fixture()
        let a = fixture["A"]
        let image = Self.image(fixture)

        let added = try fixture.engine.execute(SetNodeImageCommand(nodeID: a, image: image), named: "Add Image")
        let stored = try #require(fixture.state.image(of: a))
        #expect(stored.id == image.id)
        #expect(stored.nodeID == a)
        #expect(stored.data == nil)
        // The command sets the count from the bytes, whatever the caller said.
        #expect(stored.byteCount == Self.bytes.count)
        #expect(added.savedImages.map(\.data) == [Self.bytes])

        fixture.engine.undo()
        #expect(fixture.state.image(of: a) == nil)
        let redoneStep = fixture.engine.redo()
        let redone = try #require(redoneStep)
        #expect(redone.savedImages.map(\.data) == [Self.bytes])
        #expect(fixture.state.image(of: a)?.id == image.id)
    }

    @Test func anImageWithoutBytesIsRefused() throws {
        var fixture = try Self.fixture()
        let image = Self.image(fixture, data: nil)
        #expect(throws: GraphError.imageHasNoData(image.id)) {
            try fixture.engine.execute(SetNodeImageCommand(nodeID: fixture["A"], image: image))
        }
        #expect(fixture.state.images.isEmpty)
    }

    /// Undo of Remove Image after loading puts the record back with its file.
    @Test func removeImageUndoRedoKeepsTheBytes() throws {
        var fixture = try Self.fixture()
        let a = fixture["A"]
        let image = Self.image(fixture)
        try fixture.engine.execute(SetNodeImageCommand(nodeID: a, image: image))
        // As the editor does after opening a map: only loaded bytes are known.
        fixture.engine.imageData = [image.id: Self.bytes]

        let removed = try fixture.engine.execute(SetNodeImageCommand(nodeID: a, image: nil), named: "Remove Image")
        #expect(removed.deletedImageIDs == [image.id])
        #expect(fixture.state.images.isEmpty)

        let undoneStep = fixture.engine.undo()
        let undone = try #require(undoneStep)
        #expect(undone.savedImages.map(\.data) == [Self.bytes])
        #expect(fixture.state.image(of: a)?.id == image.id)
        let redoneStep = fixture.engine.redo()
        let redone = try #require(redoneStep)
        #expect(redone.deletedImageIDs == [image.id])
        #expect(fixture.state.images.isEmpty)
    }

    /// An image added in this session needs no loading: the engine kept its bytes.
    @Test func removingAnImageAddedThisSessionCanBeUndoneWithoutLoading() throws {
        var fixture = try Self.fixture()
        let a = fixture["A"]
        let image = Self.image(fixture)
        try fixture.engine.execute(SetNodeImageCommand(nodeID: a, image: image))
        try fixture.engine.execute(DeleteNodeCommand(nodeID: a))

        let undoneStep = fixture.engine.undo()
        let undone = try #require(undoneStep)
        #expect(undone.savedImages.map(\.data) == [Self.bytes])
        #expect(fixture.state.image(of: a)?.id == image.id)
    }

    @Test func replaceImageUndoRedo() throws {
        var fixture = try Self.fixture()
        let a = fixture["A"]
        let first = Self.image(fixture)
        try fixture.engine.execute(SetNodeImageCommand(nodeID: a, image: first))
        let second = Self.image(fixture, data: Self.otherBytes)

        let replaced = try fixture.engine.execute(SetNodeImageCommand(nodeID: a, image: second), named: "Replace Image")
        #expect(replaced.deletedImageIDs == [first.id])
        #expect(replaced.savedImages.map(\.data) == [Self.otherBytes])
        #expect(fixture.state.images.keys.sorted() == [second.id])

        let undoneStep = fixture.engine.undo()
        let undone = try #require(undoneStep)
        #expect(undone.savedImages.map(\.id) == [first.id])
        #expect(undone.savedImages.map(\.data) == [Self.bytes])
        #expect(undone.deletedImageIDs == [second.id])
        #expect(fixture.state.image(of: a)?.id == first.id)

        fixture.engine.redo()
        #expect(fixture.state.image(of: a)?.id == second.id)
    }

    @Test func changeImageSizeUndoRedoWithoutBytes() throws {
        var fixture = try Self.fixture()
        let a = fixture["A"]
        let image = Self.image(fixture)
        try fixture.engine.execute(SetNodeImageCommand(nodeID: a, image: image))

        let resized = try fixture.engine.execute(UpdateImageCommand(imageID: image.id, displayWidth: .set(240)), named: "Change Image Size")
        #expect(fixture.state.images[image.id]?.displayWidth == 240)
        // No bytes: saving it leaves the stored file alone.
        #expect(resized.savedImages.map(\.data) == [nil])

        fixture.engine.undo()
        #expect(fixture.state.images[image.id]?.displayWidth == nil)
        fixture.engine.redo()
        #expect(fixture.state.images[image.id]?.displayWidth == 240)

        try fixture.engine.execute(UpdateImageCommand(imageID: image.id, displayWidth: .set(.nan)))
        #expect(fixture.state.images[image.id]?.displayWidth == nil)
    }

    @Test func editImageDescriptionUndoRedo() throws {
        var fixture = try Self.fixture()
        let a = fixture["A"]
        let image = Self.image(fixture)
        try fixture.engine.execute(SetNodeImageCommand(nodeID: a, image: image))

        let long = String(repeating: "x", count: 300)
        let edited = try fixture.engine.execute(UpdateImageCommand(imageID: image.id, altText: .set("  \(long)  ")), named: "Edit Image Description")
        #expect(fixture.state.images[image.id]?.altText?.count == MindImage.maximumAltTextLength)
        #expect(edited.savedImages.map(\.data) == [nil])

        fixture.engine.undo()
        #expect(fixture.state.images[image.id]?.altText == nil)
        fixture.engine.redo()
        #expect(fixture.state.images[image.id]?.altText?.count == MindImage.maximumAltTextLength)

        try fixture.engine.execute(UpdateImageCommand(imageID: image.id, altText: .set("   ")))
        #expect(fixture.state.images[image.id]?.altText == nil)
        // Nothing to change is no step.
        let none = try fixture.engine.execute(UpdateImageCommand(imageID: image.id, altText: .set(nil)))
        #expect(none.isEmpty)
    }

    @Test func updatingAMissingImageThrows() throws {
        var fixture = try Self.fixture()
        let id = ImageID()
        #expect(throws: GraphError.imageNotFound(id)) {
            try fixture.engine.execute(UpdateImageCommand(imageID: id, altText: .set("x")))
        }
    }

    @Test func imagesInBranchesListWhatADeleteWouldRemove() throws {
        var fixture = try Self.fixture()
        let onA = Self.image(fixture)
        let onA1 = Self.image(fixture)
        let onB = Self.image(fixture)
        try fixture.engine.execute(SetNodeImageCommand(nodeID: fixture["A"], image: onA))
        try fixture.engine.execute(SetNodeImageCommand(nodeID: fixture["A1"], image: onA1))
        try fixture.engine.execute(SetNodeImageCommand(nodeID: fixture["B"], image: onB))

        let state = fixture.state
        #expect(Set(state.images(inBranchesOf: [fixture["A"]]).map(\.id)) == [onA.id, onA1.id])
        #expect(Set(state.images(inBranchesOf: [fixture["A1"], fixture["A"]]).map(\.id)) == [onA.id, onA1.id])
        #expect(state.images(inBranchesOf: [fixture["Root"]]).count == 3)
    }

    @Test func mergeMovesTheImageToASurvivorWithoutOne() throws {
        var fixture = try Self.fixture()
        let (a, b) = (fixture["A"], fixture["B"])
        let image = Self.image(fixture)
        try fixture.engine.execute(SetNodeImageCommand(nodeID: b, image: image))

        let merged = try fixture.engine.execute(MergeNodesCommand(into: a, merging: [b]))
        #expect(fixture.state.image(of: a)?.id == image.id)
        // Moved, not deleted: nothing to write but the record's node.
        #expect(merged.deletedImageIDs.isEmpty)

        fixture.engine.undo()
        #expect(fixture.state.image(of: b)?.id == image.id)
        fixture.engine.redo()
        #expect(fixture.state.image(of: a)?.id == image.id)
    }

    @Test func mergeKeepsTheSurvivorsImage() throws {
        var fixture = try Self.fixture()
        let (a, b) = (fixture["A"], fixture["B"])
        let kept = Self.image(fixture)
        let dropped = Self.image(fixture, data: Self.otherBytes)
        try fixture.engine.execute(SetNodeImageCommand(nodeID: a, image: kept))
        try fixture.engine.execute(SetNodeImageCommand(nodeID: b, image: dropped))

        let merged = try fixture.engine.execute(MergeNodesCommand(into: a, merging: [b]))
        #expect(fixture.state.images.keys.sorted() == [kept.id])
        #expect(merged.deletedImageIDs == [dropped.id])

        let undoneStep = fixture.engine.undo()
        let undone = try #require(undoneStep)
        #expect(undone.savedImages.first { $0.id == dropped.id }?.data == Self.otherBytes)
    }

    @Test func duplicateCopiesLoadedImagesWithNewIDs() throws {
        var fixture = try Self.fixture()
        let (a, a1) = (fixture["A"], fixture["A1"])
        let onA = Self.image(fixture)
        let onA1 = Self.image(fixture, data: Self.otherBytes)
        try fixture.engine.execute(SetNodeImageCommand(nodeID: a, image: onA))
        try fixture.engine.execute(SetNodeImageCommand(nodeID: a1, image: onA1))
        // Only A's bytes are known (as after a reopen with only A loaded).
        fixture.engine.imageData = [onA.id: Self.bytes]

        let copyID = NodeID()
        let duplicated = try fixture.engine.execute(DuplicateBranchCommand(nodeID: a, copyID: copyID))
        let copy = try #require(fixture.state.image(of: copyID))
        #expect(copy.id != onA.id)
        #expect(copy.pixelWidth == onA.pixelWidth)
        #expect(duplicated.savedImages.map(\.data) == [Self.bytes])
        // A1's copy has no picture rather than a record with no file.
        #expect(fixture.state.images.count == 3)

        fixture.engine.undo()
        #expect(fixture.state.images.count == 2)
        fixture.engine.redo()
        #expect(fixture.state.image(of: copyID)?.id == copy.id)
    }
}
