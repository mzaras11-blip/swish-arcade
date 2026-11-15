import Foundation
import StoreKit

/// In-app purchase manager (StoreKit 2).
///
/// Sells one non-consumable: "Remove Ads".
/// Before release, create the product in App Store Connect with the ID below
/// (non-consumable, e.g. $4.99) and sign the Paid Apps agreement.
/// Until then the product lookup simply returns nothing and the UI stays quiet.
///
/// Note: deliberately NOT @MainActor — all @Published writes are bounced
/// through MainActor.run so this compiles cleanly under Swift 5.
final class StoreManager: ObservableObject {
    static let shared = StoreManager()
    static let removeAdsID = "com.swishgame.arcade.remove_ads"

    @Published var hasRemoveAds = false
    @Published var removeAdsProduct: Product?
    @Published var storeError: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await self?.handle(transaction)
                }
            }
        }
        Task { [weak self] in
            await self?.refresh()
        }
    }

    /// Looks up the product and checks existing entitlements.
    /// StoreKit is authoritative: a stale local grant (e.g. after a refund
    /// or revoke) is cleared when no active entitlement exists.
    func refresh() async {
        do {
            let products = try await Product.products(for: [Self.removeAdsID])
            let first = products.first
            await MainActor.run { self.removeAdsProduct = first }
        } catch {
            await MainActor.run { self.removeAdsProduct = nil }
        }

        var entitled = false
        for await result in Transaction.currentEntitlements {
            // Only .verified transactions count: the JWS signature is
            // checked against Apple's root certificate on-device.
            // Anything unverified is ignored, never granted.
            if case .verified(let transaction) = result,
               transaction.productID == Self.removeAdsID {
                entitled = true
                await transaction.finish()
                break
            }
        }
        if entitled {
            await MainActor.run { self.setOwned() }
        } else {
            // No active entitlement: drop any stale local grant so a
            // refunded or revoked purchase stops unlocking the app.
            UserDefaults.standard.removeObject(forKey: "swish_remove_ads")
            await MainActor.run { self.hasRemoveAds = false }
        }
    }

    func purchase() async {
        await MainActor.run { self.storeError = nil }
        let product = await MainActor.run { self.removeAdsProduct }
        guard let product = product else {
            await MainActor.run { self.storeError = "Store isn't available yet." }
            return
        }
        do {
            // purchase() presents system UI; call it directly (it is async).
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await handle(transaction)
                } else {
                    await MainActor.run {
                        self.storeError = "Purchase couldn't be verified."
                    }
                }
            case .userCancelled:
                break
            case .pending:
                await MainActor.run {
                    self.storeError = "Purchase is pending approval."
                }
            @unknown default:
                break
            }
        } catch {
            await MainActor.run {
                self.storeError = "Purchase failed. Please try again."
            }
        }
    }

    func restore() async {
        await MainActor.run { self.storeError = nil }
        do {
            try await AppStore.sync()
        } catch {
            // sync can fail quietly; refresh() still checks entitlements
        }
        await refresh()
        let owned = await MainActor.run { self.hasRemoveAds }
        if !owned {
            await MainActor.run {
                self.storeError = "No purchases found to restore."
            }
        }
    }

    private func handle(_ transaction: Transaction) async {
        if transaction.productID == Self.removeAdsID {
            await MainActor.run { self.setOwned() }
        }
        await transaction.finish()
    }

    private func setOwned() {
        hasRemoveAds = true
        UserDefaults.standard.set(true, forKey: "swish_remove_ads")
    }
}
