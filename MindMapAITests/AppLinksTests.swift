import Foundation
@testable import MindMapAI
import Testing

/// App Review opens these links (2.1, 5.1.1(i)); a wrong host or a plain
/// http link is caught here rather than in review.
@Suite("App links")
struct AppLinksTests {
    // A loop, not `arguments:`: AppLinks is main-actor isolated, and test
    // arguments are built off the main actor.
    @Test func pointAtTheXDevSiteOverHTTPS() {
        for url in [AppLinks.website, AppLinks.privacyPolicy, AppLinks.support] {
            #expect(url.scheme == "https")
            #expect(url.host() == "xdev.asia")
            #expect(url.path().hasPrefix("/mindmap"))
        }
    }

    @Test func privacyPolicyAndSupportAreSeparatePages() {
        #expect(AppLinks.privacyPolicy.path() == "/mindmap/privacy")
        #expect(AppLinks.support.path() == "/mindmap/support")
    }
}
