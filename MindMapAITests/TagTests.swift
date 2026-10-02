import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapTestSupport
import Testing

/// MM-34: tagging topics from the inspector and menus, managing map and
/// shared tags, chips on the canvas, and Suggest Tags with `MockAIProvider`.
@Suite("Tags")
struct TagTests {
    let repository: SwiftDataMapRepository

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
    }

    /// A map "Plan" with the topics A and B under the central topic.
    private func open(_ graph: GraphState? = nil) async throws -> EditorSession {
        let graph = try graph ?? Self.plan()
        try await repository.create(graph)
        return try await reopen(graph.map.id)
    }

    private func reopen(_ mapID: MapID) async throws -> EditorSession {
        guard case .ready(let session) = await EditorSession.open(mapID: mapID, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        return session
    }

    static func plan() throws -> GraphState {
        var engine = try GraphEngine(state: GraphState.newMap(title: "Plan"))
        let rootID = try #require(engine.state.map.rootNodeID)
        try engine.execute(AddNodeCommand(.child(of: rootID), title: "A"))
        try engine.execute(AddNodeCommand(.child(of: rootID), title: "B"))
        return engine.state
    }

    private func node(_ title: String, in session: EditorSession) throws -> NodeID {
        try #require(session.engine.state.nodes.values.first { $0.title == title }?.id)
    }

    private func undoManager(for session: EditorSession) -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager
        return undoManager
    }

    private func step(_ undoManager: UndoManager, _ action: () -> Void) {
        undoManager.beginUndoGrouping()
        action()
        undoManager.endUndoGrouping()
    }

    private func tagNames(of id: NodeID, in session: EditorSession) -> [String] {
        session.engine.state.tags(of: id).map(\.name)
    }

    // MARK: Tagging

    @Test func typingANameTagsEverySelectedTopicAsOneNamedStep() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let a = try node("A", in: session)
        let b = try node("B", in: session)
        session.setSelection([a, b], primary: a)

        step(undoManager) { session.addTag(named: " #Việc ") }

        #expect(tagNames(of: a, in: session) == ["Việc"])
        #expect(tagNames(of: b, in: session) == ["Việc"])
        #expect(session.engine.state.mapTags.count == 1)
        #expect(undoManager.undoActionName == String(localized: "Add Tag"))
        undoManager.undo()
        #expect(session.engine.state.tags.isEmpty && session.engine.state.nodeTags.isEmpty)
        undoManager.redo()
        #expect(tagNames(of: b, in: session) == ["Việc"])

        await session.flush()
        let stored = try #require(try await repository.loadGraph(for: session.map.id))
        #expect(stored.tags(of: a).map(\.name) == ["Việc"])
    }

    @Test func aBadNameIsRefusedWithAMessage() async throws {
        let session = try await open()
        session.selection = try node("A", in: session)

        #expect(!session.addTag(named: "#"))
        #expect(session.tagFailure == .invalidName)
        #expect(!session.canUndo)
    }

    @Test func theMenuToggleTagsAllThenRemovesFromAll() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let a = try node("A", in: session)
        let b = try node("B", in: session)
        session.selection = a
        step(undoManager) { session.addTag(named: "Việc") }
        let tagID = try #require(session.engine.state.mapTags.first?.id)
        session.setSelection([a, b], primary: a)
        #expect(session.coverage(of: tagID) == .some)

        step(undoManager) { session.toggleTag(tagID) }
        #expect(session.coverage(of: tagID) == .all)
        #expect(undoManager.undoActionName == String(localized: "Add Tag"))

        step(undoManager) { session.toggleTag(tagID) }
        #expect(session.coverage(of: tagID) == .none)
        #expect(undoManager.undoActionName == String(localized: "Remove Tag"))
        undoManager.undo()
        #expect(session.coverage(of: tagID) == .all)
        #expect(session.mostUsedTags().map(\.id) == [tagID])
    }

    @Test func theFieldOffersTagsBySearchFoldingAndCreateForNewNames() async throws {
        let session = try await open()
        let a = try node("A", in: session)
        let b = try node("B", in: session)
        session.selection = b
        session.addTag(named: "Việc cần làm")
        session.selection = a

        #expect(session.tagMatches(for: "viec").map(\.name) == ["Việc cần làm"])
        #expect(session.tagMatches(for: "#VIEC").map(\.name) == ["Việc cần làm"])
        #expect(!session.wouldCreateTag(named: "VIỆC CẦN LÀM"), "same key, same tag")
        #expect(session.wouldCreateTag(named: "Gấp"))

        session.selection = b
        #expect(session.tagMatches(for: "viec").isEmpty, "a tag the topic has is not offered again")
    }

    @Test func addTagFromTheMenuOpensTheInspectorField() async throws {
        let session = try await open()
        session.selection = try node("A", in: session)

        session.beginAddingTag()

        #expect(session.isInspectorPresented)
        #expect(session.tagFieldFocusRequest)
    }

    // MARK: Managing map tags

    @Test func renameRecolourMergeAndDeleteAreNamedUndoSteps() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let a = try node("A", in: session)
        let b = try node("B", in: session)
        session.selection = a
        step(undoManager) { session.addTag(named: "Việc") }
        session.selection = b
        step(undoManager) { session.addTag(named: "Task") }
        let viec = try #require(session.engine.state.tag(named: "Việc")?.id)
        let task = try #require(session.engine.state.tag(named: "Task")?.id)

        undoManager.beginUndoGrouping()
        await session.renameTag(viec, to: "Công việc")
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == String(localized: "Rename Tag"))
        undoManager.beginUndoGrouping()
        await session.setTagColor(viec, to: .rose)
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == String(localized: "Change Tag Color"))
        undoManager.beginUndoGrouping()
        await session.mergeTag(task, into: viec)
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == String(localized: "Merge Tags"))
        #expect(tagNames(of: b, in: session) == ["Công việc"])
        undoManager.beginUndoGrouping()
        await session.deleteTag(viec)
        undoManager.endUndoGrouping()
        #expect(undoManager.undoActionName == String(localized: "Delete Tag"))
        #expect(session.engine.state.tags.isEmpty)

        undoManager.undo()
        undoManager.undo()
        #expect(tagNames(of: b, in: session) == ["Task"])
        #expect(session.engine.state.tag(viec)?.color == .rose)
        undoManager.redo()
        #expect(tagNames(of: b, in: session) == ["Công việc"])
    }

    @Test func renamingToAnotherTagsNameIsRefused() async throws {
        let session = try await open()
        session.selection = try node("A", in: session)
        session.addTag(named: "Việc")
        session.addTag(named: "Gấp")
        let gap = try #require(session.engine.state.tag(named: "Gấp")?.id)

        await session.renameTag(gap, to: "VIỆC")

        #expect(session.tagFailure == .nameTaken("Việc"))
        #expect(session.engine.state.tag(gap)?.name == "Gấp")
    }

    // MARK: Shared tags

    @Test func makeSharedReachesAnotherOpenMapAndClearsHistory() async throws {
        let first = try await open()
        let undoManager = undoManager(for: first)
        let second = try await open()
        let observing = Task { await second.observeStore() }
        defer { observing.cancel() }
        // The subscription starts before the action below.
        await Task.yield()
        first.selection = try node("A", in: first)
        step(undoManager) { first.addTag(named: "Việc") }
        let tagID = try #require(first.engine.state.mapTags.first?.id)

        await first.makeShared(tagID)

        #expect(first.engine.state.tag(tagID)?.isShared == true)
        #expect(!first.canUndo && !undoManager.canUndo, "undoing the tag's creation would delete a library tag")
        try await waitUntil { second.engine.state.tag(tagID) != nil }
        #expect(second.availableTags.map(\.id) == [tagID])
        second.selection = try node("B", in: second)
        #expect(second.addTag(named: "việc"), "the shared tag is reused by name")
        #expect(second.engine.state.mapTags.isEmpty)
        await second.flush()
        #expect(await first.sharedTagMapCounts() == [tagID: 2])
    }

    @Test func renamingASharedTagKeepsUndoAndReachesStoredMaps() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        session.selection = try node("A", in: session)
        step(undoManager) { session.addTag(named: "Việc") }
        let tagID = try #require(session.engine.state.mapTags.first?.id)
        await session.makeShared(tagID)
        step(undoManager) { session.addTag(named: "Gấp") }

        await session.renameTag(tagID, to: "Công việc")

        #expect(session.engine.state.tag(tagID)?.name == "Công việc")
        #expect(undoManager.canUndo, "a rename of a shared tag leaves the map's steps alone")
        let stored = try #require(try await repository.loadGraph(for: session.map.id))
        #expect(stored.tag(tagID)?.name == "Công việc")
    }

    @Test func deletingASharedTagRemovesItFromEveryMap() async throws {
        let first = try await open()
        first.selection = try node("A", in: first)
        first.addTag(named: "Việc")
        let tagID = try #require(first.engine.state.mapTags.first?.id)
        await first.makeShared(tagID)
        let second = try await open()
        second.selection = try node("A", in: second)
        second.addTag(tagID)
        await second.flush()

        await first.deleteTag(tagID)

        #expect(first.engine.state.tags.isEmpty && first.engine.state.nodeTags.isEmpty)
        let stored = try #require(try await repository.loadGraph(for: second.map.id))
        #expect(stored.nodeTags.isEmpty)
    }

    @Test func aSharedTagUsedElsewhereStaysShared() async throws {
        let first = try await open()
        first.selection = try node("A", in: first)
        first.addTag(named: "Việc")
        let tagID = try #require(first.engine.state.mapTags.first?.id)
        await first.makeShared(tagID)
        let second = try await open()
        second.selection = try node("A", in: second)
        second.addTag(tagID)
        await second.flush()

        await first.makeMapTag(tagID)

        #expect(first.tagFailure == .usedInOtherMaps(1))
        #expect(first.engine.state.tag(tagID)?.isShared == true)
        #expect(!first.canMerge(tagID, into: TagID()))
    }

    // MARK: Canvas and outline

    @Test func chipsAreMeasuredWithTheTitleAndCapAtThreeThenMore() async throws {
        let session = try await open()
        let canvas = CanvasModel(session: session)
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        let a = try node("A", in: session)
        let before = try #require(canvas.scene.topic(a)?.frame.size)

        session.selection = a
        for name in ["One", "Two", "Three", "Four", "Five"] { session.addTag(named: name) }
        await canvas.layoutSettled()

        let topic = try #require(canvas.scene.topic(a))
        #expect(topic.chips.map(\.label) == ["One", "Two", "Three", "+2"])
        let measured = topic.chips.allSatisfy { $0.width > 0 }
        #expect(measured)
        #expect(topic.frame.height > before.height, "the chip row is part of the box")
        #expect(topic.tagNames.count == 5)
        let row = try #require(session.rows.first { $0.id == a })
        #expect(row.tags.map(\.name) == ["One", "Two", "Three", "Four", "Five"])

        let one = try #require(session.engine.state.tag(named: "One")?.id)
        await session.renameTag(one, to: "A much longer first tag name")
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(a)?.chips.first?.label == "A much longer first tag name", "a renamed tag measures again")
    }

    // MARK: Suggest Tags

    private func assistant(for session: EditorSession, provider: MockAIProvider, capabilities: AICapabilities = .readyForTesting) async throws -> AIAssistant {
        let defaults = try #require(UserDefaults(suiteName: "TagTests.\(UUID().uuidString)"))
        defaults.set(true, forKey: AIAssistant.privacyNoticeKey)
        provider.setCapabilities(capabilities)
        let service = AIService(provider: { provider }, entitlements: EverythingUnlocked())
        await service.refresh()
        return AIAssistant(session: session, service: service, defaults: defaults, locale: Locale(identifier: "en_US"))
    }

    @Test func suggestedTagsStayOutOfTheMapUntilAcceptedOneByOne() async throws {
        let session = try await open()
        let undoManager = undoManager(for: session)
        let provider = MockAIProvider()
        let assistant = try await assistant(for: session, provider: provider)
        let rootID = try #require(session.rootID)
        let a = try node("A", in: session)
        let b = try node("B", in: session)
        provider.enqueue(.tags(.tags([a: ["Travel", "Urgent"], b: ["Travel"]], order: [a, b])), for: .suggestTags)

        assistant.suggestTags(rootID)
        await assistant.requestSettled()

        guard case .suggestTags(let request) = provider.requests.last else { throw OpenFailed() }
        #expect(request.topics.map(\.title) == ["Plan", "A", "B"], "the branch of the topic")
        #expect(assistant.hasTagSuggestions && assistant.canAcceptSuggestions)
        #expect(assistant.suggestionCount == 3)
        #expect(session.engine.state.nodeTags.isEmpty)
        #expect(!session.canUndo)

        let urgent = try #require(assistant.tagSuggestions?.suggestions.first { $0.name == "Urgent" })
        step(undoManager) { assistant.acceptTag(urgent.id) }
        #expect(tagNames(of: a, in: session) == ["Urgent"])
        let fromAI = session.engine.state.nodeTags.values.allSatisfy { $0.origin == .ai }
        #expect(fromAI)
        #expect(undoManager.undoActionName == String(localized: "Add AI Tags"))
        #expect(assistant.suggestionCount == 2)

        let travelOnB = try #require(assistant.tagSuggestions?.suggestions(for: b).first)
        assistant.discardTag(travelOnB.id)
        step(undoManager) { assistant.acceptAll() }
        #expect(tagNames(of: a, in: session) == ["Urgent", "Travel"])
        #expect(tagNames(of: b, in: session).isEmpty)
        #expect(!assistant.hasSuggestions)

        undoManager.undo()
        #expect(tagNames(of: a, in: session) == ["Urgent"])
    }

    @Test func aRenamedSuggestionIsAcceptedAsEdited() async throws {
        let session = try await open()
        let provider = MockAIProvider()
        let assistant = try await assistant(for: session, provider: provider)
        let a = try node("A", in: session)
        provider.enqueue(.tags(.tags([a: ["Travel"]], order: [a])), for: .suggestTags)
        assistant.suggestTags(a)
        await assistant.requestSettled()
        let id = try #require(assistant.tagSuggestions?.suggestions.first?.id)

        assistant.renameTagSuggestion(id, to: "Du lịch")
        assistant.acceptTag(id)

        #expect(tagNames(of: a, in: session) == ["Du lịch"])
    }

    @Test func suggestTagsIsHiddenOnIneligibleDevicesAndExplainedOtherwise() async throws {
        let session = try await open()
        let a = try node("A", in: session)
        let ineligible = try await assistant(for: session, provider: MockAIProvider(), capabilities: .notEligible)
        #expect(!ineligible.service.showsEntryPoints)
        #expect(!ineligible.canRun(.suggestTags, on: a))

        let off = try await assistant(for: session, provider: MockAIProvider(), capabilities: AICapabilities(model: .appleIntelligenceOff))
        #expect(off.service.showsEntryPoints)
        #expect(!off.canRun(.suggestTags, on: a))
    }

    @Test func tagSuggestionsAreDrawnAsAIChips() async throws {
        let session = try await open()
        let provider = MockAIProvider()
        let assistant = try await assistant(for: session, provider: provider)
        let canvas = CanvasModel(session: session, assistant: assistant)
        canvas.setTextSpecs(.designSizes())
        let a = try node("A", in: session)
        provider.enqueue(.tags(.tags([a: ["Travel"]], order: [a])), for: .suggestTags)

        assistant.suggestTags(a)
        await assistant.requestSettled()
        await canvas.layoutSettled()

        let chips = try #require(canvas.scene.topic(a)?.chips)
        #expect(chips.map(\.label) == ["Travel"])
        let suggested = chips.allSatisfy(\.isSuggestion)
        #expect(suggested)
        assistant.discardAll()
        await canvas.layoutSettled()
        #expect(canvas.scene.topic(a)?.chips.isEmpty == true)
    }

    private struct OpenFailed: Error {}

    private struct EverythingUnlocked: ProEntitlements {
        func allows(_ feature: ProFeature) -> Bool { true }
    }

    /// Polls briefly for a change that arrives through the change stream.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
