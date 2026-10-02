import CoreGraphics
import Foundation
@testable import MindMapAI
import MindMapAICore
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import MindMapTestSupport
import Testing

/// The AI tasks end to end without a model: `MockAIProvider` answers, a real
/// session on an in-memory store applies what is accepted.
@Suite("AI assistant")
struct AIAssistantTests {
    let repository: SwiftDataMapRepository
    let provider = MockAIProvider()
    let defaults: UserDefaults

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
        defaults = try #require(UserDefaults(suiteName: "AIAssistantTests.\(UUID().uuidString)"))
        defaults.set(true, forKey: AIAssistant.privacyNoticeKey)
    }

    private func open(
        _ outline: [String] = ["Trip", "Flights", "Hotels"],
        capabilities: AICapabilities = .readyForTesting,
        entitlements: any ProEntitlements = AllFeaturesUnlocked()
    ) async throws -> AIAssistant {
        var graph = GraphState.newMap(title: outline[0])
        let rootID = try #require(graph.map.rootNodeID)
        var engine = try GraphEngine(state: graph)
        for title in outline.dropFirst() {
            try engine.execute(AddNodeCommand(.child(of: rootID), title: title))
        }
        graph = engine.state
        try await repository.create(graph)
        guard case .ready(let session) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        provider.setCapabilities(capabilities)
        let service = AIService(provider: { [provider] in provider }, entitlements: entitlements, defaults: defaults)
        await service.refresh()
        return AIAssistant(session: session, service: service, defaults: defaults, locale: Locale(identifier: "en_US"))
    }

    private func childTitles(of id: NodeID?, in session: EditorSession) -> [String] {
        id.map { session.engine.state.children(of: $0).map(\.title) } ?? []
    }

    // MARK: Suggestions

    @Test func suggestionsStayOutOfTheMapUntilAccepted() async throws {
        let assistant = try await open()
        let session = assistant.session
        let rootID = try #require(session.rootID)
        provider.enqueue(.stream([
            .suggestions(["Fo"], under: rootID),
            .suggestions(["Food", "Weather"], under: rootID),
        ]), for: .expandTopic)

        assistant.expand(rootID)
        #expect(assistant.isWorking)
        await assistant.requestSettled()

        #expect(!assistant.isWorking)
        #expect(assistant.suggestions?.topics.map(\.title) == ["Food", "Weather"])
        #expect(childTitles(of: rootID, in: session) == ["Flights", "Hotels"])
        #expect(!session.canUndo, "suggestions are not a step in the map's history")
    }

    @Test func acceptAllIsOneUndoStepOfAITopics() async throws {
        let assistant = try await open()
        let session = assistant.session
        let rootID = try #require(session.rootID)
        provider.enqueue(.proposal(.suggestions(["Food", "Weather"], under: rootID)), for: .expandTopic)
        assistant.expand(rootID)
        await assistant.requestSettled()

        assistant.acceptAll()

        #expect(childTitles(of: rootID, in: session) == ["Flights", "Hotels", "Food", "Weather"])
        #expect(session.engine.state.children(of: rootID).suffix(2).allSatisfy { $0.metadata.origin == .ai })
        #expect(assistant.suggestions == nil)

        session.undo()
        #expect(childTitles(of: rootID, in: session) == ["Flights", "Hotels"])
        session.redo()
        #expect(childTitles(of: rootID, in: session) == ["Flights", "Hotels", "Food", "Weather"])
    }

    @Test func acceptOneDiscardAnotherAndEditBeforeAccepting() async throws {
        let assistant = try await open()
        let session = assistant.session
        let rootID = try #require(session.rootID)
        let flightsID = try #require(session.engine.state.children(of: rootID).first?.id)
        provider.enqueue(.proposal(.suggestions(["Window seat", "Lounge", "Visa"], under: flightsID, feature: .brainstorm)), for: .brainstorm)
        assistant.brainstorm(flightsID, question: "")
        await assistant.requestSettled()

        assistant.renameSuggestion("s2", to: "Airport lounge")
        assistant.discard("s3")
        assistant.accept("s2")

        #expect(childTitles(of: flightsID, in: session) == ["Airport lounge"])
        #expect(assistant.suggestions?.topics.map(\.title) == ["Window seat"])
        assistant.discardAll()
        #expect(assistant.suggestions == nil)
        #expect(childTitles(of: flightsID, in: session) == ["Airport lounge"])
    }

    @Test func aGeneratedMapNamesAnEmptyMapInTheSameStep() async throws {
        let assistant = try await open(["Untitled Map"])
        let session = assistant.session
        let rootID = try #require(session.rootID)
        provider.enqueue(.proposal(AIProposal(feature: .generateMap, anchor: .root, suggestedMapTitle: "Garden", topics: [
            ProposedTopic(temporaryID: "t1", title: "Vegetables"),
            ProposedTopic(temporaryID: "t2", parentTemporaryID: "t1", title: "Tomatoes"),
        ])), for: .generateMap)

        assistant.generateMap(description: "A vegetable garden")
        await assistant.requestSettled()
        assistant.acceptAll()

        #expect(session.map.title == "Garden")
        #expect(session.engine.state.node(rootID)?.title == "Garden")
        #expect(childTitles(of: rootID, in: session) == ["Vegetables"])

        session.undo()
        #expect(session.map.title == "Untitled Map")
        #expect(childTitles(of: rootID, in: session).isEmpty)
        session.redo()
        #expect(session.map.title == "Garden")
    }

    // MARK: Background work

    @Test func theMapStaysEditableWhileWaitingAndCancelStops() async throws {
        let assistant = try await open()
        let session = assistant.session
        provider.enqueue(.hang, for: .expandTopic)

        assistant.expand()
        session.addChild()
        #expect(assistant.isWorking)
        #expect(session.canUndo, "editing goes on while the model answers")

        assistant.cancel()
        await assistant.requestSettled()
        #expect(!assistant.isWorking)
        #expect(assistant.suggestions == nil)
        #expect(assistant.failure == nil, "cancelling is not an error")
    }

    @Test func guardrailRefusalSuggestsRewordingTheRequest() async throws {
        let assistant = try await open()
        let rootID = try #require(assistant.session.rootID)
        provider.enqueue(.failure(.guardrailViolation), for: .brainstorm)

        assistant.brainstorm(rootID, question: "Something blocked")
        await assistant.requestSettled()

        #expect(assistant.failure == .rephrase)
        #expect(assistant.suggestions == nil)
        #expect(assistant.canEditLastRequest)
        assistant.editLastRequest()
        #expect(assistant.sheet == .brainstorm(rootID, draft: "Something blocked"))
    }

    @Test func errorsMapToAWayForward() {
        #expect(AIFailure(AIError.contextSizeExceeded) == .smallerBranch)
        #expect(AIFailure(AIError.rateLimited) == .busy)
        #expect(AIFailure(AIError.refusal) == .rephrase)
        #expect(AIFailure(AIError.invalidResponse(.empty)) == .unusable)
        #expect(AIFailure(ProposalError.anchorNotFound) == .topicGone)
    }

    // MARK: Rewrite and summary

    @Test func rewriteChangesTheTitleOnlyWhenChosen() async throws {
        let assistant = try await open()
        let session = assistant.session
        let rootID = try #require(session.rootID)
        let hotelsID = try #require(session.engine.state.children(of: rootID).last?.id)
        provider.enqueue(.rewrite(AIRewrite(nodeID: hotelsID, originalTitle: "Hotels", suggestions: ["Places to stay"])), for: .rewrite)

        assistant.rewrite(hotelsID, style: .clearer)
        await assistant.requestSettled()
        guard case .rewrite(let rewrite) = assistant.sheet else {
            Issue.record("No rewrite sheet")
            return
        }
        #expect(session.engine.state.node(hotelsID)?.title == "Hotels")

        assistant.applyRewrite("Places to stay", from: rewrite)
        #expect(session.engine.state.node(hotelsID)?.title == "Places to stay")
        session.undo()
        #expect(session.engine.state.node(hotelsID)?.title == "Hotels")
        session.redo()
        #expect(session.engine.state.node(hotelsID)?.title == "Places to stay")
    }

    @Test func summaryGoesIntoTheNoteOnlyWhenChosen() async throws {
        let assistant = try await open()
        let session = assistant.session
        let rootID = try #require(session.rootID)
        provider.enqueue(.summary(AISummary(nodeID: rootID, text: "Flights and hotels.")), for: .summarize)

        assistant.summarize(rootID)
        await assistant.requestSettled()
        guard case .summary(let summary) = assistant.sheet else {
            Issue.record("No summary sheet")
            return
        }
        #expect(session.engine.state.node(rootID)?.note == nil, "reading a summary changes nothing")

        assistant.addSummaryToNote(summary)
        #expect(session.engine.state.node(rootID)?.note == "Flights and hotels.")
        session.undo()
        #expect(session.engine.state.node(rootID)?.note == nil)
        session.redo()
        #expect(session.engine.state.node(rootID)?.note == "Flights and hotels.")
    }

    // MARK: Availability and gates

    @Test func entryPointsFollowTheModelState() async throws {
        let off = try await open(capabilities: AICapabilities(model: .appleIntelligenceOff))
        #expect(off.service.showsEntryPoints)
        #expect(!off.canRun(.expandTopic))
        #expect(AIAvailabilityText.explanation(for: off.modelAvailability) != nil)

        let downloading = try await open(capabilities: AICapabilities(model: .modelDownloading))
        #expect(downloading.availability(for: .summarize) == .modelDownloading)
        #expect(!downloading.canRun(.summarize))

        let ineligible = try await open(capabilities: .notEligible)
        #expect(!ineligible.service.showsEntryPoints)
    }

    @Test func useAIFeaturesIsOnByDefaultAndRemembered() async throws {
        let assistant = try await open()
        #expect(assistant.service.isEnabled)
        #expect(defaults.object(forKey: AIService.enabledKey) == nil, "the default is not written")

        assistant.service.isEnabled = false
        #expect(defaults.bool(forKey: AIService.enabledKey) == false)
        #expect(defaults.object(forKey: AIService.enabledKey) != nil)
        let relaunched = AIService(provider: { [provider] in provider }, entitlements: AllFeaturesUnlocked(), defaults: defaults)
        #expect(!relaunched.isEnabled)
    }

    @Test func turningAIOffTakesItOutOfTheEditorAtOnce() async throws {
        let assistant = try await open()
        #expect(assistant.service.showsControls)
        #expect(assistant.service.unavailableReason == nil)

        assistant.service.isEnabled = false

        #expect(assistant.service.showsEntryPoints, "the menu bar keeps its AI menu")
        #expect(!assistant.service.showsControls, "toolbar, canvas and topic menus hide AI")
        #expect(assistant.service.unavailableReason == AIAvailabilityText.turnedOff)
        for feature in AIFeature.allCases {
            #expect(!assistant.canRun(feature), "\(feature) is disabled")
        }
        // A request asked for while off does nothing.
        assistant.expand()
        #expect(!assistant.isWorking)
        #expect(assistant.suggestions == nil)

        assistant.service.isEnabled = true
        #expect(assistant.canRun(.expandTopic))
    }

    @Test func suggestionsOnTheCanvasStayWhenAIIsTurnedOff() async throws {
        let assistant = try await open()
        let session = assistant.session
        let rootID = try #require(session.rootID)
        provider.enqueue(.proposal(.suggestions(["Food"], under: rootID)), for: .expandTopic)
        assistant.expand(rootID)
        await assistant.requestSettled()

        assistant.service.isEnabled = false

        #expect(assistant.suggestions?.topics.map(\.title) == ["Food"])
        #expect(assistant.canAcceptSuggestions)
        assistant.acceptAll()
        #expect(childTitles(of: rootID, in: session) == ["Flights", "Hotels", "Food"])
        session.undo()
        #expect(childTitles(of: rootID, in: session) == ["Flights", "Hotels"])
        session.redo()
        #expect(childTitles(of: rootID, in: session) == ["Flights", "Hotels", "Food"])
    }

    @Test func theFirstRequestShowsThePrivacyNoticeFirst() async throws {
        let assistant = try await open()
        defaults.removeObject(forKey: AIAssistant.privacyNoticeKey)
        let rootID = try #require(assistant.session.rootID)
        provider.enqueue(.proposal(.suggestions(["Food"], under: rootID)), for: .expandTopic)

        assistant.expand(rootID)
        #expect(assistant.sheet == .privacyNotice)
        #expect(assistant.holdsDeleteKey, "an open sheet keeps Delete for its own fields")
        #expect(provider.requests.isEmpty, "nothing is sent before the notice is read")

        assistant.acknowledgePrivacyNotice()
        await assistant.requestSettled()
        #expect(assistant.suggestions?.topics.map(\.title) == ["Food"])
        #expect(defaults.bool(forKey: AIAssistant.privacyNoticeKey))
    }

    @Test func proFeaturesAskTheEntitlementHook() async throws {
        let assistant = try await open(entitlements: NothingUnlocked())
        let rootID = try #require(assistant.session.rootID)

        assistant.findMissingTopics(rootID)
        assistant.summarize(rootID)

        #expect(assistant.failure == .requiresPro)
        #expect(provider.requests.isEmpty)
    }

    // MARK: Canvas

    @Test func theCanvasDrawsSuggestionsApartFromTopics() async throws {
        let assistant = try await open()
        let session = assistant.session
        let rootID = try #require(session.rootID)
        let canvas = CanvasModel(session: session, assistant: assistant)
        canvas.setViewSize(CGSize(width: 1000, height: 700))
        canvas.setTextSpecs(.designSizes())
        await canvas.layoutSettled()
        provider.enqueue(.proposal(.suggestions(["Food"], under: rootID)), for: .expandTopic)

        assistant.expand(rootID)
        await assistant.requestSettled()
        await canvas.layoutSettled()

        let suggestion = try #require(canvas.scene.topics.first { $0.isSuggestion })
        #expect(suggestion.title == "Food")
        #expect(session.engine.state.node(suggestion.id) == nil)

        canvas.select(suggestion.id)
        #expect(assistant.selectedSuggestion == "s1")
        #expect(session.selection == rootID, "selecting a suggestion leaves the map's selection alone")
        // Delete then discards the suggestion, so it cannot be Delete Topic's key.
        #expect(assistant.holdsDeleteKey)

        canvas.acceptSuggestion(suggestion.id)
        await canvas.layoutSettled()
        #expect(canvas.scene.topics.allSatisfy { !$0.isSuggestion })
        #expect(childTitles(of: rootID, in: session) == ["Flights", "Hotels", "Food"])
    }

    private struct OpenFailed: Error {}
}

private struct AllFeaturesUnlocked: ProEntitlements {
    func allows(_ feature: ProFeature) -> Bool { true }
}

private struct NothingUnlocked: ProEntitlements {
    func allows(_ feature: ProFeature) -> Bool { false }
}
