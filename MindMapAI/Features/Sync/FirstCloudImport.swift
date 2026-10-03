import CoreData
import Foundation

/// Whether CloudKit's first import of this launch has finished, so the first
/// run can tell an empty iCloud library from one still downloading (MM-120).
/// Created before the store opens: the import can end before any window loads.
nonisolated final class FirstCloudImport: @unchecked Sendable {
    /// How long an empty library waits for iCloud before it gets the sample.
    /// Long enough for a first import on a usual connection [Đề xuất]; the
    /// iCloud key-value flag ends the wait sooner on a second device.
    static let timeout: Duration = .seconds(20)

    private let lock = NSLock()
    private var finished = false
    private var observer: (any NSObjectProtocol)?

    /// `observing` is false when the store stays on this device.
    init(observing: Bool) {
        guard observing else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil
        ) { [weak self] notification in
            let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            // A failed import (offline, say) is not "iCloud is empty": the
            // wait goes on until a later one succeeds or the time is up.
            guard let event, event.type == .import, event.endDate != nil, event.succeeded else { return }
            self?.markFinished()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var hasFinished: Bool {
        lock.withLock { finished }
    }

    func markFinished() {
        lock.withLock { finished = true }
    }

    /// Polls rather than observing the flag too: both change rarely, and a
    /// poll of a quarter second for at most `timeout` costs nothing. False
    /// when the time ran out with neither.
    @discardableResult @MainActor
    func wait(for flag: any FirstRunCloudFlag, timeout: Duration = timeout) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !hasFinished, !flag.isSet, clock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                break
            }
        }
        return hasFinished || flag.isSet
    }
}
