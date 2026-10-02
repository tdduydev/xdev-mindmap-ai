import Foundation
import MindMapDomain
import MindMapSearch
import Testing

@Suite("Library search")
struct LibrarySearchTests {
    let design = MapSearchDocument(mapID: MapID(), title: "Thiết kế sản phẩm", topicTexts: ["Người dùng", "Màn hình"])
    let notes = MapSearchDocument(mapID: MapID(), title: "Weekly notes", topicTexts: ["Review", "Thiết kế API", "đánh giá"])
    let trip = MapSearchDocument(mapID: MapID(), title: "Đà Lạt trip", topicTexts: ["Hotel", "Food"])

    var index: LibrarySearchIndex { LibrarySearchIndex(documents: [design, notes, trip]) }

    @Test func titleMatchesComeBeforeContentMatches() {
        // Content match listed first in the source order; ranking still puts the title first.
        let ranked = index.search(SearchQuery("thiet ke")).ranked([notes.mapID, trip.mapID, design.mapID])

        #expect(ranked.map(\.mapID) == [design.mapID, notes.mapID])
        #expect(ranked.map(\.match) == [.title, .content(excerpt: "Thiết kế API")])
    }

    @Test func keepsTheListOrderWithinAGroup() {
        // "e" is in two titles and only in the topics of the trip.
        let results = index.search(SearchQuery("e"))

        #expect(results.ranked([trip.mapID, notes.mapID, design.mapID]).map(\.mapID) == [notes.mapID, design.mapID, trip.mapID])
        #expect(results.ranked([design.mapID, notes.mapID, trip.mapID]).map(\.mapID) == [design.mapID, notes.mapID, trip.mapID])
    }

    @Test func dMatchesTheVietnameseLetter() {
        let hits = index.search(SearchQuery("da lat")).hits

        #expect(hits == [trip.mapID: .title])
    }

    @Test func wordsMayComeFromDifferentTopics() {
        let hits = index.search(SearchQuery("review danh gia")).hits

        #expect(hits == [notes.mapID: .content(excerpt: "Review")])
    }

    @Test func noMatchAndEmptyQuery() {
        #expect(index.search(SearchQuery("xyz")).hits.isEmpty)
        #expect(index.search(SearchQuery("")).hits.isEmpty)
    }

    @Test func rankingIgnoresMapsNotInTheList() {
        let results = index.search(SearchQuery("thiet ke"))

        #expect(results.ranked([notes.mapID]).map(\.mapID) == [notes.mapID])
        #expect(LibrarySearchResults.empty.ranked([design.mapID]).isEmpty)
    }

    @Test func buildsInTheBackground() async {
        let built = await LibrarySearchIndex.build(documents: [design])
        let results = await built.searchInBackground(SearchQuery("san pham"))

        #expect(results.hits == [design.mapID: .title])
    }
}
