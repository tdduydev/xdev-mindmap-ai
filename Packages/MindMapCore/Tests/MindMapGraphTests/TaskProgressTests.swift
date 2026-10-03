import Foundation
import MindMapDomain
@testable import MindMapGraph
import Testing

@Suite("Task progress")
struct TaskProgressTests {
    static let outline = """
    Root
      Launch
        Design
          Sketch
          Review
        Build
        Notes
      Other
    """

    private func mark(_ titles: [String], _ state: TaskState, in fixture: inout GraphFixture) throws {
        try fixture.engine.execute(SetTaskCommand(nodeIDs: titles.map { fixture[$0] }, state: .set(state)))
    }

    @Test func countsLeafTasksOfEachBranch() throws {
        var fixture = try GraphFixture(Self.outline)
        try mark(["Design", "Sketch", "Review", "Build"], .open, in: &fixture)
        try mark(["Sketch"], .done, in: &fixture)

        let progress = fixture.state.taskProgressByNode()

        // Design is a task with tasks below it, so only Sketch and Review count for it.
        #expect(progress[fixture["Design"]] == TaskProgress(done: 1, total: 2))
        #expect(progress[fixture["Launch"]] == TaskProgress(done: 1, total: 3))
        #expect(progress[fixture["Root"]] == TaskProgress(done: 1, total: 3))
        #expect(progress[fixture["Sketch"]] == nil)
        #expect(progress[fixture["Other"]] == nil)
        #expect(fixture.state.taskProgress(of: fixture["Launch"]) == TaskProgress(done: 1, total: 3))
    }

    @Test func aTaskWithoutTaskChildrenCountsItself() throws {
        var fixture = try GraphFixture(Self.outline)
        try mark(["Design"], .done, in: &fixture)

        #expect(fixture.state.taskProgress(of: fixture["Launch"]) == TaskProgress(done: 1, total: 1))
        #expect(fixture.state.taskProgress(of: fixture["Launch"])?.isComplete == true)
        #expect(fixture.state.taskProgress(of: fixture["Design"]) == nil)
    }

    @Test func followsUndoBecauseItIsNeverStored() throws {
        var fixture = try GraphFixture(Self.outline)
        try mark(["Build"], .open, in: &fixture)
        try mark(["Build"], .done, in: &fixture)
        #expect(fixture.state.taskProgress(of: fixture["Launch"]) == TaskProgress(done: 1, total: 1))

        _ = fixture.engine.undo()
        #expect(fixture.state.taskProgress(of: fixture["Launch"]) == TaskProgress(done: 0, total: 1))
        _ = fixture.engine.redo()
        #expect(fixture.state.taskProgress(of: fixture["Launch"]) == TaskProgress(done: 1, total: 1))
    }

    @Test func anUnknownStateCountsAsOpen() throws {
        var fixture = try GraphFixture(Self.outline)
        try mark(["Build"], TaskState(rawValue: "blocked"), in: &fixture)

        #expect(fixture.state.taskProgress(of: fixture["Launch"]) == TaskProgress(done: 0, total: 1))
    }

    @Test func aMapWithoutTasksHasNoProgress() throws {
        let fixture = try GraphFixture(Self.outline)
        #expect(fixture.state.taskProgressByNode().isEmpty)
    }
}
