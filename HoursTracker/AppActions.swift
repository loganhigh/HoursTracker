import SwiftUI
import UIKit
import StoreKit

enum AppActions {

    /// ⚠️ BEFORE APP STORE RELEASE: Set to your app's Apple ID (numeric string, e.g. "1234567890").
    /// Find it in App Store Connect → Your App → App Information.
    static let appStoreID: String = "6758329353"

    /// Attempts to show the in-app rating prompt.
    /// If Apple suppresses it, we fall back to opening the App Store page.
    @MainActor
    static func rateApp() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
                openAppStoreListing()
                return
            }

        if #available(iOS 18.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    /// Opens your app's App Store product page — the front page where the
    /// app is downloadable, not the review-writing flow.
    static func openAppStoreListing() {
        guard appStoreID != "YOUR_APP_ID_HERE", !appStoreID.isEmpty else { return }

        let productURL = "itms-apps://itunes.apple.com/app/id\(appStoreID)"
        if let url = URL(string: productURL) {
            UIApplication.shared.open(url)
        }
    }

    /// Opens the App Store's write-a-review flow directly. Used by explicit
    /// "leave a review" actions — not the general "get the app" listing.
    static func openAppStoreWriteReview() {
        guard appStoreID != "YOUR_APP_ID_HERE", !appStoreID.isEmpty else { return }

        let reviewURL = "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review"
        if let url = URL(string: reviewURL) {
            UIApplication.shared.open(url)
        }
    }

    /// Opens the default Mail app for support
    static func contactSupportEmail() {
        let email = "trackedhours@gmail.com"
        let subject = "Hour Tracker Support"
        let body = "Hi, I need help with..."

        let urlString =
        "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
