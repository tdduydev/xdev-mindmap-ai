import Darwin
import Foundation
import Testing

/// Runs a test or suite that drives an `SKTestSession` only once no other test
/// run on the Mac does.
///
/// StoreKit Testing keeps its transactions per app, not per process: two test
/// runs of the same bundle ID (two worktrees, an agent and the leader) see each
/// other's purchases, and one's `clearTransactions()` wipes the other's (MM-69).
/// `.serialized` only orders tests inside one process, so the lock is a file.
/// The process keeps it until it exits: releasing it when the suite ended was
/// not enough, because the end of that process still reset StoreKit while the
/// next run's suite was buying.
// Nonisolated: the target defaults to the main actor, and TestScoping is not.
nonisolated struct StoreKitTestLock: SuiteTrait, TestTrait, TestScoping {
    // @concurrent: Swift Testing declares the closure without nonisolated(nonsending).
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable @concurrent () async throws -> Void
    ) async throws {
        try await ProcessLock.shared.acquire()
        try await function()
    }

    private actor ProcessLock {
        static let shared = ProcessLock()

        /// The temporary directory is the same for every process of this app and
        /// user, sandboxed or not, so every test run finds the same file.
        private static let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "asia.xdev.mindmapai.storekit-tests.lock").path

        /// Shared so that a second caller in this process waits for the first one
        /// instead of opening the file again, which would wait on itself.
        private var acquiring: Task<Void, any Error>?

        func acquire() async throws {
            if acquiring == nil {
                acquiring = Task {
                    let descriptor = open(Self.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
                    guard descriptor >= 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    // Never closed: the kernel releases the lock when the process exits.
                    // Polled instead of a blocking flock so the wait does not hold a
                    // thread of the cooperative pool.
                    // Another whole app test run can hold it for minutes; a hung one
                    // fails this run instead of stalling it.
                    let deadline = ContinuousClock.now + .seconds(15 * 60)
                    while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
                        guard ContinuousClock.now < deadline else { throw POSIXError(.ETIMEDOUT) }
                        try await Task.sleep(for: .milliseconds(200))
                    }
                }
            }
            try await acquiring?.value
        }
    }
}

extension Trait where Self == StoreKitTestLock {
    /// See `StoreKitTestLock`.
    static var storeKitTestLock: Self { Self() }
}
