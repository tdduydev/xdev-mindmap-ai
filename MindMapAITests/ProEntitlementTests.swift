import Foundation
@testable import MindMapAI
import StoreKit
import StoreKitTest
import Testing

/// Purchases against the local StoreKit configuration (MindMapAI.storekit).
/// Serialized: an `SKTestSession` changes StoreKit for the whole process.
@Suite("Pro entitlement", .serialized)
struct ProEntitlementTests {
    let session: SKTestSession

    init() throws {
        // The file is a resource of this test bundle, not of the shipped app.
        let url = try #require(
            Bundle.allBundles.lazy.compactMap { $0.url(forResource: "MindMapAI", withExtension: "storekit") }.first
        )
        session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.clearTransactions()
    }

    @Test func loadsTheProProductWithItsPrice() async throws {
        let store = ProEntitlement()
        await store.start()

        let product = try #require(store.product)
        #expect(product.id == ProEntitlement.productID)
        #expect(product.type == .nonConsumable)
        #expect(product.price == Decimal(string: "14.99"))
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

        #expect(store.isUnlocked)
        #expect(store.purchaseState == .idle)
        for feature in ProFeature.allCases {
            #expect(store.allows(feature))
        }
    }

    /// The launch check: a new process sees a purchase made earlier.
    @Test func launchFindsAnEarlierPurchase() async throws {
        _ = try await session.buyProduct(identifier: ProEntitlement.productID)

        let store = ProEntitlement()
        await store.start()

        #expect(store.isUnlocked)
    }

    /// A purchase from outside the app (another device, Ask to Buy approval)
    /// arrives through `Transaction.updates` while the app runs.
    @Test func purchaseFromElsewhereUnlocksWhileRunning() async throws {
        let store = ProEntitlement()
        await store.start()
        #expect(!store.isUnlocked)

        _ = try await session.buyProduct(identifier: ProEntitlement.productID)

        #expect(await eventually { store.isUnlocked })
    }

    @Test func refundLocksAgain() async throws {
        let store = ProEntitlement()
        await store.start()
        let transaction = try await session.buyProduct(identifier: ProEntitlement.productID)
        await store.refresh()
        #expect(store.isUnlocked)

        try session.refundTransaction(identifier: UInt(transaction.id))
        await store.refresh()

        #expect(!store.isUnlocked)
    }

    @Test func askToBuyStaysPendingAndUnlocksOnApproval() async throws {
        session.askToBuyEnabled = true
        let store = ProEntitlement()
        await store.start()

        await store.purchase { try await $0.purchase() }
        #expect(store.purchaseState == .pending)
        #expect(!store.isUnlocked)

        let pending = try #require(session.allTransactions().first { $0.productIdentifier == ProEntitlement.productID })
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

    /// Waits for a change that arrives asynchronously through `Transaction.updates`.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<50 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }
}

@Suite("Pro features")
struct ProFeatureTests {
    /// docs/pricing.md: advanced export, extra themes, advanced AI, voice input.
    @Test func listMatchesThePricingDecision() {
        #expect(ProFeature.allCases == [
            .vectorPDFExport, .highResolutionPNGExport, .opmlExport,
            .extraThemes,
            .generateMapFromDescription, .summarizeWholeMap, .findMissingIdeas,
            .voiceInput,
        ])
    }

    @Test func everyFeatureHasATitleAndIcon() {
        let titles = ProFeature.allCases.map { String(localized: $0.title) }
        #expect(Set(titles).count == titles.count)
        #expect(ProFeature.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }
}
