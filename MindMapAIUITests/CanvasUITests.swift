import XCTest
#if os(macOS)
import AppKit
#endif

/// The canvas (MM-24, NFR-TEST-02): select, edit a title in place, add and
/// delete, zoom, pan, drag to a new parent and the refused drop into the
/// dragged branch (AT-03), multi-selection, copy and paste as Markdown, and
/// switching to the outline. Context menu items are found by their English
/// titles, so the suite runs in English.
final class CanvasUITests: XCTestCase {
    /// Product Launch: the central topic, Research (holding Interviews), Design and Marketing.
    private static let planTopicCount = 5

    @MainActor
    private func openPlan() -> EditorPage {
        let editor = MindMapApp.launch(fixture: .sample).library.show()
            .open(UITestFixture.Title.plan)
            .show(.canvas)
        editor.canvasTopics.waitForCount(Self.planTopicCount)
        return editor
    }

    // MARK: Select and edit

    @MainActor
    func testTapSelectsOneTopic() {
        let editor = openPlan()
        editor.selectCanvasTopic(UITestFixture.Title.design)
        editor.selectCanvasTopic(UITestFixture.Title.marketing)
        editor.waitForSelection(UITestFixture.Title.design, false)
    }

    @MainActor
    func testEditTitleInPlaceReturnCommitsEscapeCancels() {
        let editor = openPlan()

        let field = editor.beginEditingCanvasTopic(UITestFixture.Title.design)
        editor.replaceCanvasTitle(field, of: UITestFixture.Title.design, with: "Prototype")
        editor.canvasTopic(titled: "Prototype").waitToExist()
        XCTAssertFalse(editor.canvasTitleField.exists, "Return left the title open")

        editor.undoButton.tapOrClick()
        editor.canvasTopic(titled: UITestFixture.Title.design).waitToExist()
        editor.redoButton.tapOrClick()
        editor.canvasTopic(titled: "Prototype").waitToExist()

        let marketing = editor.beginEditingCanvasTopic(UITestFixture.Title.marketing)
        marketing.typeText(" plan")
        #if os(iOS)
        // On the iOS Simulator the Esc key never reaches the title field's
        // onKeyPress (MM-24 finding); not strict, so a fix passes too.
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("Esc does not cancel a title edit on iOS", options: options) {
            cancelWithEscape(marketing, in: editor)
        }
        #else
        cancelWithEscape(marketing, in: editor)
        #endif
    }

    @MainActor
    private func cancelWithEscape(_ field: XCUIElement, in editor: EditorPage, file: StaticString = #filePath, line: UInt = #line) {
        field.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(editor.canvasTitleField.waitForNonExistence(timeout: MindMapApp.timeout / 3), "Esc left the title open", file: file, line: line)
        XCTAssertTrue(editor.canvasTopic(titled: UITestFixture.Title.marketing).exists, "Esc kept the typed title", file: file, line: line)
    }

    @MainActor
    func testAddAndDeleteTopicUndoRedo() {
        let editor = openPlan()
        editor.selectCanvasTopic(UITestFixture.Title.design)

        // A new topic opens its title for typing (FR-CNV-05).
        editor.tap(.addChild)
        editor.canvasTitleField.waitToExist().typeText("Mockups\n")
        XCTAssertFalse(editor.canvasTitleField.waitForExistence(timeout: 3), "Return after a new topic opened another")
        editor.canvasTopics.waitForCount(Self.planTopicCount + 1)
        editor.waitForSubtopics(of: UITestFixture.Title.design, 1)

        // The new topic stays selected. It is not tapped: on a selected topic
        // the + of Add Sibling Topic covers the middle of a one-line card.
        editor.waitForSelection("Mockups")
        editor.tap(.delete)
        editor.canvasTopics.waitForCount(Self.planTopicCount)
        editor.undoButton.tapOrClick()
        editor.canvasTopic(titled: "Mockups").waitToExist()
        editor.redoButton.tapOrClick()
        editor.canvasTopics.waitForCount(Self.planTopicCount)
    }

    // MARK: Zoom and pan

