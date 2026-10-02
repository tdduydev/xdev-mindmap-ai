extension MindNode {
    /// Whether the topic shows the note mark. Blank text does not count, so a
    /// note emptied in another app or an import is not flagged as content.
    public var hasNote: Bool {
        note?.contains { !$0.isWhitespace } ?? false
    }
}
