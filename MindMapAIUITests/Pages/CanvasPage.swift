import XCTest

/// The canvas of an open map (docs/canvas.md): topics, the floating zoom
/// controls, gestures on topics and on empty canvas. Platform differences
/// (click or tap, context menu by right click or by a hold) stay here.
@MainActor
extension EditorPage {
    func canvasTopic(titled title: String) -> XCUIElement {
        canvasTopics.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// The topic's VoiceOver value, such as "Level 2, 1 subtopic".
    func canvasValue(of title: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        canvasTopic(titled: title).waitToExist(file: file, line: line).value as? String ?? ""
    }

    /// Waits until the topic's value reads `count` subtopics, so a test reads
    /// the tree after the layout pass that follows an edit, not before it.
    func waitForSubtopics(
        of title: String,
        _ count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let topic = canvasTopic(titled: title).waitToExist(file: file, line: line)
        let text = count == 1 ? ", 1 subtopic" : ", \(count) subtopics"
        // A comma or the end follows, so "1 subtopic" does not match "1 subtopics".
        let matches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@ OR value ENDSWITH %@", text + ",", text),
            object: topic
        )
        let result = XCTWaiter().wait(for: [matches], timeout: MindMapApp.timeout)
        XCTAssertEqual(result, .completed, "\(title) reads \"\(topic.value as? String ?? "")\", expected \(count) subtopics", file: file, line: line)
    }

    func waitForSelection(
        _ title: String,
        _ selected: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let topic = canvasTopic(titled: title).waitToExist(file: file, line: line)
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == %@", NSNumber(value: selected)), object: topic)
        let result = XCTWaiter().wait(for: [matches], timeout: MindMapApp.timeout / 3)
        XCTAssertEqual(result, .completed, "\(title) is\(selected ? " not" : "") selected", file: file, line: line)
    }

    /// The title field of a topic being edited in place.
    var canvasTitleField: XCUIElement { canvas.textFields.firstMatch }

    var zoomInButton: XCUIElement { app.buttons[AccessibilityID.Canvas.zoomIn].firstMatch }
    var zoomOutButton: XCUIElement { app.buttons[AccessibilityID.Canvas.zoomOut].firstMatch }
    var zoomToFitButton: XCUIElement { app.buttons[AccessibilityID.Canvas.zoomToFit].firstMatch }
    /// The zoom level button; its value is the scale, such as "100%".
    var zoomLevel: XCUIElement { app.buttons[AccessibilityID.Canvas.actualSize].firstMatch }

    /// The zoom level as a number, 100 for "100%". Digits only, so it reads
    /// the same whatever the language puts around them.
    var zoomPercent: Int {
        Int((zoomLevel.value as? String ?? "").filter(\.isNumber)) ?? 0
    }

    func waitForZoom(_ predicate: @escaping (Int) -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        zoomLevel.waitToExist(file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate(zoomPercent) }, object: nil)
        let result = XCTWaiter().wait(for: [expectation], timeout: MindMapApp.timeout / 3)
        XCTAssertEqual(result, .completed, "\(message); zoom is \(zoomPercent)%", file: file, line: line)
    }

    /// Selects a topic with a click or a tap.
    func selectCanvasTopic(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        canvasTopic(titled: title).waitToExist(file: file, line: line).tapOrClick()
        waitForSelection(title, file: file, line: line)
    }

    /// Opens a topic's title in place with a double click or a double tap.
    @discardableResult
    func beginEditingCanvasTopic(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let topic = canvasTopic(titled: title).waitToExist(file: file, line: line)
        #if os(macOS)
        topic.doubleClick()
        #else
        topic.doubleTap()
        #endif
        return canvasTitleField.waitToExist(file: file, line: line)
    }

    /// Replaces the text of the open title field and commits it with Return.
    func replaceCanvasTitle(_ field: XCUIElement, of title: String, with newTitle: String) {
        #if os(macOS)
        field.typeKey("a", modifierFlags: .command)
        field.typeText(newTitle + "\r")
        #else
        let delete = String(repeating: XCUIKeyboardKey.delete.rawValue, count: title.count + 2)
        field.typeText(delete + newTitle + "\n")
        #endif
    }

    /// Picks `item` from a topic's context menu. Menu items have no
    /// identifier, so they are found by their English title.
    func chooseFromContextMenu(of title: String, _ item: String, file: StaticString = #filePath, line: UInt = #line) {
        let topic = canvasTopic(titled: title).waitToExist(file: file, line: line)
        #if os(macOS)
        topic.rightClick()
        app.menuItems.matching(NSPredicate(format: "title == %@", item)).firstMatch.waitToExist(file: file, line: line).click()
        #else
        topic.press(forDuration: 1)
        app.buttons.matching(NSPredicate(format: "label == %@", item)).firstMatch.waitToExist(file: file, line: line).tap()
        #endif
    }

    /// Drags a topic and drops it on the middle of another, which drops it
    /// inside as the last child (docs/canvas.md, Drag and drop).
    func dragCanvasTopic(_ title: String, onto target: String, file: StaticString = #filePath, line: UInt = #line) {
        let source = canvasTopic(titled: title).waitToExist(file: file, line: line)
        let destination = canvasTopic(titled: target).waitToExist(file: file, line: line)
        drag(from: source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
             to: destination.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
    }

    /// A press shorter than the context menu's hold (iOS) and the selection
    /// rectangle's (`CanvasMetrics.marqueeHoldDuration`), then a slow drag, so
    /// every move reaches the drag gesture.
    func drag(from start: XCUICoordinate, to end: XCUICoordinate) {
        #if os(macOS)
        start.click(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        #else
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        #endif
    }

    /// A point on the canvas well away from every topic and the floating
    /// controls, for panning.
    /// `margin` is the room kept around each topic; a dense map needs less.
    func emptyCanvasPoint(margin: CGFloat = 40, file: StaticString = #filePath, line: UInt = #line) -> XCUICoordinate {
        let area = canvas.waitToExist(file: file, line: line).frame
        let topics = canvasTopics.allElementsBoundByIndex.map { $0.frame.insetBy(dx: -margin, dy: -margin) }
        let controls = zoomLevel.frame.insetBy(dx: -200, dy: -60)
        for y in stride(from: 0.15, through: 0.85, by: 0.05) {
            for x in stride(from: 0.1, through: 0.9, by: 0.05) {
                let point = CGPoint(x: area.minX + area.width * x, y: area.minY + area.height * y)
                if !controls.contains(point), !topics.contains(where: { $0.contains(point) }) {
                    return canvas.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
                }
            }
        }
        XCTFail("no empty spot on the canvas", file: file, line: line)
        return canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.15))
    }
}
