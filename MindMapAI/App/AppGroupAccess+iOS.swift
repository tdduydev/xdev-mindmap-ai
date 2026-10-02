#if os(iOS)
import Foundation
import MindMapPersistence

/// The App Group container, when this build may use it.
enum AppGroupAccess {
    /// iOS returns nil without the entitlement, so no extra check is needed.
    static var containerURL: URL? {
        AppGroup.containerURL()
    }
}
#endif
