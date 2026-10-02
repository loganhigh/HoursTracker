import Foundation

/// Central config for monetization (StoreKit 2 "Hour Tracker Pro").
///
/// The app shows no ads. Subscription product IDs
/// (`com.loganh.HourTracker.pro.monthly` / `.yearly`) live on `PremiumManager`
/// alongside the StoreKit 2 code that uses them — see
/// `PremiumManager.monthlyProductID` / `.yearlyProductID`.
enum MonetizationConfig {

    // MARK: Pro tier

    /// Master switch for the Hour Tracker Pro tier. While this is `false` the
    /// app ships with no paid tier at all: every Pro-gated feature is free for
    /// everyone, no upgrade or paywall UI is reachable, and StoreKit is never
    /// contacted.
    ///
    /// The StoreKit code, the paywall, and the individual feature gates are all
    /// left intact — flipping this back to `true` restores the tier exactly as
    /// it was, with no other edit required.
    static let isProEnabled = false
}
