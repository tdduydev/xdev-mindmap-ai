import Foundation

/// Public pages the app links to.
enum AppLinks {
    static let website = URL(literal: "https://xdev.asia/mindmap")
    /// App Review needs this in App Store Connect and inside the app (5.1.1(i)).
    static let privacyPolicy = URL(literal: "https://xdev.asia/mindmap/privacy")
    /// Also the target of Help ▸ MindMap AI Help: the app has no help book.
    static let support = URL(literal: "https://xdev.asia/mindmap/support")
    #if os(macOS)
    /// System Settings ▸ Apple Intelligence & Siri. The pane's extension
    /// (`com.apple.Siri-Settings.extension`) declares that it opens from this
    /// scheme; checked in its Info.plist on macOS 27.0.1, not on macOS 26.
    static let appleIntelligenceSettings = URL(literal: "x-apple.systempreferences:com.apple.Siri-Settings.extension")
    #endif
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
