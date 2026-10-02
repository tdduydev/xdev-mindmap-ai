import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Testing

/// The Topic menu enables each item from these session properties, so the
/// rules below are what a person sees as enabled or disabled in the menu bar.
@Suite("Menu command state")
struct MenuCommandStateTests {
    let repository: SwiftDataMapRepository
    let mapID: MapID

    init() async throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        let graph = GraphState.newMap(title: "Plan")
        try await repository.create(graph)
        mapID = graph.map.id
    }

    private func open() async throws -> EditorSession {
        guard case .ready(let session) = await EditorSession.open(mapID: mapID, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        return session
    }

    @Test func centralTopicSelected() async throws {
        let session = try await open()

        #expect(session.selection == session.rootID)
        #expect(!session.canDeleteSelection)
        #expect(!session.canDuplicateSelection)
        #expect(!session.canPromoteSelection)
        #expect(!session.canDemoteSelection)
        #expect(!session.canToggleSelection)
    }

    @Test func firstChildSelected() async throws {
        let session = try await open()
        session.addChild()

        #expect(session.canDeleteSelection)
        #expect(session.canDuplicateSelection)
        // A first child has no sibling before it to go under, and its parent is the central topic.
        #expect(!session.canDemoteSelection)
        #expect(!session.canPromoteSelection)
        #expect(!session.canToggleSelection)
    }

    @Test func secondChildCanBeDemotedThenPromoted() async throws {
        let session = try await open()
        session.addChild()
        let first = try #require(session.selection)
        session.addSibling()

        #expect(session.canDemoteSelection)
        session.demoteSelection()
        #expect(session.canPromoteSelection)

        session.selection = first
        #expect(session.canToggleSelection)
        #expect(!session.selectionIsCollapsed)
        session.toggleSelectionCollapsed()
        #expect(session.selectionIsCollapsed)
    }

    @Test func nothingSelected() async throws {
        let session = try await open()
        session.selection = nil

        #expect(!session.canDeleteSelection)
        #expect(!session.canDuplicateSelection)
        #expect(!session.canPromoteSelection)
        #expect(!session.canDemoteSelection)
        #expect(!session.canToggleSelection)
        #expect(!session.deleteKeyDeletesTopic)
    }

    /// Delete is the Delete Topic shortcut only while the editor has focus
    /// and no title is being typed (FR-KBD-01).
    @Test func deleteKeyFollowsKeyboardFocus() async throws {
        let session = try await open()
        session.addChild()
        #expect(session.canDeleteSelection)

        session.keyboardFocus = .elsewhere
        #expect(!session.deleteKeyDeletesTopic)
        session.keyboardFocus = .editingText
        #expect(!session.deleteKeyDeletesTopic)
        session.keyboardFocus = .content
        #expect(session.deleteKeyDeletesTopic)

        session.selection = session.rootID
        #expect(!session.deleteKeyDeletesTopic)
    }

    @Test func windowTitleIsTheMapTitle() async throws {
        let session = try await open()
        #expect(session.displayTitle == "Plan")

        session.renameMap(to: "")
        #expect(session.displayTitle == String(localized: "Untitled Map"))
    }

    private struct OpenFailed: Error {}
}

/// The glossary in the comments of Localizable.xcstrings (NFR-L10N-02),
/// checked against the Vietnamese strings the app ships.
@Suite("Glossary")
struct GlossaryTests {
    @Test func vietnameseUsesTheFixedTerms() throws {
        let path = try #require(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "vi"))
        let strings = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
        #expect(!strings.isEmpty)

        for (key, value) in strings {
            let lowered = value.lowercased()
            #expect(!lowered.contains("bản đồ"), "“\(key)” should say “sơ đồ” for map")
        }
        #expect(strings["Topic"] == "Chủ đề")
        #expect(strings["Central Topic"] == "Chủ đề trung tâm")
        #expect(strings["New Mind Map"] == "Sơ đồ mới")
    }
}
