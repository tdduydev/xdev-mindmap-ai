import MindMapDomain
import Observation

/// A map an intent or Spotlight asked to open. Intents run outside any
/// window, so they leave the request here and the frontmost window that sees
/// it opens the map and clears it.
@Observable
final class MapOpenRequests {
    private(set) var pending: MapID?

    func open(_ mapID: MapID) {
        pending = mapID
    }

    /// Returns the request once, so two windows do not both open it.
    func take() -> MapID? {
        defer { pending = nil }
        return pending
    }
}
