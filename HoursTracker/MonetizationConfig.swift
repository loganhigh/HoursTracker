import Foundation

/// Central config for monetization (RevenueCat + AdMob).
///
/// IMPORTANT — replace the placeholder values before shipping a release build:
///  1. `revenueCatAPIKey` — your RevenueCat **public** SDK key.
///  2. `bannerUnitID` (release) — your real AdMob banner unit ID.
///  3. AdMob **App ID** goes in `Info.plist` under `GADApplicationIdentifier`.
///
/// The DEBUG values use Google's official **test** IDs, which are safe to ship
/// in development builds and always return a test ad.
enum MonetizationConfig {

    // MARK: RevenueCat
    /// Public SDK API key from the RevenueCat dashboard (Project → API keys).
    /// Leave as-is until you create the project; the app still builds/runs and
    /// simply treats everyone as non-Pro until a real key + product exist.
    static let revenueCatAPIKey = "REVENUECAT_PUBLIC_API_KEY"

    /// Entitlement identifier configured in RevenueCat that represents Pro.
    static let proEntitlementID = "pro"

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
