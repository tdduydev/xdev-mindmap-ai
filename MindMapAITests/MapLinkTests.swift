import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapPersistence
import Testing

/// Share Link… and opening map links (FR-CLP-01, FR-CLP-02, ADR 0012).
@Suite("Map links")
struct MapLinkTests {
    let repository: SwiftDataMapRepository

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
    }

    private struct OpenFailed: Error {}

    private func openSession(_ outline: OutlineDraft) async throws -> EditorSession {
        let graph = GraphState.newMap(title: "Trip")
        try await repository.create(graph)
        guard case .ready(let session) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        #expect(session.importOutline(outline))
        return session
    }

    private static let tripOutline = OutlineDraft(items: [
        .init(depth: 0, title: "Hotel", note: "Near the lake", link: TopicLink(string: "https://example.com")),
        .init(depth: 0, title: "Food"),
        .init(depth: 1, title: "Phở"),
    ])

    // MARK: Opening

    @Test func linkOpensAsANewMap() async throws {
        let library = LibraryModel(repository: repository)
        var opened: MapID?
        let transfer = FileTransfer(createMap: { await library.createMap($0, imageData: $1) }, openMap: { opened = $0 })
        let source = try await openSession(Self.tripOutline)
        let url = try MapLinkCodec.link(for: source.engine.state)

        await transfer.openMapLink(url)

        #expect(transfer.mapLinkFailure == nil)
        let id = try #require(opened)
        #expect(id != source.map.id)
        let graph = try #require(try await repository.loadGraph(for: id))
        let rootID = try #require(graph.map.rootNodeID)
        #expect(graph.map.title == "Trip")
        #expect(graph.children(of: rootID).map(\.title) == ["Hotel", "Food"])
        #expect(graph.children(of: rootID).first?.note == "Near the lake")
        #expect(graph.children(of: rootID).first?.link?.string == "https://example.com")
        // The map it came from is untouched.
        #expect(try await repository.loadGraph(for: source.map.id)?.nodes.count == source.engine.state.nodes.count)
    }

    @Test func linkDeliveredTwiceOpensOneMap() async throws {
        var created = 0
        let transfer = FileTransfer(createMap: { graph, _ in created += 1; return graph.map.id }, openMap: { _ in })
        let url = try MapLinkCodec.link(for: GraphState.newMap(title: "Plan"))
        let now = Date.now

        await transfer.openMapLink(url, now: now)
        await transfer.openMapLink(url, now: now.addingTimeInterval(0.5))
        #expect(created == 1)

        // Opened again later on purpose: a second map, as docs/app-clip.md says.
        await transfer.openMapLink(url, now: now.addingTimeInterval(FileTransfer.repeatedLinkInterval + 1))
        #expect(created == 2)
    }

    @Test func brokenLinksSayWhy() async throws {
        let transfer = FileTransfer(createMap: { _, _ in Issue.record("Nothing is created"); return nil }, openMap: { _ in })

        await transfer.openMapLink(URL(string: "https://xdev.asia/mindmap/m#1.q1Yq")!)
        #expect(transfer.mapLinkFailure == .unreadable)

        await transfer.openMapLink(URL(string: "https://xdev.asia/mindmap/m#2.q1Yq")!)
        #expect(transfer.mapLinkFailure == .newerVersion)

        await transfer.openMapLink(text: "Not a link at all")
        #expect(transfer.mapLinkFailure == .unreadable)

        await transfer.openMapLink(text: "https://example.com/mindmap/m#1.q1Yq")
        #expect(transfer.mapLinkFailure == .unreadable)

        #expect(MapLinkFailure.newerVersion.message.contains("newer version"))
    }

    @Test func pastedLinkWithSpacesOpens() async throws {
        var opened: MapID?
        let transfer = FileTransfer(createMap: { graph, _ in graph.map.id }, openMap: { opened = $0 })
        transfer.isOpeningMapLink = true
        let url = try MapLinkCodec.link(for: GraphState.newMap(title: "Plan"))

        await transfer.openMapLink(text: "  \(url.absoluteString)\n")

        #expect(opened != nil)
        #expect(!transfer.isOpeningMapLink)
    }

    @Test func onlyMapLinksAreHandled() {
        #expect(FileTransfer.isMapLink(URL(string: "https://xdev.asia/mindmap/m#1.abc")!))
        #expect(!FileTransfer.isMapLink(URL(string: "https://xdev.asia/mindmap/privacy")!))
        #expect(!FileTransfer.isMapLink(URL(string: "file:///tmp/a.md")!))
    }

    // MARK: Sharing

    @Test func sharesTheWholeMapByDefault() async throws {
        let session = try await openSession(Self.tripOutline)
        // Importing selects the new topics; nothing selected shares the map.
        session.selection = nil
        let model = ShareLinkModel(session: session)
        #expect(model.branchID == nil)

        await model.prepare()

        guard case .ready(let url, withoutNotes: false) = model.status else {
            Issue.record("A small map fits in a link")
            return
        }
        let shared = try await MapLinkCodec.map(from: url)
        #expect(shared.nodes.count == session.engine.state.nodes.count)
        #expect(model.title == "Trip")
    }

    @Test func sharesTheSelectedBranch() async throws {
        let session = try await openSession(Self.tripOutline)
        let foodID = try #require(session.engine.state.nodes.values.first { $0.title == "Food" }?.id)
        session.selection = foodID
        let model = ShareLinkModel(session: session)
        #expect(model.branchID == foodID)

        model.scope = .branch(foodID)
        await model.prepare()

        guard case .ready(let url, _) = model.status else {
            Issue.record("A branch fits in a link")
            return
        }
        let shared = try await MapLinkCodec.map(from: url)
        #expect(shared.map.title == "Food")
        #expect(shared.nodes.count == 2)
        #expect(model.title == "Food")
        #expect(model.branchToOffer == nil)
    }

    @Test func centralTopicSelectedIsTheWholeMap() async throws {
        let session = try await openSession(Self.tripOutline)
        session.selection = session.map.rootNodeID
        #expect(ShareLinkModel(session: session).branchID == nil)
    }

    @Test func tooBigMapOffersSmallerShares() async throws {
        // Notes of random letters do not compress; their titles do.
        var items: [OutlineDraft.Item] = [.init(depth: 0, title: "Notes")]
        for index in 0 ..< 60 {
            items.append(.init(depth: 1, title: "Topic \(index)", note: Self.noise(length: 200, seed: index)))
        }
        let session = try await openSession(OutlineDraft(items: items))
        let notesID = try #require(session.engine.state.nodes.values.first { $0.title == "Notes" }?.id)
        session.selection = notesID
        let model = ShareLinkModel(session: session)

        await model.prepare()

        #expect(model.status == .tooLong(canShareWithoutNotes: true))
        #expect(model.branchToOffer == notesID)
        model.shareWithoutNotes()
        guard case .ready(let url, withoutNotes: true) = model.status else {
            Issue.record("The map without notes fits")
            return
        }
        #expect(url.absoluteString.count <= MapLinkCodec.maximumLinkLength)
        #expect(try await MapLinkCodec.map(from: url).nodes.values.allSatisfy { $0.note == nil })
    }

    @Test func menuCommandAndToolbarOpenTheSameSheet() async throws {
        let session = try await openSession(Self.tripOutline)
        let transfer = FileTransfer(createMap: { _, _ in nil }, openMap: { _ in })
        transfer.beginShareLink(session)
        #expect(transfer.shareLinkRequest?.session === session)
    }

    static func noise(length: Int, seed: Int) -> String {
        var state = UInt64(seed + 1) &* 0x9E37_79B9_7F4A_7C15
        let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0 ..< length).map { _ in
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return letters[Int(state % UInt64(letters.count))]
        })
    }
}
