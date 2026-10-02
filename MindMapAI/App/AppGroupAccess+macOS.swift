#if os(macOS)
import Foundation
import MindMapPersistence
import Security

/// The App Group container, when this build may use it.
enum AppGroupAccess {
    /// On macOS `containerURL` returns a path even without the entitlement,
    /// and the sandbox then refuses to write there. Unsigned local builds
    /// (`MINDMAP_MAC_APP_GROUP = NO`) have no entitlement, so check it first.
    static var containerURL: URL? {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
              groups.contains(AppGroup.identifier)
        else { return nil }
        return AppGroup.containerURL()
    }
}
#endif
