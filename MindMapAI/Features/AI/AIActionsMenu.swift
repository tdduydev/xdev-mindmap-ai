import Foundation
import MindMapAICore
import MindMapDomain
import SwiftUI

/// The `sparkles` symbol in the AI gradient, the one mark for AI in the app.
struct AISymbol: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Image(systemName: "sparkles")
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Palette.ai(colorScheme: colorScheme, contrast: contrast, reduceTransparency: reduceTransparency))
    }
}

/// The AI actions for a topic, shared by the toolbar menu, the canvas control
/// and the topic context menu. The menu bar has its own copy with shortcuts
/// (`MapCommands`), so the key equivalents are not registered twice.
struct AIActionsMenu: View {
    let assistant: AIAssistant
    /// The topic the actions apply to; the selection when nil.
    var nodeID: NodeID?
    /// Generate Map is about the map, not a topic, so topic menus leave it out.
    var includesGenerateMap = false

    var body: some View {
        if let note = assistant.service.unavailableReason {
            // One line on why AI is not ready, in place of an alert (FR-AI-02).
            Text(note)
        }
        if includesGenerateMap {
            Button("Generate Map…", systemImage: "sparkles") { assistant.requestGenerateMap() }
                .disabled(!assistant.canRun(.generateMap))
            Divider()
        }
        Button("Suggest Subtopics", systemImage: "arrow.turn.down.right") { assistant.expand(nodeID) }
            .disabled(!assistant.canRun(.expandTopic, on: nodeID))
        Button("Brainstorm Ideas…", systemImage: "lightbulb") { assistant.requestBrainstorm(nodeID) }
            .disabled(!assistant.canRun(.brainstorm, on: nodeID))
        Menu("Rewrite Topic", systemImage: "pencil.line") {
            ForEach(RewriteStyle.allCases, id: \.self) { style in
                Button(style.title) { assistant.rewrite(nodeID, style: style) }
            }
        }
        .disabled(!assistant.canRun(.rewrite, on: nodeID))
        Button("Summarize Branch", systemImage: "text.alignleft") { assistant.summarize(nodeID) }
            .disabled(!assistant.canRun(.summarize, on: nodeID))
        Button("Find Missing Topics", systemImage: "questionmark.bubble") { assistant.findMissingTopics(nodeID) }
            .disabled(!assistant.canRun(.findMissingTopics, on: nodeID))
        Button("Suggest Tags", systemImage: "tag") { assistant.suggestTags(nodeID) }
            .disabled(!assistant.canRun(.suggestTags, on: nodeID))
        Button("Suggest Groups", systemImage: "rectangle.dashed") { assistant.suggestGroups(nodeID) }
            .disabled(!assistant.canRun(.suggestGroups, on: nodeID))
        Button("Summarize Boundary", systemImage: "character.cursor.ibeam") { assistant.summarizeBoundary() }
            .disabled(!assistant.canRun(.summarizeBoundary))
    }
}

/// The toolbar's AI menu: a `sparkles` button in the AI gradient.
struct AIToolbarMenu: View {
    let assistant: AIAssistant

    var body: some View {
        Menu {
            AIActionsMenu(assistant: assistant, includesGenerateMap: true)
        } label: {
            Label {
                Text("AI")
            } icon: {
                AISymbol()
            }
        }
        .help(Text("AI"))
        .accessibilityIdentifier(AccessibilityID.ScreenshotAI.menu)
    }
}

extension RewriteStyle {
    var title: String {
        switch self {
        case .shorter: String(localized: "Shorter")
        case .clearer: String(localized: "Clearer")
        case .formal: String(localized: "More Formal")
        case .simpler: String(localized: "Simpler")
        case .technical: String(localized: "More Technical")
        case .vietnamese: String(localized: "In Vietnamese")
        case .english: String(localized: "In English")
        case .japanese: String(localized: "In Japanese")
        }
    }
}

extension AIFeature {
    /// What the progress line says while the request runs.
    var progressTitle: String {
        switch self {
        case .generateMap: String(localized: "Generating map…")
        case .expandTopic: String(localized: "Suggesting subtopics…")
        case .brainstorm: String(localized: "Brainstorming ideas…")
        case .rewrite: String(localized: "Rewriting the title…")
        case .summarize: String(localized: "Summarizing the branch…")
        case .findMissingTopics: String(localized: "Looking for missing topics…")
        case .suggestTags: String(localized: "Suggesting tags…")
        case .suggestGroups: String(localized: "Suggesting groups…")
        case .summarizeBoundary: String(localized: "Summarizing the boundary…")
        }
    }

    /// The heading over a set of suggestions. Missing topics are offered as
    /// possibilities, never as corrections (FR-AI-08).
    var suggestionsTitle: String {
        switch self {
        case .generateMap: String(localized: "Suggested map")
        case .expandTopic: String(localized: "Suggested subtopics")
        case .brainstorm: String(localized: "Ideas")
        case .findMissingTopics: String(localized: "Possible missing topics")
        case .suggestTags: String(localized: "Suggested tags")
        case .suggestGroups: String(localized: "Suggested groups")
        case .summarizeBoundary: String(localized: "Suggested boundary title")
        case .rewrite, .summarize: String(localized: "Suggestions")
        }
    }
}
