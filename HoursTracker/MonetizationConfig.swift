import Foundation

/// Central config for monetization (StoreKit 2 "Hour Tracker Pro" + AdMob).
///
/// IMPORTANT — replace the placeholder value before shipping a release build:
///  1. `bannerUnitID` (release) — your real AdMob banner unit ID.
///  2. AdMob **App ID** goes in `Info.plist` under `GADApplicationIdentifier`.
///
/// The DEBUG values use Google's official **test** IDs, which are safe to ship
/// in development builds and always return a test ad.
///
/// Subscription product IDs (`com.loganh.HourTracker.pro.monthly` /
/// `.yearly`) live on `PremiumManager` alongside the StoreKit 2 code that
/// uses them — see `PremiumManager.monthlyProductID` / `.yearlyProductID`.
enum MonetizationConfig {

    // MARK: Pro tier

    /// Master switch for the Hour Tracker Pro tier. While this is `false` the
    /// app ships with no paid tier at all: every Pro-gated feature is free for
    /// everyone, no upgrade or paywall UI is reachable, StoreKit is never
    /// contacted, and the banner ad is hidden (it only ever showed to non-Pro
    /// users, and with nothing to buy there would be no way to remove it).
    ///
    /// The StoreKit code, the paywall, and the individual feature gates are all
    /// left intact — flipping this back to `true` restores the tier exactly as
    /// it was, with no other edit required.
    static let isProEnabled = false

    // MARK: AdMob
    /// Banner ad unit ID. DEBUG uses Google's official test unit (always fills
    /// with a test ad). Replace the release value with your real unit ID.
    static var bannerUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716" // Google test banner
        #else
        return "ca-app-pub-0000000000000000/0000000000" // TODO: real banner unit ID
        #endif
    }
}
