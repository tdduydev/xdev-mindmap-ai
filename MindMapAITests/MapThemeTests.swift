import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import SwiftUI
import Testing

@Suite("Map theme")
struct MapThemeTests {
    let repository: SwiftDataMapRepository

    init() throws {
        repository = try PersistenceController.makeRepository(at: .inMemory)
    }

    private func open(_ graph: GraphState) async throws -> EditorSession {
        try await repository.create(graph)
        guard case .ready(let session) = await EditorSession.open(mapID: graph.map.id, repository: repository, onMapChange: { _ in }) else {
            throw OpenFailed()
        }
        return session
    }

    // MARK: Command through the session

    @Test func changeThemeIsOneNamedUndoStep() async throws {
        let session = try await open(.newMap(title: "Plan"))
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager

        undoManager.beginUndoGrouping()
        session.changeTheme(to: .graphite)
        undoManager.endUndoGrouping()
        #expect(session.map.theme == .graphite)
        #expect(undoManager.undoActionName == String(localized: "Change Theme"))

        undoManager.undo()
        #expect(session.map.theme == .standard)
        #expect(undoManager.redoActionName == String(localized: "Change Theme"))

        undoManager.redo()
        #expect(session.map.theme == .graphite)

        await session.flush()
        let stored = try #require(try await repository.loadGraph(for: session.map.id))
        #expect(stored.map.theme == .graphite)
    }

    @Test func choosingTheCurrentThemeLeavesNoUndoStep() async throws {
        let session = try await open(.newMap(title: "Plan"))
        let undoManager = UndoManager()
        session.undoManager = undoManager

        session.changeTheme(to: .standard)

        #expect(!undoManager.canUndo)
    }

    /// FR-THM-03: the theme touches colour only, so nothing about the topics changes.
    @Test func changingThemeKeepsTopicsAndSelection() async throws {
        let session = try await open(.newMap(title: "Plan"))
        session.addChild()
        let selected = session.selection
        let nodes = session.engine.state.nodes

        session.changeTheme(to: .xdevBlue)

        #expect(session.engine.state.nodes == nodes)
        #expect(session.selection == selected)
    }

    // MARK: Pro (FR-THM-02)

    @Test func aProThemeWithoutProOpensThePaywallAndKeepsTheMap() async throws {
        let session = try await open(.newMap(title: "Plan"))
        let undoManager = UndoManager()
        session.undoManager = undoManager

        session.chooseTheme(.graphite, entitlements: Entitlements(isPro: false))

        #expect(session.map.theme == .standard)
        #expect(!undoManager.canUndo)
        #expect(session.pendingThemeChoice?.feature == .extraThemes)
    }

    @Test func standardNeverAsksForPro() async throws {
        let session = try await open(.newMap(title: "Plan", theme: .xdevBlue))

        session.chooseTheme(.standard, entitlements: Entitlements(isPro: false))

        #expect(session.map.theme == .standard)
        #expect(session.pendingThemeChoice == nil)
    }

    /// Only the choice is locked: a map made with Pro keeps its theme without it.
    @Test func aMapWithAProThemeKeepsItWithoutPro() async throws {
        let session = try await open(.newMap(title: "Plan", theme: .graphite))

        session.chooseTheme(.graphite, entitlements: Entitlements(isPro: false))

        #expect(session.map.theme == .graphite)
    }

    /// Unlocking Pro on the paywall applies the theme as one "Change Theme" step.
    @Test func theThemeChangesOnceProIsUnlocked() async throws {
        let session = try await open(.newMap(title: "Plan"))
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        session.undoManager = undoManager
        session.chooseTheme(.xdevBlue, entitlements: Entitlements(isPro: false))
        let pending = try #require(session.pendingThemeChoice)

        undoManager.beginUndoGrouping()
        pending.apply()
        undoManager.endUndoGrouping()
        #expect(session.map.theme == .xdevBlue)
        #expect(undoManager.undoActionName == String(localized: "Change Theme"))

        undoManager.undo()
        #expect(session.map.theme == .standard)
        undoManager.redo()
        #expect(session.map.theme == .xdevBlue)
    }

