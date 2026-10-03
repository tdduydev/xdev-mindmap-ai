import Foundation
import MindMapDomain
import MindMapGraph
@testable import MindMapInterchange
import Testing

@Suite("Map links (ADR 0012)")
struct MapLinkCodecTests {
    /// Written by Python's zlib (raw DEFLATE), not by this codec, so the test
    /// proves the format rather than agreeing with itself. The web page's test
    /// (`docs/web/mindmap/m/decode.test.mjs`) reads the same link. It has an
    /// unknown key `x`, which readers ignore.
    static let golden = URL(string: "https://xdev.asia/mindmap/m#1.q1YqUbJSCinKLFAoyVc4MuHwAgWfh7sWlijpKBUpWVXDZYH8ZCWraIiAR35Jag5QJA_I9ktNLFIoyUhVyEnMTo3JCyzNTAVpzgFKZZSUFBRb6eunViTmFuSk6iXn5-on2ifZGqol2xop1epADHPLz08BakhUsjJEtiMg4-Hu-Qo2SXZJhzfZ6CfZKdXG1sbqKFUApTLT8_KLUlOUamsB")!

    static func sampleMap() throws -> GraphState {
        typealias Topic = MapLinkCodec.Topic
        return try MapLinkCodec.graph(from: MapLinkCodec.Payload(t: "Trip to Đà Lạt", r: Topic(t: "Trip", n: "Summer", c: [
            Topic(t: "Hotel", n: "Near the lake\nQuiet", l: "https://example.com/a?b=1"),
            Topic(t: "Food", a: 1, c: [
                Topic(t: "Phở bò"),
                Topic(t: "旅行の計画", l: "mailto:a@example.com"),
            ]),
            Topic(t: ""),
        ])))
    }

    @Test func roundTripKeepsStructureNotesLinksAndAILabel() async throws {
        let map = try Self.sampleMap()
        let url = try MapLinkCodec.link(for: map)
        #expect(url.absoluteString.hasPrefix("https://xdev.asia/mindmap/m#1."))

        let opened = try await MapLinkCodec.map(from: url)
        #expect(opened.map.title == "Trip to Đà Lạt")
        #expect(opened.outline == map.outline)
        #expect(opened.firstNode(titled: "Hotel")?.link?.string == "https://example.com/a?b=1")
        #expect(opened.firstNode(titled: "旅行の計画")?.link?.string == "mailto:a@example.com")
        #expect(opened.firstNode(titled: "Food")?.metadata.origin == .ai)
        #expect(opened.firstNode(titled: "Hotel")?.metadata.origin == .imported)
        #expect(opened.map.id != map.map.id)
        #expect(opened.nodes.count == map.nodes.count)
    }

    @Test func branchBecomesTheCentralTopicAndTitle() async throws {
        let map = try Self.sampleMap()
        let foodID = try #require(map.firstNode(titled: "Food")?.id)
        let opened = try await MapLinkCodec.map(from: MapLinkCodec.link(for: map, branch: foodID))
        #expect(opened.map.title == "Food")
        #expect(opened.outline == "Food\n  Phở bò\n  旅行の計画")
    }

    @Test func linkWithoutNotesDropsNotesOnly() async throws {
        let map = try Self.sampleMap()
        let opened = try await MapLinkCodec.map(from: MapLinkCodec.link(for: map, includeNotes: false))
        #expect(opened.nodes.values.allSatisfy { $0.note == nil })
        #expect(opened.nodes.count == map.nodes.count)
        #expect(opened.firstNode(titled: "Hotel")?.link != nil)
    }

    @Test func goldenLinkFromAnotherEncoderReads() async throws {
        let opened = try await MapLinkCodec.map(from: Self.golden)
        #expect(opened.map.title == "Trip to Đà Lạt")
        #expect(opened.outline == "Trip\n  Hotel [Near the lake\nQuiet]\n  Food\n    Phở <b>bò</b>")
        #expect(opened.firstNode(titled: "Hotel")?.link?.string == "https://example.com/a?b=1&c=2")
        #expect(opened.firstNode(titled: "Food")?.metadata.origin == .ai)
    }

    @Test func floatingTopicsAreLeftOut() async throws {
        var map = try Self.sampleMap()
        var engine = try GraphEngine(state: map)
        try engine.execute(AddFloatingTopicCommand(title: "Loose", position: TopicPosition(x: 400, y: 400)))
        map = engine.state
        #expect(map.firstNode(titled: "Loose") != nil)
        let opened = try await MapLinkCodec.map(from: MapLinkCodec.link(for: map))
        #expect(opened.firstNode(titled: "Loose") == nil)
    }

    @Test func shareFitsOrSaysWhatWouldFit() async throws {
        let small = try Self.sampleMap()
        guard case .link = await MapLinkCodec.share(small) else {
            Issue.record("A small map fits in a link")
            return
        }

        // Notes of random text do not compress; the titles alone do.
        var items = [OutlineDraft.Item(depth: 0, title: "Big")]
        for index in 0 ..< 60 {
            items.append(.init(depth: 1, title: "Topic \(index)", note: Self.noise(length: 200, seed: index)))
        }
        let big = try GraphState.imported(from: OutlineDraft(items: items), title: "Big")
        guard case .tooLong(let withoutNotes) = await MapLinkCodec.share(big) else {
            Issue.record("Incompressible notes are too long for a link")
            return
        }
        let url = try #require(withoutNotes)
        #expect(url.absoluteString.count <= MapLinkCodec.maximumLinkLength)

        var huge = [OutlineDraft.Item(depth: 0, title: "Huge")]
        for index in 0 ..< 400 { huge.append(.init(depth: 1, title: Self.noise(length: 40, seed: index))) }
        let hugeMap = try GraphState.imported(from: OutlineDraft(items: huge), title: "Huge")
        #expect(await MapLinkCodec.share(hugeMap) == .tooLong(withoutNotes: nil))
    }

