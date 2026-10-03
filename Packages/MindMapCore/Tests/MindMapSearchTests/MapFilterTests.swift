import Foundation
import MindMapDomain
import MindMapGraph
import MindMapSearch
import Testing

@Suite("Map filter")
struct MapFilterTests {
    /// Root ─ Plan ─ (Budget: high, open, due today, #money #urgent)
    ///             └ (Hotels: done, due yesterday, #money)
    ///      ─ Ideas (AI) ─ (Venue: low, open, due in 7 days)
    struct Fixture {
        var state: GraphState
        let root: NodeID
        let plan = NodeID()
        let budget = NodeID()
        let hotels = NodeID()
        let ideas = NodeID()
        let venue = NodeID()
        let money: TagID
        let urgent: TagID
        let today = CalendarDay(year: 2026, month: 10, day: 3)!

        init() throws {
            var engine = try GraphEngine(state: GraphState.newMap(title: "Trip"))
            root = try #require(engine.state.map.rootNodeID)
            try engine.execute(BatchCommand([
                AddNodeCommand(nodeID: plan, .child(of: root), title: "Plan"),
                AddNodeCommand(nodeID: budget, .child(of: plan), title: "Budget"),
                AddNodeCommand(nodeID: hotels, .child(of: plan), title: "Hotels"),
                AddNodeCommand(nodeID: ideas, .child(of: root), title: "Ideas", metadata: NodeMetadata(origin: .ai)),
                AddNodeCommand(nodeID: venue, .child(of: ideas), title: "Venue"),
                SetTaskCommand(nodeIDs: [budget], state: .set(.open), priority: .set(.high), due: .set(today)),
                SetTaskCommand(nodeIDs: [hotels], state: .set(.done), due: .set(today.adding(days: -1))),
                SetTaskCommand(nodeIDs: [venue], state: .set(.open), priority: .set(.low), due: .set(today.adding(days: 7))),
                TagNodesCommand(nodeIDs: [budget, hotels], add: [.named("Money")]),
                TagNodesCommand(nodeIDs: [budget], add: [.named("Urgent")]),
            ]))
            state = engine.state
            money = try #require(state.tags.values.first { $0.name == "Money" }?.id)
            urgent = try #require(state.tags.values.first { $0.name == "Urgent" }?.id)
        }
    }

    @Test func noCriteriaIsNotActiveAndShowsEverything() throws {
        let f = try Fixture()
        let filter = MapFilter()
        let view = MapFilterView(state: f.state, filter: filter, mode: .hide, focusID: nil, today: f.today)

        #expect(!filter.isActive)
        #expect(view.shown == Set(f.state.nodes.keys))
        #expect(!view.isDimmed(f.budget))
        #expect(view.project(f.state).nodes.count == f.state.nodes.count)
    }

    @Test func tagsMatchAnyOrAll() throws {
        let f = try Fixture()
        var filter = MapFilter()
        filter.tagIDs = [f.money, f.urgent]

        #expect(filter.matches(in: f.state, today: f.today) == [f.budget, f.hotels])
        filter.tagMatch = .all
        #expect(filter.matches(in: f.state, today: f.today) == [f.budget])
    }

    @Test func priorityTaskDueOriginAndTextCombine() throws {
        let f = try Fixture()
        var filter = MapFilter()
        filter.priorities = [.high, .low]
        #expect(filter.matches(in: f.state, today: f.today) == [f.budget, f.venue])
        filter.tasks = [.open]
        filter.due = [.nextSevenDays]
        #expect(filter.matches(in: f.state, today: f.today) == [f.budget, f.venue])
        filter.due = [.today]
        #expect(filter.matches(in: f.state, today: f.today) == [f.budget])

        var other = MapFilter()
        other.tasks = [.notATask]
        #expect(other.matches(in: f.state, today: f.today) == [f.root, f.plan, f.ideas])
        other = MapFilter()
        other.due = [.overdue]
        #expect(other.matches(in: f.state, today: f.today).isEmpty, "a done task is never overdue")
        other = MapFilter()
        other.origins = [.ai]
        #expect(other.matches(in: f.state, today: f.today) == [f.ideas])
        other = MapFilter()
        other.text = "hotel"
        #expect(other.matches(in: f.state, today: f.today) == [f.hotels])
        other.text = "#urg"
        #expect(other.matches(in: f.state, today: f.today) == [f.budget])
    }

