import Foundation
import MindMapDomain
import Testing

@Suite("Organization values")
struct OrganizationValuesTests {
    @Test(arguments: [
        ("Việc", "VIỆC", true),
        ("Việc", "Vie\u{0323}\u{0302}c", true), // decomposed marks
        ("việc", "viếc", false),
        ("việc", "viec", false),
        ("đi", "di", false),
        ("Đi", "đi", true),
        // Japanese: voiced marks are part of the letter, and stay.
        ("タグ", "タク", false),
        ("タグ", "タ\u{30AF}\u{3099}", true), // decomposed ガ-row mark
        ("しごと", "シゴト", false),
    ])
    func tagKeyFoldsCaseButKeepsMarks(lhs: String, rhs: String, same: Bool) {
        #expect((MindTag.key(for: lhs) == MindTag.key(for: rhs)) == same)
    }

    @Test func tagNamesAreCleaned() {
        #expect(MindTag.normalizedName("  #Kế   hoạch \n quý ") == "Kế hoạch quý")
        #expect(MindTag.normalizedName("# ") == nil)
        #expect(MindTag.normalizedName("   ") == nil)
        #expect(MindTag.normalizedName(String(repeating: "ệ", count: 40)) != nil)
        #expect(MindTag.normalizedName(String(repeating: "ệ", count: 41)) == nil)
    }

    @Test func symbolIsANameOrOneEmoji() {
        #expect(TopicSymbol.normalized(" star.fill ") == "star.fill")
        #expect(TopicSymbol.normalized("🚀🔥") == "🚀")
        #expect(TopicSymbol.normalized("👩‍💻 dev") == "👩‍💻")
        #expect(TopicSymbol.normalized("Star") == "S")
        #expect(TopicSymbol.normalized("  ") == nil)
    }

    @Test func calendarDayReadsOnlyRealISODays() throws {
        #expect(CalendarDay(isoString: "2026-10-02")?.isoString == "2026-10-02")
        #expect(CalendarDay(isoString: "2028-02-29") != nil)
        #expect(CalendarDay(isoString: "2026-02-29") == nil)
        #expect(CalendarDay(isoString: "2026-1-02") == nil)
        #expect(CalendarDay(isoString: "2026-10-02T00:00:00Z") == nil)
        #expect(CalendarDay(isoString: "") == nil)
        let earlier = try #require(CalendarDay(year: 2026, month: 9, day: 30))
        let later = try #require(CalendarDay(year: 2026, month: 10, day: 1))
        #expect(earlier < later)
    }

    /// A due day is the day on the device's calendar, whatever its time zone.
    @Test func calendarDayFromADateUsesTheCalendarsTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        let lateEvening = try #require(ISO8601DateFormatter().date(from: "2026-10-02T20:00:00Z"))

        #expect(CalendarDay(lateEvening, in: calendar).isoString == "2026-10-03")
    }

    @Test func priorityAboveThreeReadsAsLow() {
        #expect(TaskPriority(rawValue: 7).level == .low)
        #expect(TaskPriority(rawValue: 2).level == .medium)
        #expect(TaskPriority(rawValue: 0).level == .high)
    }

    @Test func unknownStoredTokensSurvive() {
        let color = TopicColor(rawValue: "magenta")
        #expect(!color.isKnown)
        #expect(color.rawValue == "magenta")
        #expect(!TaskState(rawValue: "blocked").isDone)
        let allKnown = TopicColor.all.allSatisfy(\.isKnown)
        #expect(allKnown)
    }

    @Test func organizedNodeRoundTripsThroughJSON() throws {
        let node = MindNode(
            mapID: MapID(), parentID: NodeID(), title: "Ship", createdAt: Date(timeIntervalSinceReferenceDate: 1),
            color: .teal, symbol: "flag", taskState: .done, priority: .high,
            startDate: CalendarDay(year: 2026, month: 10, day: 1), dueDate: CalendarDay(year: 2026, month: 10, day: 9)
        )

        let data = try JSONEncoder().encode(node)

        #expect(try JSONDecoder().decode(MindNode.self, from: data) == node)
        #expect(String(decoding: data, as: UTF8.self).contains("\"2026-10-09\""))
    }

    /// JSON written before the organization fields decodes with them empty.
    @Test func olderNodeJSONDecodes() throws {
        let old = MindNode(mapID: MapID(), parentID: nil, title: "Old", createdAt: Date(timeIntervalSinceReferenceDate: 1))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        for key in ["color", "symbol", "taskState", "priority", "startDate", "dueDate"] {
            json.removeValue(forKey: key)
        }

        let decoded = try JSONDecoder().decode(MindNode.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded == old)
    }
}
