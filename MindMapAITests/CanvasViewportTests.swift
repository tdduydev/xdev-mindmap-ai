import CoreGraphics
@testable import MindMapAI
import Testing

@Suite("Canvas viewport")
struct CanvasViewportTests {
    private let limits: ClosedRange<CGFloat> = 0.1...4

    private func viewport(scale: CGFloat = 1, offset: CGPoint = CGPoint(x: 400, y: 300)) -> CanvasViewport {
        CanvasViewport(scale: scale, offset: offset, size: CGSize(width: 800, height: 600))
    }

    @Test func mapsBetweenCanvasAndView() {
        let camera = viewport(scale: 2, offset: CGPoint(x: 100, y: 50))

        #expect(camera.toView(CGPoint(x: 10, y: 20)) == CGPoint(x: 120, y: 90))
        #expect(camera.toCanvas(CGPoint(x: 120, y: 90)) == CGPoint(x: 10, y: 20))
        #expect(camera.visibleRect == CGRect(x: -50, y: -25, width: 400, height: 300))
    }

    @Test func zoomKeepsThePointUnderTheAnchor() {
        var camera = viewport()
        let anchor = CGPoint(x: 650, y: 120)
        let before = camera.toCanvas(anchor)

        camera.zoom(to: 2.5, anchor: anchor, limits: limits)

        #expect(camera.scale == 2.5)
        let after = camera.toCanvas(anchor)
        #expect(abs(after.x - before.x) < 1e-9)
        #expect(abs(after.y - before.y) < 1e-9)
    }

    @Test func zoomStaysWithinTheLimits() {
        var camera = viewport()

        camera.zoom(to: 50, anchor: camera.center, limits: limits)
        #expect(camera.scale == 4)
        camera.zoom(to: 0.001, anchor: camera.center, limits: limits)
        #expect(camera.scale == 0.1)
    }

    @Test func zoomStepsGoToTheNextStepEitherWay() {
        let steps: [CGFloat] = [0.1, 0.5, 1, 2, 4]

        #expect(viewport(scale: 1).zoomStep(up: true, steps: steps) == 2)
        #expect(viewport(scale: 1).zoomStep(up: false, steps: steps) == 0.5)
        // Between steps after a pinch: the nearest step in that direction.
        #expect(viewport(scale: 1.4).zoomStep(up: true, steps: steps) == 2)
        #expect(viewport(scale: 1.4).zoomStep(up: false, steps: steps) == 1)
        // At the ends nothing changes.
        #expect(viewport(scale: 4).zoomStep(up: true, steps: steps) == 4)
        #expect(viewport(scale: 0.1).zoomStep(up: false, steps: steps) == 0.1)
    }

    @Test func fitShowsTheWholeRectangleCentred() {
        var camera = viewport()
        let map = CGRect(x: -1000, y: -200, width: 2400, height: 600)

        camera.fit(map, padding: 40, limits: limits)

        #expect(camera.visibleRect.contains(map))
        let centre = camera.toView(CGPoint(x: map.midX, y: map.midY))
        #expect(abs(centre.x - 400) < 1e-9 && abs(centre.y - 300) < 1e-9)
        #expect(camera.scale == (800 - 80) / 2400)
    }

    @Test func fitDoesNotEnlargePastTheLimit() {
        var camera = viewport()

        camera.fit(CGRect(x: -50, y: -20, width: 100, height: 40), padding: 40, limits: 0.1...1)

        #expect(camera.scale == 1)
    }

    @Test func revealPansTheLeastDistance() {
        var camera = viewport()
        // Canvas x 500...600 is off the right edge (view x 900...1000).
        camera.reveal(CGRect(x: 500, y: 0, width: 100, height: 30), margin: 20)

        #expect(camera.scale == 1)
        #expect(camera.toView(CGPoint(x: 600, y: 0)).x == 780)
        #expect(camera.offset.y == 300)

        // Already in view: nothing moves.
        let settled = camera
        camera.reveal(CGRect(x: 0, y: 0, width: 50, height: 30), margin: 20)
        #expect(camera == settled)
    }

    @Test func resizeKeepsTheMiddleInPlace() {
        var camera = viewport()
        let middle = camera.toCanvas(camera.center)

        camera.resize(to: CGSize(width: 1200, height: 900))

        #expect(camera.toCanvas(camera.center) == middle)
    }

    @Test func cullingRectAddsAMarginAroundTheView() {
        let camera = viewport()

        #expect(camera.cullingRect(margin: 0.25) == CGRect(x: -600, y: -450, width: 1200, height: 900))
    }
}
