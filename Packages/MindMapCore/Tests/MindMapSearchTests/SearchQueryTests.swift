import Foundation
import MindMapSearch
import Testing

@Suite("Folding and matching")
struct SearchQueryTests {
    @Test(arguments: [
        ("Thiết kế", "thiet ke"),
        ("ĐỊNH HƯỚNG", "dinh huong"),
        ("đường đi", "duong di"),
        ("Café Ｒｅｓｕｍｅ", "cafe resume"),
        ("Ứng dụng", "ung dung"),
    ])
    func foldsCaseAccentsWidthAndD(text: String, folded: String) {
        #expect(SearchText.fold(text) == folded)
    }

    @Test func foldsDecomposedVietnamese() {
        // Text pasted from some apps arrives decomposed (NFD); it must match typed text.
        let decomposed = "Thiết kế".decomposedStringWithCanonicalMapping
        #expect(SearchQuery("thiet ke").matches(decomposed))
    }

    @Test(arguments: [
        ("thiet ke", "Thiết kế hệ thống", true),
        ("THIẾT KẾ", "thiet ke", true),
        ("d", "Đà Nẵng", true),
        ("đa", "Da Nang", true),
        ("ke thiet", "Thiết kế", true),
        ("  thiet   ke  ", "Thiết kế", true),
        ("thiet ke", "Thiết lập", false),
        ("", "anything", false),
        ("   ", "anything", false),
    ])
    func matchesEveryWord(query: String, text: String, expected: Bool) {
        #expect(SearchQuery(query).matches(text) == expected)
    }

    @Test func emptyQuery() {
        #expect(SearchQuery(" \n").isEmpty)
        #expect(SearchQuery("a b").terms == ["a", "b"])
    }
}
