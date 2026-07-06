import SwiftUI

#if canImport(GoogleMobileAds)
import GoogleMobileAds

/// A standard AdMob banner. Sized to a fixed 50pt height row. Only created when
/// the caller decides the user is non-Pro, so it never appears for Pro users.
struct BannerAdView: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = MonetizationConfig.bannerUnitID
        banner.rootViewController = Self.topViewController()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
#else
/// Placeholder until the Google Mobile Ads SDK is added in Xcode. Renders
/// nothing so the layout is unaffected.
struct BannerAdView: View {
    var body: some View { EmptyView() }
}
#endif