    @Test func mapsTheReaderWouldRefuseAreNotEncoded() throws {
        var items: [OutlineDraft.Item] = []
        for depth in 0 ... MapLinkCodec.maximumDepth + 1 { items.append(.init(depth: depth, title: "L")) }
        let deep = try GraphState.imported(from: OutlineDraft(items: items), title: "Deep")
        #expect(throws: MapLinkError.tooLarge) { try MapLinkCodec.link(for: deep) }
    }

    // MARK: Refused links (FR-IO-09)

    @Test(arguments: [
        "https://example.com/mindmap/m#1.q1YqUbJSCg",
        "http://xdev.asia/mindmap/m#1.q1YqUbJSCg",
        "https://xdev.asia/mindmap/other#1.q1YqUbJSCg",
        "https://xdev.asia/mindmap/m",
        "https://xdev.asia/mindmap/m#",
        "https://xdev.asia/mindmap/m#1.",
        "https://xdev.asia/mindmap/m#abc",
        "https://xdev.asia/mindmap/m#1.ab+cd",
        "https://xdev.asia/mindmap/m#1.ab.cd",
        "https://xdev.asia/mindmap/m#0.q1YqUbJSCg",
    ])
    func notAMapLink(_ text: String) async throws {
        let url = try #require(URL(string: text))
        await #expect(throws: MapLinkError.notAMapLink) { try await MapLinkCodec.map(from: url) }
    }

    @Test func newerVersionSaysSo() async throws {
        for text in ["https://xdev.asia/mindmap/m#2.q1YqUbJSCg", "https://xdev.asia/mindmap/m#99999999999999999999999.q1Yq"] {
            let url = try #require(URL(string: text))
            await #expect(throws: MapLinkError.newerVersion) { try await MapLinkCodec.map(from: url) }
        }
    }

    @Test func cutShortLinkIsDamaged() async throws {
        let full = try MapLinkCodec.link(for: Self.sampleMap()).absoluteString
        let cut = try #require(URL(string: String(full.prefix(full.count - 20))))
        await #expect(throws: MapLinkError.damaged) { try await MapLinkCodec.map(from: cut) }
    }

    @Test func payloadThatIsNotAMapIsDamaged() async throws {
        for json in [#"{"t":"No root"}"#, #"[1,2]"#, #"{"r":{"t":"A","a":true}}"#, "not json"] {
            let url = try link(forJSON: json)
            await #expect(throws: MapLinkError.damaged) { try await MapLinkCodec.map(from: url) }
        }
    }

    @Test func decompressionBombIsRefused() async throws {
        // About 2 MB of spaces inside a title compresses to a couple of kilobytes.
        let json = #"{"r":{"t":""# + String(repeating: " ", count: 2_000_000) + #""}}"#
        let url = try link(forJSON: json)
        #expect(url.absoluteString.count < MapLinkCodec.maximumLinkLength)
        await #expect(throws: MapLinkError.tooLarge) { try await MapLinkCodec.map(from: url) }
    }

    @Test func tooManyOrTooDeepTopicsAreRefused() async throws {
        let many = #"{"r":{"t":"A","c":["# + Array(repeating: #"{"t":"x"}"#, count: MapLinkCodec.maximumTopics).joined(separator: ",") + "]}}"
        await #expect(throws: MapLinkError.tooLarge) { try await MapLinkCodec.map(from: link(forJSON: many)) }

        let levels = 5_000
        let deep = #"{"r":"# + String(repeating: #"{"t":"x","c":["#, count: levels) + #"{"t":"x"}"# + String(repeating: "]}", count: levels) + "}"
        await #expect(throws: MapLinkError.tooLarge) { try await MapLinkCodec.map(from: link(forJSON: deep)) }
    }

    @Test func unsafeLinksInThePayloadAreDropped() async throws {
        let json = #"{"r":{"t":"A","c":[{"t":"B","l":"javascript:alert(1)"},{"t":"C","l":"file:///etc/passwd"},{"t":"D","l":"https://ok.example"}]}}"#
        let opened = try await MapLinkCodec.map(from: link(forJSON: json))
        #expect(opened.firstNode(titled: "B")?.link == nil)
        #expect(opened.firstNode(titled: "C")?.link == nil)
        #expect(opened.firstNode(titled: "D")?.link?.string == "https://ok.example")
        #expect(opened.map.title == "A")
    }

    @Test func recognisesOnlyTheMapLinkPage() throws {
        #expect(MapLinkCodec.isMapLink(URL(string: "https://XDEV.asia/mindmap/m#1.a")!))
        #expect(MapLinkCodec.isMapLink(URL(string: "https://xdev.asia/mindmap/m/")!))
        #expect(!MapLinkCodec.isMapLink(URL(string: "https://xdev.asia/mindmap")!))
        #expect(!MapLinkCodec.isMapLink(URL(string: "https://xdev.asia.evil.example/mindmap/m#1.a")!))
    }

    // MARK: Helpers

    private func link(forJSON json: String) throws -> URL {
        let data = try MapLinkCodec.deflate(Data(json.utf8)).base64URLEncodedString()
        return try #require(URL(string: "https://xdev.asia/mindmap/m#1.\(data)"))
    }

    /// Letters from a fixed generator, so the test is the same on every run.
    static func noise(length: Int, seed: Int) -> String {
        var state = UInt64(seed + 1) &* 0x9E37_79B9_7F4A_7C15
        let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0 ..< length).map { _ in
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return letters[Int(state % UInt64(letters.count))]
        })
    }
}