    @MainActor
    func testZoomShortcutsAndZoomToFit() {
        let editor = openPlan()
        // ⌘0 first: the first view is fitted again while the layout settles,
        // so a zoom read before any key is not a fixed starting point.
        editor.zoomLevel.waitToExist()
        editor.app.typeKey("0", modifierFlags: .command)
        editor.waitForZoom({ $0 == 100 }, "⌘0 did not go to actual size")

        editor.app.typeKey("-", modifierFlags: .command)
        editor.waitForZoom({ $0 < 100 }, "⌘− did not zoom out")
        editor.app.typeKey("+", modifierFlags: .command)
        editor.waitForZoom({ $0 == 100 }, "⌘+ did not zoom back in")
        editor.app.typeKey("+", modifierFlags: .command)
        editor.waitForZoom({ $0 > 100 }, "⌘+ did not zoom in")
        editor.app.typeKey("0", modifierFlags: .command)
        editor.waitForZoom({ $0 == 100 }, "⌘0 did not go back to actual size")

        // The floating controls do the same as the menu (FR-CNV-08).
        editor.zoomInButton.tapOrClick()
        editor.waitForZoom({ $0 > 100 }, "Zoom In did not zoom in")
        editor.zoomToFitButton.tapOrClick()
        // A small map fits at 100% or less.
        editor.waitForZoom({ $0 <= 100 }, "Zoom to Fit did not zoom out")
        for title in [UITestFixture.Title.plan, UITestFixture.Title.interviews, UITestFixture.Title.marketing] {
            let topic = editor.canvasTopic(titled: title).waitToExist()
            XCTAssertTrue(editor.canvas.frame.contains(topic.frame), "Zoom to Fit left \(title) outside the canvas")
        }
    }

