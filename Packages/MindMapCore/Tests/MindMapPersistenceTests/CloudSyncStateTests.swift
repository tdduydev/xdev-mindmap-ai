import Foundation
import MindMapPersistence
import Testing

/// What Settings and the status line say about sync (FR-SYN-03).
@Suite("Sync state")
struct CloudSyncStateTests {
    private func state(
        enabled: Bool = true,
        available: Bool = true,
        account: CloudAccount = .available,
        online: Bool = true,
        activity: CloudSyncActivity = CloudSyncActivity()
    ) -> CloudSyncState {
        CloudSyncState(isEnabled: enabled, isAvailable: available, account: account, isNetworkReachable: online, activity: activity)
    }

    private func activity(_ steps: [(UUID, Bool, CloudSyncFailure?)]) -> CloudSyncActivity {
        var activity = CloudSyncActivity()
        for (id, finished, failure) in steps { activity.record(id, finished: finished, failure: failure) }
        return activity
    }

    @Test func aBuildWithoutICloudSaysSoWhateverElse() {
        #expect(state(enabled: false, available: false, account: .noAccount) == .unavailable)
    }

    @Test func offInTheAppComesBeforeTheAccount() {
        #expect(state(enabled: false, account: .noAccount) == .off)
    }

    @Test func accountStates() {
        #expect(state(account: .noAccount) == .notSignedIn)
        #expect(state(account: .restricted) == .restricted)
        #expect(state(account: .temporarilyUnavailable) == .accountNeedsAttention)
        #expect(state(account: .unknown) == .upToDate)
    }

    @Test func offlineIsWaitingNotAnError() {
        #expect(state(online: false) == .waitingForNetwork)
        let failed = activity([(UUID(), true, .network)])
        #expect(state(activity: failed) == .waitingForNetwork)
        #expect(CloudSyncState.waitingForNetwork.isActive)
    }

    @Test func aRunningStepIsSyncingUntilItEnds() {
        let id = UUID()
        #expect(state(activity: activity([(id, false, nil)])) == .syncing)
        #expect(state(activity: activity([(id, false, nil), (id, true, nil)])) == .upToDate)
    }

    @Test func aFailureStaysUntilAStepSucceeds() {
        let failed = activity([(UUID(), true, .quotaExceeded)])
        #expect(state(activity: failed) == .error(.quotaExceeded))
        var recovered = failed
        recovered.record(UUID(), finished: true)
        #expect(state(activity: recovered) == .upToDate)
    }

    @Test func aLostAccountMidSyncReadsAsSignedOut() {
        #expect(state(activity: activity([(UUID(), true, .notAuthenticated)])) == .notSignedIn)
    }

    @Test func theStatusLineStaysQuietUnlessSomethingHappens() {
        let shown: [CloudSyncState] = [.syncing, .waitingForNetwork, .error(.other)]
        let quiet: [CloudSyncState] = [.off, .unavailable, .notSignedIn, .restricted, .accountNeedsAttention, .upToDate]
        #expect(shown.filter { !$0.isWorthShowing }.isEmpty)
        #expect(quiet.filter(\.isWorthShowing).isEmpty)
    }
}
