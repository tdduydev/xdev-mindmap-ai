import Foundation
@testable import MindMapAI
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapTestSupport
import Testing

/// MM-17: windows that show the same map share one session, so neither can
/// write over the other (FR-PER-08, NFR-REL-06), and a window's editor state
/// comes back at relaunch (FR-PER-09).
@Suite("Open maps")
struct OpenMapsTests {
    let repository: SwiftDataMapRepository
    let openMaps: OpenMaps
    let service = AIService(provider: { MockAIProvider() }, entitlements: Unlocked())
    let mapID: MapID

    init() async throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        openMaps = OpenMaps(repository: repository, clipboard: MemoryClipboard())
        let graph = GraphState.newMap(title: "Plan")
        try await repository.create(graph)
        mapID = graph.map.id
    }

    private func open(in window: WindowToken) async throws -> OpenMap {
        guard case .ready(let map) = await openMaps.open(mapID, in: window, service: service) else { throw OpenFailed() }
        return map
    }

    /// The map as the store has it, through a session of its own.
    private func stored() async throws -> EditorSession {
        guard case .ready(let session) = await EditorSession.open(mapID: mapID, repository: repository, clipboard: MemoryClipboard(), onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        return session
    }

    // MARK: One session per map

    @Test func twoWindowsOnOneMapShareTheSession() async throws {
        let first = try await open(in: WindowToken())
        let second = try await open(in: WindowToken())

        #expect(first.session === second.session)
        #expect(first.canvas === second.canvas)
        #expect(first.assistant === second.assistant)
    }

    @Test func windowsOpeningAtOnceShareOneLoad() async throws {
        async let first = open(in: WindowToken())
        async let second = open(in: WindowToken())
        let maps = try await [first, second]

        #expect(maps[0].session === maps[1].session)
    }

    @Test func twoWindowsEditingTheSameMapLoseNoChange() async throws {
        let (a, b) = (WindowToken(), WindowToken())
        let inA = try await open(in: a).session
        let inB = try await open(in: b).session

        inA.renameMap(to: "Launch")
        inB.addChild()
        let topic = try #require(inB.selection)
        inB.rename(topic, to: "Budget")
        inA.selection = inA.rootID
        inA.addChild()
        let other = try #require(inA.selection)
        inA.rename(other, to: "Timeline")
        openMaps.close(mapID, in: a)
        openMaps.close(mapID, in: b)
        await openMaps.flush()

        let saved = try await stored()
        #expect(saved.map.title == "Launch")
        #expect(saved.rows.map(\.node.title) == ["Plan", "Budget", "Timeline"])
    }

    /// Why the sessions are shared: two of them on one map each save from a
    /// graph the other has not seen, and the later save wins.
    @Test func separateSessionsOnOneMapWouldWriteOverEachOther() async throws {
        let first = try await stored()
        let second = try await stored()

        first.renameMap(to: "Launch")
        await first.flush()
        second.addChild()
        await second.flush()

        #expect(try await stored().map.title == "Plan")
    }

    // MARK: Closing

    @Test func aMapNoWindowShowsIsReleasedOnceSaved() async throws {
        let window = WindowToken()
        let map = try await open(in: window)
        map.session.addChild()

        openMaps.close(mapID, in: window)
        await openMaps.flush()

        #expect(!openMaps.isOpen(mapID))
        #expect(try await stored().rows.count == 2)
    }

    @Test func aMapStaysWhileAnotherWindowShowsIt() async throws {
        let (a, b) = (WindowToken(), WindowToken())
        _ = try await open(in: a)
        _ = try await open(in: b)

        openMaps.close(mapID, in: a)
        await openMaps.flush()

        #expect(openMaps.isOpen(mapID))
    }

    @Test func openingAgainWhileSavingGetsTheSameSession() async throws {
        let (a, b) = (WindowToken(), WindowToken())
        let first = try await open(in: a)
        first.session.addChild()

        openMaps.close(mapID, in: a)
        let second = try await open(in: b)
        await openMaps.flush()

        #expect(second.session === first.session)
        #expect(openMaps.isOpen(mapID), "the second window still shows it")
    }

    @Test func aMapClosedWhileLoadingIsReleased() async throws {
        let window = WindowToken()
        let opening = Task { [openMaps, mapID, service] in await openMaps.open(mapID, in: window, service: service) }
        // Lets the open start and wait on the store, as a window's task does before it disappears.
        await Task.yield()
        openMaps.close(mapID, in: window)
        _ = await opening.value
        await openMaps.flush()

        #expect(!openMaps.isOpen(mapID))
    }

    @Test func aMissingMapIsNotKept() async throws {
        let window = WindowToken()
        let opening = await openMaps.open(MapID(), in: window, service: service)

        guard case .missing = opening else { Issue.record("expected a missing map"); return }
        #expect(openMaps.window(showing: mapID, besides: WindowToken()) == nil)
    }

    // MARK: One window per map

    @Test func pickingAMapAnotherWindowShowsBringsThatWindowForward() async throws {
        let (a, b) = (WindowToken(), WindowToken())
        var activated: [String] = []
        openMaps.register(a, activate: { activated.append("a") }, onMapChange: { _ in })
        openMaps.register(b, activate: { activated.append("b") }, onMapChange: { _ in })
        _ = try await open(in: a)

        #expect(openMaps.activateWindow(showing: mapID, besides: b))
        #expect(!openMaps.activateWindow(showing: mapID, besides: a), "a window does not bring itself forward")
        #expect(activated == ["a"])
    }

    @Test func everyWindowHearsOfMapChanges() async throws {
        let (a, b) = (WindowToken(), WindowToken())
        var heard: [String] = []
        openMaps.register(a, activate: {}, onMapChange: { heard.append("a:" + $0.title) })
        openMaps.register(b, activate: {}, onMapChange: { heard.append("b:" + $0.title) })
        let map = try await open(in: a)

        map.session.renameMap(to: "Launch")

        #expect(heard.sorted() == ["a:Launch", "b:Launch"])
    }

    // MARK: Restoration

    @Test func restorationBringsBackSelectionAndPresentation() async throws {
        let session = try await open(in: WindowToken()).session
        session.addChild()
        let first = try #require(session.selection)
        session.addSibling()
        let second = try #require(session.selection)
        session.setSelection([first, second], primary: second)
        session.presentation = .outline
        let data = try #require(EditorRestoration(session).data)
        await openMaps.flush()

        let restored = try await stored()
        try #require(EditorRestoration(data: data)).apply(to: restored)

        #expect(restored.selectedIDs == [first, second])
        #expect(restored.primarySelection == second)
        #expect(restored.presentation == .outline)
    }

    @Test func restorationLeavesOutDeletedTopics() async throws {
        let session = try await open(in: WindowToken()).session
        session.addChild()
        let topic = try #require(session.selection)
        let state = EditorRestoration(session)
        session.deleteSelection()

        state.apply(to: session)

        #expect(!session.selectedIDs.contains(topic))
        #expect(session.selection != nil)
    }

    @Test func restorationOfAnotherMapIsIgnored() async throws {
        let session = try await open(in: WindowToken()).session
        session.presentation = .outline
        var state = EditorRestoration(session)
        state.mapID = MapID()
        session.presentation = .canvas

        state.apply(to: session)

        #expect(session.presentation == .canvas)
    }

    @Test func unreadableRestorationIsNoState() {
        #expect(EditorRestoration(data: Data("not json".utf8)) == nil)
        #expect(EditorRestoration(data: nil) == nil)
    }

    private struct OpenFailed: Error {}
}

private struct Unlocked: ProEntitlements {
    func allows(_ feature: ProFeature) -> Bool { true }
}