    @Test func dimKeepsEveryTopicAndFadesTheRest() throws {
        let f = try Fixture()
        var filter = MapFilter()
        filter.text = "venue"
        let view = MapFilterView(state: f.state, filter: filter, mode: .dim, focusID: nil, today: f.today)

        #expect(view.shown == Set(f.state.nodes.keys))
        #expect(view.isDimmed(f.budget))
        #expect(!view.isDimmed(f.venue))
        #expect(view.isSelectable(f.venue))
        #expect(!view.isSelectable(f.budget), "Select All picks matches only")
    }

    @Test func hideKeepsMatchesWithTheirAncestors() throws {
        let f = try Fixture()
        var filter = MapFilter()
        filter.text = "venue"
        let view = MapFilterView(state: f.state, filter: filter, mode: .hide, focusID: nil, today: f.today)
        let projected = view.project(f.state)

        #expect(view.shown == [f.root, f.ideas, f.venue])
        #expect(view.isDimmed(f.ideas), "an ancestor shown for context is faded")
        #expect(Set(projected.nodes.keys) == view.shown)
        #expect(projected.childIDs(of: f.root) == [f.ideas])
        #expect(f.state.nodes.count == 6, "the real map keeps every topic")
    }

    @Test func focusShowsOneBranchWithItsTopicInTheCentre() throws {
        let f = try Fixture()
        let view = MapFilterView(state: f.state, filter: MapFilter(), mode: .dim, focusID: f.plan, today: f.today)
        let projected = view.project(f.state)

        #expect(view.shown == [f.plan, f.budget, f.hotels])
        #expect(projected.map.rootNodeID == f.plan)
        #expect(projected.node(f.plan)?.parentID == nil)
        #expect(projected.floatingTopicIDs.isEmpty)
        #expect(projected.visibleOutline().map(\.nodeID) == [f.plan, f.budget, f.hotels])
    }

    @Test func filterAppliesInsideTheFocusedBranch() throws {
        let f = try Fixture()
        var filter = MapFilter()
        filter.tagIDs = [f.money]
        filter.tasks = [.done]
        let view = MapFilterView(state: f.state, filter: filter, mode: .hide, focusID: f.plan, today: f.today)

        #expect(view.matches == [f.hotels])
        #expect(view.shown == [f.plan, f.hotels])
    }

    @Test func aFocusedTopicThatIsGoneEndsFocus() throws {
        let f = try Fixture()
        let view = MapFilterView(state: f.state, filter: MapFilter(), mode: .dim, focusID: NodeID(), today: f.today)

        #expect(view.focusID == nil)
        #expect(view.shown.count == f.state.nodes.count)
    }

    @Test func filterRoundTripsAsDeviceLocalJSON() throws {
        let f = try Fixture()
        var filter = MapFilter()
        filter.tagIDs = [f.money]
        filter.tagMatch = .all
        filter.priorities = [.medium]
        filter.due = [.noDate]
        filter.origins = [.imported]
        filter.text = "x"
        let data = try JSONEncoder().encode(filter)

        #expect(try JSONDecoder().decode(MapFilter.self, from: data) == filter)
    }

    @Test func addingDaysCrossesMonthsAndYears() {
        let day = CalendarDay(year: 2026, month: 12, day: 28)!
        #expect(day.adding(days: 7) == CalendarDay(year: 2027, month: 1, day: 4))
        #expect(day.adding(days: -28) == CalendarDay(year: 2026, month: 11, day: 30))
    }
}
