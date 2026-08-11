import Foundation
import Combine
import StoreKit

/// A currently-active "Hour Tracker Pro" subscription, resolved from
/// `Transaction.currentEntitlements` + `Product.SubscriptionInfo.Status`.
struct ActiveSubscriptionInfo {
    let productID: String
    /// Renewal (or expiration, if not renewing) date of the current period.
    let expirationDate: Date?
    /// True if the subscription is set to auto-renew at `expirationDate`.
    let willAutoRenew: Bool

    /// "You're on Hour Tracker Pro — renews Aug 15, 2026" when a renewal
    /// date is known; the bare fallback "Active" otherwise.
    var settingsStatusLine: String {
        guard let expirationDate else { return "Active" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: expirationDate)
        return willAutoRenew
            ? "You're on Hour Tracker Pro — renews \(dateString)"
            : "You're on Hour Tracker Pro — active until \(dateString)"
    }
}

/// App-wide source of truth for the "Hour Tracker Pro" entitlement.
///
/// Backed by native StoreKit 2 (`Product` / `Transaction` / `AppStore`).
/// Two auto-renewable subscriptions — monthly and yearly — live in one
/// subscription group; owning either grants Pro.
///
/// `isPremium` is cached in `UserDefaults` so a cold launch never flashes a
/// banner ad at a Pro user before StoreKit finishes its first entitlement
/// check.
@MainActor
final class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    /// Product identifiers, in the "hourtracker_pro" subscription group.
    ///
    /// The monthly id carries a `.v2` suffix because the original
    /// `…pro.monthly` product was deleted in App Store Connect, and Apple
    /// reserves product ids permanently — a deleted id can never be
    /// recreated. Do NOT "clean this up" back to the original; it will fail
    /// to create with ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE.
    static let monthlyProductID = "com.loganh.HourTracker.pro.monthly.v2"
    static let yearlyProductID = "com.loganh.HourTracker.pro.yearly"
    static let allProductIDs: Set<String> = [monthlyProductID, yearlyProductID]

    @Published private(set) var isPremium: Bool
    /// Convenience price string for the cheapest available plan (monthly if
    /// loaded, else the first product). Paywall UI should prefer reading
    /// `displayPrice` directly off each `Product` in `products` instead.
    @Published private(set) var priceString: String?
    @Published private(set) var isPurchasing = false
    /// Loaded storefront products, in monthly-then-yearly order.
    @Published private(set) var products: [Product] = []
    /// True while the storefront request is in flight. The paywall needs to
    /// tell "still loading" apart from "came back with nothing" — otherwise
    /// an empty result spins forever, which is what happens whenever the
    /// products aren't live in App Store Connect yet.
    @Published private(set) var isLoadingProducts = false
    /// True once a load finished without returning any product.
    @Published private(set) var productsUnavailable = false
    /// Details of the active subscription, when Pro is active and the
    /// renewal date could be resolved.
    @Published private(set) var activeSubscription: ActiveSubscriptionInfo?

    /// True while StoreKit is reachable for purchases (false under parental
    /// controls / "Ask to Buy" restrictions).
    var purchasesAvailable: Bool {
        AppStore.canMakePayments
    }

    private let cacheKey = "is_premium_cached"
    private var updatesTask: Task<Void, Never>?
    private var didConfigure = false

    private init() {
        // With the tier switched off every gate reads as unlocked, so the
        // cached entitlement is irrelevant. It is deliberately left on disk:
        // re-enabling Pro should restore a real subscriber's status without
        // waiting on the first StoreKit round trip.
        isPremium = MonetizationConfig.isProEnabled
            ? UserDefaults.standard.bool(forKey: cacheKey)
            : true
    }

    /// Call once at app launch.
    func configure() {
        guard !didConfigure else { return }
        didConfigure = true

        // Nothing is for sale while the tier is off — skip the storefront
        // request and the transaction listener rather than asking StoreKit
        // about products the build never shows.
        guard MonetizationConfig.isProEnabled else { return }

        startTransactionListener()
        Task {
            await loadProducts()
            await refresh()
        }
    }

    /// StoreKit 2 entitlements follow the signed-in Apple ID / device, not
    /// an app-level user id — there's no RevenueCat-style "log in" call.
    /// Kept for call-site compatibility; just re-checks entitlements so Pro
    /// status is fresh right after sign-in.
    func identify(uid: String?) {
        Task { await refresh() }
    }

    /// Loads the monthly + yearly products from the storefront (or the
    /// local `.storekit` configuration in DEBUG/Simulator runs).
    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            let ordered = [Self.monthlyProductID, Self.yearlyProductID].compactMap { id in
                loaded.first { $0.id == id }
            }
            products = ordered
            priceString = ordered.first?.displayPrice
            productsUnavailable = ordered.isEmpty
        } catch {
            productsUnavailable = true
        }
    }

    /// Re-derives `isPremium` / `activeSubscription` from current entitlements.
    func refresh() async {
        await applyCurrentEntitlements()
    }

    /// Buy a plan. Returns true if Pro is active afterward.
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refresh()
                return isPremium
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    /// Restore a previous purchase (e.g. on a new device).
    func restore() async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
        } catch {
            return false
        }
        await refresh()
        return isPremium
    }

    // MARK: - Entitlement resolution

    private func applyCurrentEntitlements() async {
        var activeProductID: String?
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if Self.allProductIDs.contains(transaction.productID), transaction.revocationDate == nil {
                activeProductID = transaction.productID
                break
            }
        }

        setPremium(activeProductID != nil)
        activeSubscription = await resolveActiveSubscription(productID: activeProductID)
    }

    private func resolveActiveSubscription(productID: String?) async -> ActiveSubscriptionInfo? {
        guard let productID else { return nil }
        let fallback = ActiveSubscriptionInfo(productID: productID, expirationDate: nil, willAutoRenew: false)

        var resolvedProduct = products.first { $0.id == productID }
        if resolvedProduct == nil {
            resolvedProduct = (try? await Product.products(for: [productID]))?.first
        }
        guard let subscription = resolvedProduct?.subscription,
              let statuses = try? await subscription.status else {
            return fallback
        }

        var matchedStatus: Product.SubscriptionInfo.Status?
        for status in statuses {
            if let transaction = try? checkVerified(status.transaction), transaction.productID == productID {
                matchedStatus = status
                break
            }
        }
        guard let status = matchedStatus ?? statuses.first,
              let transaction = try? checkVerified(status.transaction) else {
            return fallback
        }

        let renewalInfo = try? checkVerified(status.renewalInfo)
        return ActiveSubscriptionInfo(
            productID: productID,
            expirationDate: transaction.expirationDate,
            willAutoRenew: renewalInfo?.willAutoRenew ?? false
        )
    }

    private func startTransactionListener() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self, let transaction = try? self.checkVerified(update) else { continue }
                await transaction.finish()
                await self.refresh()
            }
        }
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitVerificationError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private func setPremium(_ value: Bool) {
        // Every write to the entitlement funnels through here — entitlement
        // refreshes, purchases, and the DEBUG toggle alike. Pinning the
        // published value while the tier is off means no code path can
        // re-lock a feature. The real value still reaches the cache, so
        // re-enabling Pro finds an accurate entitlement waiting.
        let effective = MonetizationConfig.isProEnabled ? value : true
        if isPremium != effective { isPremium = effective }
        UserDefaults.standard.set(value, forKey: cacheKey)
    }

    #if DEBUG
    /// Debug-only manual override to test ad gating / paywall UI without a
    /// real purchase (e.g. in Simulator runs without the StoreKit config).
    func debugSetPremium(_ value: Bool) { setPremium(value) }
    #endif
}

private enum StoreKitVerificationError: Error {
    case failedVerification
}
