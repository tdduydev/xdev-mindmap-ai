import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapInterchange
import MindMapPersistence
import SwiftUI
import Testing
import UniformTypeIdentifiers

/// OPML in File ▸ Import… (free, a new map, a summary of what was lost) and
/// File ▸ Export… (Pro) (FR-IO-06, FR-IO-13).
@Suite("OPML import and export")
struct OPMLTests {
    let repository: SwiftDataMapRepository
    let folder: URL

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        folder = FileManager.default.temporaryDirectory.appending(path: "OPMLTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func file(_ name: String, _ contents: String) throws -> URL {
        let url = folder.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func transfer(_ library: LibraryModel, opened: @escaping (MapID) -> Void = { _ in }) -> FileTransfer {
        FileTransfer(createMap: { await library.createMap($0, imageData: $1) }, openMap: opened)
    }

    private let trip = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Trip</title></head>
          <body>
            <outline text="Tokyo" _note="Five days">
              <outline text="Shibuya"/>
            </outline>
            <outline text="Kyoto" type="include" url="https://example.com/kyoto.opml"/>
          </body>
        </opml>
        """

    // MARK: Import

    @Test func theOpenPanelOffersOPML() {
        #expect(MapImporter.contentTypes.contains(.opml))
        #expect(UTType.opml.conforms(to: .xml))
        #expect(MapImporter.foreignFormat(of: URL(filePath: "/a/Plan.OPML")) == .opml)
        #expect(MapImporter.foreignFormat(of: URL(filePath: "/a/Plan.md")) == nil)
    }

    @Test func importsAsANewMapAndSummarizesWhatWasNotKept() async throws {
        let library = LibraryModel(repository: repository)
        var opened: MapID?
        let transfer = transfer(library) { opened = $0 }

        await transfer.importFile(at: try file("trip.opml", trip), into: .newMap)

        #expect(transfer.failure == nil)
        let id = try #require(opened)
        let graph = try #require(try await repository.loadGraph(for: id))
        let rootID = try #require(graph.map.rootNodeID)
        // Two top-level outlines: the central topic takes the head's title.
        #expect(graph.node(rootID)?.title == "Trip")
        let tokyo = try #require(graph.children(of: rootID).first)
        #expect(graph.children(of: rootID).map(\.title) == ["Tokyo", "Kyoto"])
        #expect(tokyo.note == "Five days")
        #expect(graph.children(of: tokyo.id).map(\.title) == ["Shibuya"])
        #expect(graph.children(of: rootID).last?.link?.string == "https://example.com/kyoto.opml")

        let summary = try #require(transfer.importSummary)
        #expect(summary.title.contains("trip.opml"))
        #expect(summary.report.entries == [.init(loss: .includedOutline, count: 1)])
        #expect(summary.message.contains("1"))
    }

    @Test func aCompleteImportShowsNoSummary() async throws {
        let library = LibraryModel(repository: repository)
        let transfer = transfer(library)
        let url = try file("plan.opml", #"<opml version="2.0"><body><outline text="Plan"/></body></opml>"#)

        await transfer.importFile(at: url, into: .newMap)

        #expect(transfer.failure == nil)
        #expect(transfer.importSummary == nil)
        #expect(library.maps.count == 1)
    }

    @Test func badFilesSayWhatIsWrong() async throws {
        let library = LibraryModel(repository: repository)
        let transfer = transfer(library)

        await transfer.importFile(at: try file("feed.opml", #"<rss version="2.0"/>"#), into: .newMap)
        #expect(transfer.failure == .wrongFormat(fileName: "feed.opml", format: .opml))

        await transfer.importFile(at: try file("cut.opml", #"<opml version="2.0"><body><outline text="A">"#), into: .newMap)
        #expect(transfer.failure == .damagedFile(fileName: "cut.opml"))

        await transfer.importFile(at: try file("empty.opml", #"<opml version="2.0"><body/></opml>"#), into: .newMap)
        #expect(transfer.failure == .noTopics(fileName: "empty.opml"))

        #expect(library.maps.isEmpty)
        for failure: ImportFailure in [
            .wrongFormat(fileName: "a.opml", format: .opml), .damagedFile(fileName: "a.opml"),
            .noTopics(fileName: "a.opml"), .foreignIntoMap(fileName: "a.opml"),
        ] {
            #expect(failure.title.contains("a.opml"))
            #expect(!failure.message.isEmpty)
        }
        #expect(ImportFailure.unsupportedType(fileName: "a.rtf").message.contains(".opml"))
    }

    @Test func importIntoMapRefusesOPMLAndChangesNothing() async throws {
        let graph = GraphState.newMap(title: "Plan")
        try await repository.create(graph)
        guard case .ready(let session) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            Issue.record("The map did not open")
            return
        }
        let transfer = FileTransfer(createMap: { _, _ in nil }, openMap: { _ in })

        await transfer.importFile(at: try file("trip.opml", trip), into: .openMap(session))

        #expect(transfer.failure == .foreignIntoMap(fileName: "trip.opml"))
        #expect(session.engine.state.nodes.count == 1)
        #expect(!session.canUndo)
    }

    @Test func everyLossHasALine() {
        for loss in ImportReport.Loss.allCases {
            let line = ImportSummary.line(for: .init(loss: loss, count: 2))
            #expect(line.contains("2"))
        }
    }

    // MARK: Export

    @Test func exportWritesOPMLOfTheMapOrABranch() async throws {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Trip"))
        let rootID = try #require(engine.state.map.rootNodeID)
        let flights = NodeID()
        try engine.execute(AddNodeCommand(nodeID: flights, .child(of: rootID), title: "Flights"))
        try engine.execute(AddNodeCommand(.child(of: flights), title: "Hanoi"))
        var options = ExportOptions()
        options.format = .opml

        let whole = String(decoding: try await MapExporter.data(for: engine.state, options: options, colorScheme: .light), as: UTF8.self)
        #expect(whole.contains(#"<opml version="2.0">"#))
        #expect(whole.contains(#"<outline text="Trip">"#))

        options.branch = flights
        let branch = String(decoding: try await MapExporter.data(for: engine.state, options: options, colorScheme: .light), as: UTF8.self)
        #expect(!branch.contains(#"<outline text="Trip">"#))
        #expect(branch.contains(#"<outline text="Hanoi"/>"#))
        #expect(ExportFormat.opml.contentType == .opml)
        #expect(ExportFormat.opml.fileExtension == "opml")
    }

    @Test func exportIsProAndImportIsFree() {
        var options = ExportOptions()
        options.format = .opml
        #expect(options.requiredFeature == .opmlExport)
        #expect(ProFeature.offered(includingAI: false).contains(.opmlExport))
        #expect(!ProFeature.opmlExport.needsOnDeviceModel)
    }

    @Test func theSheetDoesNotReopenOnALockedOPMLExport() throws {
        let defaults = try #require(UserDefaults(suiteName: "OPMLTests-\(UUID().uuidString)"))
        defaults.set(ExportFormat.opml.rawValue, forKey: ExportPreferences.formatKey)
        let preferences = ExportPreferences(defaults: defaults)

        #expect(preferences.options(entitlements: Locked()).format == .markdown)
        #expect(preferences.options(entitlements: Unlocked()).format == .opml)
    }
}

private struct Locked: ProEntitlements {
    func allows(_ feature: ProFeature) -> Bool { false }
}

private struct Unlocked: ProEntitlements {
    func allows(_ feature: ProFeature) -> Bool { true }
}
