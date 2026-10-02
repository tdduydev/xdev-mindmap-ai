import Foundation
import MindMapDomain

enum LibrarySection: String, CaseIterable, Identifiable, Hashable {
    case all
    case recent
    case favorites
    /// Maps deleted in the last 30 days (FR-LIB-11); fed from
    /// `LibraryModel.deletedMaps`, never from the live list.
    case recentlyDeleted

    /// How many maps Recent shows.
    static let recentLimit = 20

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .all: "All Maps"
        case .recent: "Recent"
        case .favorites: "Favorites"
        case .recentlyDeleted: "Recently Deleted"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .recent: "clock"
        case .favorites: "star"
        case .recentlyDeleted: "trash"
        }
    }

    /// All maps by title, Recent by last edit, Favorites by title, Recently
    /// Deleted by deletion, most recent first.
    func maps(from maps: [MindMap]) -> [MindMap] {
        switch self {
        case .all:
            maps.sorted(by: Self.byTitle)
        case .recent:
            Array(maps.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.recentLimit))
        case .favorites:
            maps.filter(\.isFavorite).sorted(by: Self.byTitle)
        case .recentlyDeleted:
            maps.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        }
    }

    private static func byTitle(_ lhs: MindMap, _ rhs: MindMap) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
