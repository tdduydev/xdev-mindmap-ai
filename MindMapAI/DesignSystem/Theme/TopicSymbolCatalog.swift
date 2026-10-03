import Foundation
import MindMapDomain

/// The SF Symbols a topic can carry (FR-ORG-03), in picker order. Names were
/// checked against the SF Symbols of macOS 27; all of them date from iOS 16
/// or earlier. A stored name outside this list, from a newer version or
/// another tool, draws nothing and is kept, so the layout never depends on
/// whether this OS has the symbol.
nonisolated enum TopicSymbolCatalog {
    struct Entry: Identifiable, Sendable {
        let name: String
        let title: LocalizedStringResource

        var id: String { name }
    }

    // `envelope`, `link`, `note.text`, `sparkles` and `tag` are left out: the
    // card already uses them for mail links, links, notes, AI and tags.
    static let entries: [Entry] = [
        Entry(name: "flag.fill", title: "Flag"),
        Entry(name: "star.fill", title: "Star"),
        Entry(name: "heart.fill", title: "Heart"),
        Entry(name: "lightbulb.fill", title: "Idea"),
        Entry(name: "questionmark.circle.fill", title: "Question"),
        Entry(name: "exclamationmark.triangle.fill", title: "Warning"),
        Entry(name: "checkmark.seal.fill", title: "Approved"),
        Entry(name: "xmark.octagon.fill", title: "Rejected"),
        Entry(name: "bolt.fill", title: "Lightning"),
        Entry(name: "flame.fill", title: "Hot"),
        Entry(name: "target", title: "Goal"),
        Entry(name: "trophy.fill", title: "Trophy"),
        Entry(name: "1.circle.fill", title: "Number 1"),
        Entry(name: "2.circle.fill", title: "Number 2"),
        Entry(name: "3.circle.fill", title: "Number 3"),
        Entry(name: "person.fill", title: "Person"),
        Entry(name: "person.2.fill", title: "People"),
        Entry(name: "calendar", title: "Calendar"),
        Entry(name: "clock.fill", title: "Time"),
        Entry(name: "bell.fill", title: "Reminder"),
        Entry(name: "bookmark.fill", title: "Bookmark"),
        Entry(name: "pin.fill", title: "Pin"),
        Entry(name: "mappin.and.ellipse", title: "Place"),
        Entry(name: "house.fill", title: "Home"),
        Entry(name: "briefcase.fill", title: "Work"),
        Entry(name: "cart.fill", title: "Shopping"),
        Entry(name: "dollarsign.circle.fill", title: "Money"),
        Entry(name: "chart.bar.fill", title: "Chart"),
        Entry(name: "gift.fill", title: "Gift"),
        Entry(name: "book.fill", title: "Book"),
        Entry(name: "graduationcap.fill", title: "Learning"),
        Entry(name: "pencil", title: "Draft"),
        Entry(name: "doc.text.fill", title: "Document"),
        Entry(name: "paperclip", title: "Paperclip"),
        Entry(name: "phone.fill", title: "Phone"),
        Entry(name: "bubble.left.fill", title: "Comment"),
        Entry(name: "hand.thumbsup.fill", title: "Thumbs Up"),
        Entry(name: "hand.thumbsdown.fill", title: "Thumbs Down"),
        Entry(name: "leaf.fill", title: "Nature"),
        Entry(name: "sun.max.fill", title: "Sun"),
        Entry(name: "moon.fill", title: "Moon"),
        Entry(name: "cloud.fill", title: "Cloud"),
        Entry(name: "airplane", title: "Travel"),
        Entry(name: "car.fill", title: "Car"),
        Entry(name: "hammer.fill", title: "Build"),
        Entry(name: "gearshape.fill", title: "Gear"),
        Entry(name: "lock.fill", title: "Locked"),
        Entry(name: "key.fill", title: "Key"),
        Entry(name: "music.note", title: "Music"),
        Entry(name: "camera.fill", title: "Camera"),
        Entry(name: "puzzlepiece.fill", title: "Puzzle"),
    ]

    private static let index: [String: Entry] = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })

    static func entry(named name: String) -> Entry? {
        index[name]
    }

    /// What a topic draws for a stored symbol: an emoji, or a name in the
    /// catalogue; nil for anything else.
    static func drawable(_ symbol: String?) -> TopicMark.Symbol? {
        guard let symbol, !symbol.isEmpty else { return nil }
        if let emoji = TopicSymbol.emoji(symbol) { return .emoji(emoji) }
        return index[symbol] == nil ? nil : .system(symbol)
    }

    /// What VoiceOver reads for a symbol: the catalogue's name, or the emoji itself.
    static func spokenName(of symbol: TopicMark.Symbol) -> String {
        switch symbol {
        case .emoji(let emoji): emoji
        case .system(let name): entry(named: name).map { String(localized: $0.title) } ?? name
        }
    }
}

/// What a topic draws before its title (MM-32): the colour's shape when
/// Differentiate Without Color asks for it, then the symbol. Part of the
/// measured size, so a change measures the topic again.
nonisolated struct TopicMark: Hashable, Sendable {
    enum Symbol: Hashable, Sendable {
        case system(String)
        case emoji(String)
    }

    var shape: TopicColor?
    var symbol: Symbol?

    static let none = TopicMark()

    var isEmpty: Bool { shape == nil && symbol == nil }
}
