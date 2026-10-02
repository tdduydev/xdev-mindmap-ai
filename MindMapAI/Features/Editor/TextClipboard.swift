/// Where copied branches go. The session talks to this instead of a pasteboard
/// type, so it stays the same on every platform and tests use a fake.
protocol TextClipboard: AnyObject {
    var text: String? { get }
    /// Whether there is text, without reading it: on iOS reading asks the
    /// person for permission, which only an actual paste should do.
    var hasText: Bool { get }
    func setText(_ text: String)
}

/// A clipboard that lives only in memory, for tests and previews.
final class MemoryClipboard: TextClipboard {
    var text: String?

    init(text: String? = nil) {
        self.text = text
    }

    var hasText: Bool { text != nil }

    func setText(_ text: String) {
        self.text = text
    }
}
