import Foundation
import MindMapDomain

enum LibrarySection: String, CaseIterable, Identifiable, Hashable {
    case all
    case recent
    case favorites

    /// How many maps Recent shows.
    static let recentLimit = 20

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .all: "All Maps"
        case .recent: "Recent"
        case .favorites: "Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .recent: "clock"
        case .favorites: "star"
        }
    }

    /// All maps by title, Recent by last edit, Favorites by title.
    func maps(from maps: [MindMap]) -> [MindMap] {
        switch self {
        case .all:
            maps.sorted(by: Self.byTitle)
        case .recent:
            Array(maps.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.recentLimit))
        case .favorites:
            maps.filter(\.isFavorite).sorted(by: Self.byTitle)
        }
    }

    private static func byTitle(_ lhs: MindMap, _ rhs: MindMap) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
