import Foundation

/// Public pages the app links to.
enum AppLinks {
    static let website = URL(literal: "https://xdev.asia/mindmap")
}

extension URL {
    /// A URL written in the source. A typo is a programming error, caught the first time the screen opens.
    init(literal: StaticString) {
        guard let url = URL(string: "\(literal)") else {
            preconditionFailure("Invalid URL literal: \(literal)")
        }
        self = url
    }
}
