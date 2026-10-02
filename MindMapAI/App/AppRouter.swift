import MindMapDomain
import Observation

/// Where the user is: the library section and the open map. Not persisted.
@Observable
final class AppRouter {
    var section: LibrarySection? = .all
    var selectedMapID: MapID?
}