    @MainActor
    func testDragOnEmptyCanvasPans() {
        let editor = openPlan()
        let design = editor.canvasTopic(titled: UITestFixture.Title.design).waitToExist()
        let before = design.frame
        let zoom = editor.zoomPercent

        let start = editor.emptyCanvasPoint()
        editor.drag(from: start, to: start.withOffset(CGVector(dx: -120, dy: 80)))

        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(design.frame.midX - (before.midX - 120)) < 30 && abs(design.frame.midY - (before.midY + 80)) < 30
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: MindMapApp.timeout / 3), .completed,
                       "Design moved from \(before) to \(design.frame), expected about (-120, +80)")
        XCTAssertEqual(editor.zoomPercent, zoom, "panning changed the zoom")
        // A pan is not an edit.
        XCTAssertFalse(editor.undoButton.isEnabled)
    }

    // MARK: Drag and drop (AT-03)

    @MainActor
    func testDragTopicOntoAnotherMakesItTheParent() {
        let editor = openPlan()
        editor.dragCanvasTopic(UITestFixture.Title.interviews, onto: UITestFixture.Title.design)

        editor.waitForSubtopics(of: UITestFixture.Title.design, 1)
        editor.waitForSubtopics(of: UITestFixture.Title.research, 0)

        // One undo step puts it back, redo moves it again.
        editor.undoButton.tapOrClick()
        editor.waitForSubtopics(of: UITestFixture.Title.research, 1)
        editor.waitForSubtopics(of: UITestFixture.Title.design, 0)
        editor.redoButton.tapOrClick()
        editor.waitForSubtopics(of: UITestFixture.Title.design, 1)
    }

    @MainActor
    func testDropIntoOwnBranchIsRefused() {
        let editor = openPlan()
        editor.dragCanvasTopic(UITestFixture.Title.research, onto: UITestFixture.Title.interviews)

        // Nothing moved and nothing was recorded for Undo.
        editor.waitForSubtopics(of: UITestFixture.Title.research, 1)
        editor.waitForSubtopics(of: UITestFixture.Title.interviews, 0)
        XCTAssertFalse(editor.undoButton.isEnabled, "a refused drop left an undo step")
    }

    // MARK: Selection and clipboard

    @MainActor
    func testDeleteSeveralTopicsIsOneUndoStep() {
        let editor = openPlan()
        editor.selectCanvasTopic(UITestFixture.Title.design)
        editor.chooseFromContextMenu(of: UITestFixture.Title.marketing, "Add to Selection")
        editor.waitForSelection(UITestFixture.Title.design)
        editor.waitForSelection(UITestFixture.Title.marketing)

        editor.tap(.delete)
        editor.canvasTopics.waitForCount(Self.planTopicCount - 2)
        editor.undoButton.tapOrClick()
        editor.canvasTopics.waitForCount(Self.planTopicCount)
        editor.canvasTopic(titled: UITestFixture.Title.design).waitToExist()
        editor.canvasTopic(titled: UITestFixture.Title.marketing).waitToExist()
        // One step: a second Undo would have nothing of the delete left.
        XCTAssertFalse(editor.undoButton.isEnabled, "the delete took more than one undo step")
    }

    @MainActor
    func testCopyAndPasteBranchAsMarkdown() {
        let editor = openPlan()
        #if os(macOS)
        // The Mac's clipboard is the person's; put it back afterwards.
        let previous = NSPasteboard.general.string(forType: .string)
        defer {
            NSPasteboard.general.clearContents()
            if let previous { NSPasteboard.general.setString(previous, forType: .string) }
        }
        #endif
        editor.selectCanvasTopic(UITestFixture.Title.research)
        editor.chooseFromContextMenu(of: UITestFixture.Title.research, "Copy")
        #if os(macOS)
        // The runner can read the Mac's clipboard; on iOS reading another
        // app's clipboard would ask for permission, so the paste checks it.
        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            "- \(UITestFixture.Title.research)\n  - \(UITestFixture.Title.interviews)"
        )
        #endif

        editor.chooseFromContextMenu(of: UITestFixture.Title.marketing, "Paste")
        editor.canvasTopics.waitForCount(Self.planTopicCount + 2)
        editor.waitForSubtopics(of: UITestFixture.Title.marketing, 1)
        XCTAssertEqual(editor.canvasTopics.matching(NSPredicate(format: "label == %@", UITestFixture.Title.interviews)).count, 2)

        editor.undoButton.tapOrClick()
        editor.canvasTopics.waitForCount(Self.planTopicCount)
        editor.redoButton.tapOrClick()
        editor.canvasTopics.waitForCount(Self.planTopicCount + 2)
    }

    @MainActor
    func testSwitchingToOutlineAndBackKeepsSelection() {
        let editor = openPlan()
        editor.selectCanvasTopic(UITestFixture.Title.design)

        editor.show(.outline)
        editor.outlineTopics.waitForCount(Self.planTopicCount)
        editor.show(.canvas)
        editor.canvasTopics.waitForCount(Self.planTopicCount)
        editor.waitForSelection(UITestFixture.Title.design)
        editor.waitForSelection(UITestFixture.Title.marketing, false)
    }

    // MARK: A large map (AT-02)

    /// Opening the 1,000-topic map, timed with XCTMetric. The numbers are
    /// recorded in the result bundle, not asserted (docs/testing.md).
    @MainActor
    func testLargeMapOpens() {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTClockMetric()], options: options) {
            let library = MindMapApp.launch(fixture: .large).library.show()
            let row = library.map(titled: UITestFixture.Title.large).waitToExist()
            let editor = EditorPage(app: library.app)
            startMeasuring()
            row.tapOrClick()
            editor.canvas.waitToExist()
            editor.canvasTopic(titled: UITestFixture.Title.large).waitToExist()
            stopMeasuring()
            editor.app.terminate()
        }
    }

    /// Panning across the 1,000-topic map: topics keep being drawn as new
    /// ones come into view. Timed, not asserted.
    @MainActor
    func testLargeMapPans() {
        let library = MindMapApp.launch(fixture: .large).library.show()
        let editor = library.open(UITestFixture.Title.large).show(.canvas)
        editor.canvasTopic(titled: UITestFixture.Title.large).waitToExist()
        editor.zoomLevel.waitToExist().tapOrClick()
        editor.waitForZoom({ $0 == 100 }, "Actual Size did not go to 100%")

        // Up, then back down from where the empty spot went, so every pan
        // starts on empty canvas; finding it among hundreds of topics is not timed.
        let start = editor.emptyCanvasPoint(margin: 4)
        let raised = start.withOffset(CGVector(dx: 0, dy: -300))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric()], options: options) {
            for (from, to) in [(start, raised), (raised, start)] {
                editor.drag(from: from, to: to)
                XCTAssertTrue(editor.canvasTopics.firstMatch.waitForExistence(timeout: MindMapApp.timeout), "no topic in view after a pan")
            }
        }
    }
}
