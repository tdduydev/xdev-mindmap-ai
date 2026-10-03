import Foundation
@testable import MindMapAI
import MindMapDomain
import MindMapGraph
import MindMapPersistence
import Testing

/// FR-ONB-01, FR-SYN-08 (MM-120): the sample map is made once per person, not
/// once per device, while iCloud may still be bringing the library down.
@Suite("First run with iCloud")
struct FirstRunGateTests {
    final class FakeFlag: FirstRunCloudFlag {
        var isSet = false
        func set() { isSet = true }
    }

    /// What the dependencies saw, and what the library holds before and after the wait.
    final class Fakes {
        let flag = FakeFlag()
        var account = CloudAccount.available
        var mapsBeforeImport = false
        var mapsAfterImport = false
        /// Set by the import, as another device's KVS write would arrive.
        var flagArrivesDuringWait = false
        private(set) var waited = false
        private(set) var askedAccount = false

        func gate(cloud: Bool) -> FirstRunGate {
            FirstRunGate(
                isCloudStoreOn: cloud,
                cloudFlag: flag,
                accountStatus: {
                    self.askedAccount = true
                    return self.account
                },
                waitForFirstImport: { flag in
                    self.waited = true
                    if self.flagArrivesDuringWait { flag.set() }
                },
                libraryHasMaps: { self.waited ? self.mapsAfterImport : self.mapsBeforeImport }
            )
        }
    }

    // MARK: iCloud off: as MM-108

    @Test func iCloudOffAndEmptyMakesTheSample() async {
        let fakes = Fakes()
        #expect(await fakes.gate(cloud: false).decide() == .createSample)
        #expect(!fakes.waited)
        #expect(!fakes.askedAccount)
    }

    @Test func iCloudOffWithMapsSkipsAndLeavesTheCloudFlag() async {
        let fakes = Fakes()
        fakes.mapsBeforeImport = true
        let gate = fakes.gate(cloud: false)
        #expect(await gate.decide() == .skip)
        gate.recordCompleted()
        // A device keeping its maps local must not stop another one's sample.
        #expect(!fakes.flag.isSet)
    }

    @Test func iCloudOffIgnoresTheCloudFlag() async {
        let fakes = Fakes()
        fakes.flag.isSet = true
        #expect(await fakes.gate(cloud: false).decide() == .createSample)
    }

    // MARK: iCloud on

    @Test func mapsOnTheDeviceSkipAndTellTheOtherDevices() async {
        let fakes = Fakes()
        fakes.mapsBeforeImport = true
        #expect(await fakes.gate(cloud: true).decide() == .skip)
        #expect(fakes.flag.isSet)
        #expect(!fakes.waited)
    }

    @Test func cloudFlagSkipsWithoutWaiting() async {
        let fakes = Fakes()
        fakes.flag.isSet = true
        #expect(await fakes.gate(cloud: true).decide() == .skip)
        #expect(!fakes.waited)
        #expect(!fakes.askedAccount)
    }

    @Test(arguments: [CloudAccount.noAccount, .restricted, .temporarilyUnavailable, .unknown])
    func noUsableAccountMakesTheSampleWithoutWaiting(account: CloudAccount) async {
        let fakes = Fakes()
        fakes.account = account
        #expect(await fakes.gate(cloud: true).decide() == .createSample)
        #expect(!fakes.waited)
    }

    @Test func importBringingMapsSkips() async {
        let fakes = Fakes()
        fakes.mapsAfterImport = true
        #expect(await fakes.gate(cloud: true).decide() == .skip)
        #expect(fakes.waited)
        #expect(fakes.flag.isSet)
    }

    @Test func importLeavingTheLibraryEmptyMakesTheSample() async {
        let fakes = Fakes()
        let gate = fakes.gate(cloud: true)
        #expect(await gate.decide() == .createSample)
        #expect(fakes.waited)
        #expect(!fakes.flag.isSet)
        // RootView records it once the sample is stored.
        gate.recordCompleted()
        #expect(fakes.flag.isSet)
    }

    @Test func flagArrivingDuringTheWaitSkips() async {
        let fakes = Fakes()
        fakes.flagArrivesDuringWait = true
        #expect(await fakes.gate(cloud: true).decide() == .skip)
    }

    // MARK: Waiting for the first import

    @Test func waitEndsAtOnceWhenTheImportFinished() async {
        let firstImport = FirstCloudImport(observing: false)
        firstImport.markFinished()
        #expect(await firstImport.wait(for: FakeFlag(), timeout: .seconds(30)))
    }

    @Test func waitEndsAtOnceWhenTheFlagIsSet() async {
        let flag = FakeFlag()
        flag.isSet = true
        #expect(await FirstCloudImport(observing: false).wait(for: flag, timeout: .seconds(30)))
    }

    @Test func waitEndsWhenTheImportFinishesLater() async {
        let firstImport = FirstCloudImport(observing: false)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            firstImport.markFinished()
        }
        #expect(await firstImport.wait(for: FakeFlag(), timeout: .seconds(30)))
    }

    @Test func waitGivesUpAtTheTimeout() async {
        let clock = ContinuousClock()
        let start = clock.now
        #expect(await !FirstCloudImport(observing: false).wait(for: FakeFlag(), timeout: .milliseconds(300)))
        #expect(clock.now - start < .seconds(5))
    }

    // MARK: What counts as having maps

    /// The same check runs after the import: a map that arrived from iCloud
    /// in Recently Deleted still means the person is not new.
    @Test func recentlyDeletedCountsAsHavingMaps() async throws {
        let repository = try PersistenceController.makeRepository(at: .inMemory)
        let library = LibraryModel(repository: repository)
        #expect(await !library.reloadHasAnyMap())

        let graph = GraphState.newMap(title: "From another device")
        try await repository.create(graph)
        try await repository.moveToRecentlyDeleted(graph.map.id, at: .now)
        #expect(await library.reloadHasAnyMap())
        #expect(library.maps.isEmpty)
    }
}