    @Test func withProAThemeChangesStraightAway() async throws {
        let session = try await open(.newMap(title: "Plan"))

        session.chooseTheme(.graphite, entitlements: Entitlements(isPro: true))

        #expect(session.map.theme == .graphite)
        #expect(session.pendingThemeChoice == nil)
    }

    // MARK: Resolving colours

    @Test func storedThemesResolveToTheirPalettes() {
        #expect(MapTheme(MindMapTheme.standard) == .standard)
        #expect(MapTheme(MindMapTheme.xdevBlue) == .xdevBlue)
        #expect(MapTheme(MindMapTheme.graphite) == .graphite)
        // A value from a newer version reaches the design system as Standard.
        #expect(MapTheme(MindMapTheme(storedValue: "aurora")) == .standard)
    }

    /// Values from the Themes table of docs/design-system.md.
    @Test func singleColourThemesUseTheDocumentedLines() {
        for branch in 0..<8 {
            #expect(MapTheme.xdevBlue.branch(branch, in: .light).line == SRGBColor(hex: 0x0B6CF5))
            #expect(MapTheme.xdevBlue.branch(branch, in: .dark).line == SRGBColor(hex: 0x4AAEFF))
            #expect(MapTheme.graphite.branch(branch, in: .light).line == SRGBColor(hex: 0x5B6885))
            #expect(MapTheme.graphite.branch(branch, in: .dark).line == SRGBColor(hex: 0x9DAAC7))
        }
    }

    /// Only the branch colours follow the theme; the central topic, text, shape,
    /// font and edge widths stay those of Standard.
    @Test(arguments: [MindMapTheme.xdevBlue, .graphite])
    func themeChangesOnlyBranchColours(_ stored: MindMapTheme) {
        let theme = MapTheme(stored)
        let appearances: [(ColorScheme, ColorSchemeContrast)] = [(.light, .standard), (.dark, .standard), (.light, .increased), (.dark, .increased)]
        for (scheme, contrast) in appearances {
            let variant = ColorVariant(colorScheme: scheme, contrast: contrast)
            for level in 0...3 {
                let standard = TopicStyle.resolve(level: level, branch: 2, theme: .standard, colorScheme: scheme, contrast: contrast)
                let themed = TopicStyle.resolve(level: level, branch: 2, theme: theme, colorScheme: scheme, contrast: contrast)
                #expect(themed.kind == standard.kind)
                #expect(themed.text == standard.text)
                #expect(themed.box == standard.box)
                #expect(themed.strokeWidth == standard.strokeWidth)
                #expect(themed.edgeWidth == standard.edgeWidth)
                #expect(themed.textColor == standard.textColor)
                if level == 0 {
                    #expect(themed.fill == standard.fill)
                } else {
                    #expect(themed.edgeColor == theme.branch(2, in: variant).line)
                }
            }
        }
    }

    // MARK: Canvas

    @Test func canvasRedrawsInTheNewTheme() async throws {
        let session = try await open(.newMap(title: "Plan"))
        let canvas = CanvasModel(session: session)
        canvas.setViewSize(CGSize(width: 1000, height: 700))
        canvas.setTextSpecs(.designSizes())
        session.addChild()
        let childID = try #require(session.selection)
        await canvas.layoutSettled()
        let topic = try #require(canvas.scene.topic(childID))
        let before = canvas.style(for: topic, colorScheme: .light, contrast: .standard)

        session.changeTheme(to: .graphite)
        await canvas.layoutSettled()

        let after = canvas.style(for: try #require(canvas.scene.topic(childID)), colorScheme: .light, contrast: .standard)
        #expect(before.edgeColor == MapTheme.standard.branch(0, in: .light).line)
        #expect(after.edgeColor == MapTheme.graphite.branch(0, in: .light).line)
    }

    private struct OpenFailed: Error {}
}

private struct Entitlements: ProEntitlements {
    let isPro: Bool
    func allows(_ feature: ProFeature) -> Bool { isPro }
}
