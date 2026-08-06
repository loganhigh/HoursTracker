import Foundation
import Combine
#if canImport(RevenueCat)
import RevenueCat
#endif

/// App-wide source of truth for the "Hour Tracker Pro" entitlement.
///
/// Wraps RevenueCat when the SDK is present. Until the `RevenueCat` Swift
/// package is added in Xcode, this still compiles and behaves as "not Pro"
/// (with a DEBUG-only manual unlock so the ad gating can be tested early).
///
/// `isPremium` is cached in `UserDefaults` so a cold launch never flashes a
/// banner ad at a Pro user before RevenueCat finishes loading.
@MainActor
final class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    @Published private(set) var isPremium: Bool
    @Published private(set) var priceString: String?
    @Published private(set) var isPurchasing = false

    /// True when the RevenueCat SDK is linked into the build.
    var purchasesAvailable: Bool {
        #if canImport(RevenueCat)
        return true
        #else
        return false
        #endif
    }

    private let cacheKey = "is_premium_cached"

    private init() {
        isPremium = UserDefaults.standard.bool(forKey: cacheKey)
    }

    /// Call once at app launch.
    func configure() {
        #if canImport(RevenueCat)
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: MonetizationConfig.revenueCatAPIKey)
        observeCustomerInfo()
        Task {
            await refresh()
            await loadOffering()
        }
        #endif
    }

    /// Tie purchases to the signed-in user so Pro follows them across devices.
    func identify(uid: String?) {
        #if canImport(RevenueCat)
        guard let uid, !uid.isEmpty else { return }
        Task {
            _ = try? await Purchases.shared.logIn(uid)
            await refresh()
            await loadOffering()
        }
        #endif
    }

    func refresh() async {
        #if canImport(RevenueCat)
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        apply(info)
        #endif
    }

    /// Buy the lifetime Pro unlock. Returns true if Pro is active afterward.
    func purchase() async -> Bool {
        #if canImport(RevenueCat)
        guard let pkg = cachedPackage else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(package: pkg)
            apply(result.customerInfo)
            return isPremium
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// Restore a previous purchase (e.g. on a new device).
    func restore() async -> Bool {
        #if canImport(RevenueCat)
        isPurchasing = true
        defer { isPurchasing = false }
        guard let info = try? await Purchases.shared.restorePurchases() else { return false }
        apply(info)
        return isPremium
        #else
        return false
        #endif
    }

    // MARK: - RevenueCat internals

    #if canImport(RevenueCat)
    private var cachedPackage: Package?

    private func loadOffering() async {
        guard let offerings = try? await Purchases.shared.offerings() else { return }
        let pkg = offerings.current?.availablePackages.first
        cachedPackage = pkg
        priceString = pkg?.storeProduct.localizedPriceString
    }

    private func observeCustomerInfo() {
        Task {
            for await info in Purchases.shared.customerInfoStream {
                apply(info)
            }
        }
    }

    private func apply(_ info: CustomerInfo) {
        setPremium(info.entitlements[MonetizationConfig.proEntitlementID]?.isActive == true)
    }
    #endif

    private func setPremium(_ value: Bool) {
        if isPremium != value { isPremium = value }
        UserDefaults.standard.set(value, forKey: cacheKey)
    }

    #if DEBUG
    /// Debug-only manual override to test ad gating before RevenueCat is wired.
    func debugSetPremium(_ value: Bool) { setPremium(value) }
    #endif
}
