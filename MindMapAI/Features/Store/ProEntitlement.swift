import Observation
import OSLog
import StoreKit

/// Whether this Apple Account owns MindMap AI Pro, and the purchase and restore
/// flows. StoreKit 2 only: the signed transactions are the source of truth, so
/// nothing is cached in defaults and there is no receipt to parse.
@Observable
final class ProEntitlement {
    /// The one non-consumable. Universal purchase shares it across Mac, iPad and iPhone.
    static let productID = "asia.xdev.mindmapai.pro"

    enum ProductState: Equatable {
        case loading
        case loaded(Product)
        /// The App Store gave no product: offline, or not reachable from here.
        case unavailable
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        /// Waiting on Ask to Buy or a payment step; the result arrives through `Transaction.updates`.
        case pending
        case failed
    }

    enum RestoreState: Equatable {
        case idle
        case restoring
        case restored
        case nothingToRestore
        case failed
    }

    /// How a Redeem Code sheet ended. The sheet shows Apple's own confirmation,
    /// so only a failure needs words from the app.
    enum RedeemOutcome: Equatable {
        case redeemed
        case cancelled
        case failed
    }

    private(set) var isUnlocked = false
    private(set) var productState = ProductState.loading
    private(set) var purchaseState = PurchaseState.idle
    private(set) var restoreState = RestoreState.idle

    private let syncWithAppStore: () async throws -> Void
    private var updates: Task<Void, Never>?

    /// - Parameter syncWithAppStore: what Restore Purchases asks the App Store
    ///   to do; tests replace it because `AppStore.sync()` asks to sign in.
    init(syncWithAppStore: @escaping () async throws -> Void = { try await AppStore.sync() }) {
        self.syncWithAppStore = syncWithAppStore
    }

    isolated deinit {
        updates?.cancel()
    }

    var product: Product? {
        if case .loaded(let product) = productState { product } else { nil }
    }

    /// The single question every Pro feature asks. Core mind mapping never asks (App Review 3.1.1).
    func allows(_ feature: ProFeature) -> Bool {
        isUnlocked
    }

    /// Call once at launch. Later calls only refresh, so every window can call it.
    func start() async {
        if updates == nil {
            // Purchases made elsewhere (another device, Ask to Buy approval,
            // a refund) arrive here while the app runs.
            updates = Task { [weak self] in
                for await update in Transaction.updates {
                    guard let self else { return }
                    await self.process(update)
                }
            }
            for await unfinished in Transaction.unfinished {
                await process(unfinished)
            }
        }
        await refresh()
        if product == nil {
            await loadProduct()
        }
    }

    /// Reads the current entitlements again. Runs at launch and whenever the app becomes active.
    func refresh() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, unlocks(transaction) {
                unlocked = true
            }
        }
        isUnlocked = unlocked
    }

    func loadProduct() async {
        productState = .loading
        do {
            if let product = try await Product.products(for: [Self.productID]).first {
                productState = .loaded(product)
            } else {
                Log.store.error("The App Store returned no Pro product")
                productState = .unavailable
            }
        } catch {
            Log.store.error("Loading the Pro product failed: \(error.localizedDescription, privacy: .public)")
            productState = .unavailable
        }
    }

    /// Buys Pro through `buy`: SwiftUI's `PurchaseAction` in the app, so the
    /// confirmation sheet attaches to the right window; `Product.purchase()` in tests.
    func purchase(using buy: (Product) async throws -> Product.PurchaseResult) async {
        guard let product, purchaseState != .purchasing else { return }
        purchaseState = .purchasing
        do {
            switch try await buy(product) {
            case .success(let verification):
                await process(verification)
                purchaseState = isUnlocked ? .idle : .failed
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            Log.store.error("The Pro purchase failed: \(error.localizedDescription, privacy: .public)")
            purchaseState = .failed
        }
    }

    func restorePurchases() async {
        guard restoreState != .restoring else { return }
        restoreState = .restoring
        do {
            try await syncWithAppStore()
        } catch StoreKitError.userCancelled {
            restoreState = .idle
            return
        } catch {
            Log.store.error("Restore Purchases failed: \(error.localizedDescription, privacy: .public)")
            restoreState = .failed
            return
        }
        await refresh()
        restoreState = isUnlocked ? .restored : .nothingToRestore
    }

    /// Called when the offer code sheet closes. A redeemed code for Pro is a
    /// transaction like a purchase: it reaches `Transaction.updates` too, but the
    /// entitlements are read again so Pro opens without waiting for that.
    func finishRedemption(_ result: Result<Void, any Error>) async -> RedeemOutcome {
        switch result {
        case .success:
            await refresh()
            return .redeemed
        case .failure(StoreKitError.userCancelled):
            return .cancelled
        case .failure(let error):
            Log.store.error("Redeeming an offer code failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// The macOS 27 and iOS 27 sheet hands back the transaction it made.
    func finishRedemption(transaction result: Result<VerificationResult<Transaction>, any Error>) async -> RedeemOutcome {
        if case .success(let verification) = result {
            await process(verification)
        }
        return await finishRedemption(result.map { _ in })
    }

    func dismissRestoreResult() {
        if restoreState != .restoring { restoreState = .idle }
    }

    private func process(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            // An unverified transaction unlocks nothing and stays unfinished,
            // so StoreKit offers it again.
            Log.store.error("Ignored a transaction that failed verification")
            return
        }
        if unlocks(transaction) {
            isUnlocked = true
            if purchaseState == .pending { purchaseState = .idle }
        } else if transaction.productID == Self.productID {
            // A revoked transaction is not the only one: with Family Sharing the
            // person may still own Pro through their own purchase or another member.
            await refresh()
        }
        await transaction.finish()
    }

    private func unlocks(_ transaction: Transaction) -> Bool {
        transaction.productID == Self.productID && transaction.revocationDate == nil
    }
}
