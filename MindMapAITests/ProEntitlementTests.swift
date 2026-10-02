import Foundation
@testable import MindMapAI
import StoreKit
import StoreKitTest
import Testing

/// Purchases against the local StoreKit configuration (MindMapAI.storekit).
/// Serialized: an `SKTestSession` changes StoreKit for the whole process, and
/// other test runs of the app share its transactions (`StoreKitTestLock`).
@Suite("Pro entitlement", .serialized, .storeKitTestLock)
struct ProEntitlementTests {
    let session: SKTestSession

    init() async throws {
        // The file is a resource of this test bundle, not of the shipped app.
        let url = try #require(
            Bundle.allBundles.lazy.compactMap { $0.url(forResource: "MindMapAI", withExtension: "storekit") }.first
        )
        session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.askToBuyEnabled = false
        // StoreKit applies the clear asynchronously; start each test from nothing
        // bought. A refunded transaction is no entitlement but still listed, and
        // the Ask to Buy test must not find an earlier test's one. On a busy Mac
        // the clear took over five seconds, and a test that went on anyway found
        // the previous test's purchase (restoreWithNothingBought, MM-88), so the
        // clear is asked again and a test never starts on a dirty store.
        try await Self.clear(session)
    }

    private static func clear(_ session: SKTestSession) async throws {
        var cleared = false
        for _ in 0..<3 where !cleared {
            session.clearTransactions()
            cleared = await eventually { await !hasProEntitlement() && session.allTransactions().isEmpty }
        }
        try #require(cleared, "StoreKit still lists transactions after clearTransactions()")
    }

    /// Runs a scenario again, from a cleared store, when StoreKit changed under
    /// it from outside this process. `StoreKitTestLock` keeps other runs of
    /// these tests out, but not everything that touches the app's StoreKit
    /// store: while a macOS UI test run launched the app, a purchase never
    /// arrived or a refund left Pro unlocked for 30 s (MM-88). `attempt`
    /// returns nil when the scenario held, or what went wrong and whether it
    /// came from outside; only an outside change is retried.
    private func retryingOutsideChanges(_ attempt: () async throws -> (problem: String, outside: Bool)?) async throws {
        for run in 1...3 {
            guard let failure = try await attempt() else { return }
            guard failure.outside, run < 3 else {
                Issue.record("\(failure.problem)")
                return
            }
            print("StoreKit changed outside this test (\(failure.problem)); clearing and running again")
            try await Self.clear(session)
        }
    }

    /// True once StoreKit no longer lists the transaction this test made.
    private func lost(_ transaction: StoreKit.Transaction) -> Bool {
        !session.allTransactions().contains { UInt64($0.identifier) == transaction.id }
    }

    /// True when Pro comes from a transaction this test did not make.
    private static func entitledByAnother(than transaction: StoreKit.Transaction) async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let other) = result, other.productID == ProEntitlement.productID, other.id != transaction.id { return true }
        }
        return false
    }

    @Test func loadsTheProProductWithItsPrice() async throws {
        let store = ProEntitlement()
        await store.start()

        let product = try #require(store.product)
        #expect(product.id == ProEntitlement.productID)
        #expect(product.type == .nonConsumable)
        // The paywall shows displayPrice only. Under StoreKitTest on Xcode 27,
        // `price` came back as 14 for this 14.99 product while displayPrice read
        // "$14.99", so the test checks what people see.
        #expect(product.displayPrice.contains("14.99"))
    }

    @Test func lockedUntilBought() async {
        let store = ProEntitlement()
        await store.start()

        #expect(!store.isUnlocked)
        for feature in ProFeature.allCases {
            #expect(!store.allows(feature))
        }
    }

    @Test func purchaseUnlocksEveryProFeature() async {
        let store = ProEntitlement()
        await store.start()

        await store.purchase { try await $0.purchase() }

        #expect(await Self.eventually { await store.refresh(); return store.isUnlocked })
        #expect(store.purchaseState == .idle)
        for feature in ProFeature.allCases {
            #expect(store.allows(feature))
        }
    }

    /// The launch check: a new process sees a purchase made earlier.
    @Test func launchFindsAnEarlierPurchase() async throws {
        _ = try await session.buyProduct(identifier: ProEntitlement.productID)
        #expect(await Self.eventually { await Self.hasProEntitlement() })

        let store = ProEntitlement()
        await store.start()

        #expect(await Self.eventually { await store.refresh(); return store.isUnlocked })
    }

    /// A purchase from outside the app (another device, Ask to Buy approval)
    /// arrives through `Transaction.updates` while the app runs.
    @Test func purchaseFromElsewhereUnlocksWhileRunning() async throws {
        try await retryingOutsideChanges {
            let store = ProEntitlement()
            await store.start()
            #expect(!store.isUnlocked)

            let transaction = try await session.buyProduct(identifier: ProEntitlement.productID)

            guard await eventually({ store.isUnlocked || lost(transaction) }) else {
                return ("the purchase did not reach Transaction.updates", false)
            }
            return store.isUnlocked ? nil : ("StoreKit lost the purchase", true)
        }
    }

    @Test func refundLocksAgain() async throws {
        try await retryingOutsideChanges {
            let store = ProEntitlement()
            await store.start()
            let transaction = try await session.buyProduct(identifier: ProEntitlement.productID)
            guard await Self.eventually({ await store.refresh(); return store.isUnlocked || lost(transaction) }) else {
                return ("the purchase did not unlock Pro", false)
            }
            if !store.isUnlocked { return ("StoreKit lost the purchase", true) }

            try session.refundTransaction(identifier: UInt(transaction.id))

            if await Self.eventually({ await store.refresh(); return !store.isUnlocked }) { return nil }
            return await Self.entitledByAnother(than: transaction)
                ? ("another transaction unlocks Pro", true)
                : ("the refund did not lock Pro", false)
        }
    }

    @Test func askToBuyStaysPendingAndUnlocksOnApproval() async throws {
        session.askToBuyEnabled = true
        let store = ProEntitlement()
        await store.start()

        await store.purchase { try await $0.purchase() }
        #expect(store.purchaseState == .pending)
        #expect(!store.isUnlocked)

        let pending = try #require(session.allTransactions().first {
            $0.productIdentifier == ProEntitlement.productID && $0.pendingAskToBuyConfirmation
        })
        try session.approveAskToBuyTransaction(identifier: pending.identifier)

        #expect(await eventually { store.isUnlocked })
        #expect(store.purchaseState == .idle)
    }

    @Test func cancelledPurchaseChangesNothing() async {
        let store = ProEntitlement()
        await store.start()

        await store.purchase { _ in .userCancelled }

        #expect(!store.isUnlocked)
        #expect(store.purchaseState == .idle)
    }

    @Test func failedPurchaseIsReported() async {
        let store = ProEntitlement()
        await store.start()

        await store.purchase { _ in throw StoreKitError.networkError(URLError(.notConnectedToInternet)) }

        #expect(store.purchaseState == .failed)
        #expect(!store.isUnlocked)
    }

    @Test func restoreFindsAnEarlierPurchase() async throws {
        _ = try await session.buyProduct(identifier: ProEntitlement.productID)
        #expect(await Self.eventually { await Self.hasProEntitlement() })
        let store = ProEntitlement(syncWithAppStore: {})

        await store.restorePurchases()

        #expect(store.restoreState == .restored)
        #expect(store.isUnlocked)
    }

    @Test func restoreWithNothingBought() async {
        let store = ProEntitlement(syncWithAppStore: {})

        await store.restorePurchases()

        #expect(store.restoreState == .nothingToRestore)
        #expect(!store.isUnlocked)
    }

    @Test func restoreFailureAndCancel() async {
        let failing = ProEntitlement(syncWithAppStore: { throw StoreKitError.networkError(URLError(.timedOut)) })
        await failing.restorePurchases()
        #expect(failing.restoreState == .failed)
        failing.dismissRestoreResult()
        #expect(failing.restoreState == .idle)

        let cancelled = ProEntitlement(syncWithAppStore: { throw StoreKitError.userCancelled })
        await cancelled.restorePurchases()
        #expect(cancelled.restoreState == .idle)
    }

    /// The offer code sheet itself cannot be driven by StoreKitTest, so the
    /// code is stood in for by a transaction made outside the app, as the App
    /// Store makes one when a Pro gift code is redeemed.
    @Test func redeemedCodeUnlocksPro() async throws {
        let store = ProEntitlement()
        await store.start()
        _ = try await session.buyProduct(identifier: ProEntitlement.productID)
        #expect(await Self.eventually { await Self.hasProEntitlement() })

        let outcome = await store.finishRedemption(.success(()))

        #expect(outcome == .redeemed)
        #expect(store.isUnlocked)
    }

    @Test func redeemCancelAndFailureChangeNothing() async {
        let store = ProEntitlement()
        await store.start()

        #expect(await store.finishRedemption(.failure(StoreKitError.userCancelled)) == .cancelled)
        #expect(await store.finishRedemption(.failure(StoreKitError.networkError(URLError(.timedOut)))) == .failed)
        #expect(!store.isUnlocked)
    }

    /// Waits for a change that arrives asynchronously through `Transaction.updates`.
    /// StoreKit delivers purchases, refunds and clears asynchronously, and much
    /// later on a Mac running several builds: five seconds was not enough
    /// (MM-88). The deadline is in time, not tries, so a slow `condition` does
    /// not stretch it; a met condition returns at once, so it costs nothing.
    private static func eventually(within limit: Duration = .seconds(30), _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await condition()
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        await Self.eventually(condition)
    }

    private static func hasProEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == ProEntitlement.productID { return true }
        }
        return false
    }
}

@Suite("Pro features")
struct ProFeatureTests {
    /// docs/pricing.md: advanced export, extra themes, advanced AI, voice input.
    @Test func listMatchesThePricingDecision() {
        #expect(ProFeature.allCases == [
            .vectorPDFExport, .highResolutionPNGExport,
            .extraThemes,
            .generateMapFromDescription, .summarizeWholeMap, .findMissingIdeas,
            .voiceInput,
        ])
    }

    /// One name per thing: the paywall names the AI tool as the AI menu does.
    @Test func paywallNamesMatchTheMenus() {
        #expect(String(localized: ProFeature.findMissingIdeas.title) == String(localized: "Find Missing Topics"))
    }

    @Test func everyFeatureHasATitleAndIcon() {
        let titles = ProFeature.allCases.map { String(localized: $0.title) }
        #expect(Set(titles).count == titles.count)
        #expect(ProFeature.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }
}
