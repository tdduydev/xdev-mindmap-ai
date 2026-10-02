import Foundation
import MindMapDomain
import Testing

@Suite("Map theme")
struct MindMapThemeTests {
    @Test func storedValuesStayFixed() {
        #expect(MindMapTheme.allCases.map(\.rawValue) == ["standard", "xdevBlue", "graphite"])
    }

    @Test func unknownStoredValueFallsBackToStandard() {
        #expect(MindMapTheme(storedValue: "ocean") == .standard)
        #expect(MindMapTheme(storedValue: "") == .standard)
        #expect(MindMapTheme(storedValue: "graphite") == .graphite)
    }

    /// A map exported by a newer version with a theme this one lacks still decodes.
    @Test func mapWithUnknownThemeDecodesAsStandard() throws {
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(MindMap(title: "Plan", theme: .xdevBlue))
        ) as! [String: Any]
        json["theme"] = "aurora"

        let decoded = try JSONDecoder().decode(MindMap.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded.theme == .standard)
        #expect(decoded.title == "Plan")
    }

    @Test func knownThemeRoundTrips() throws {
        for theme in MindMapTheme.allCases {
            let data = try JSONEncoder().encode(theme)
            #expect(try JSONDecoder().decode(MindMapTheme.self, from: data) == theme)
        }
    }
}
