import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import StoreKit

/// Who has left a tip. Supporters get the shimmer on their username wherever
/// it shows.
///
/// The flag itself is `isSupporter` on the user's own doc, written by their
/// device when a tip goes through; the server copies it onto the public
/// profile the same way it carries the verified badge. Names on screen are
/// usernames (unique), so other people's flags are keyed by name, which is
/// all the shared name view has to go on.
@MainActor
final class SupporterRegistry: ObservableObject {
    static let shared = SupporterRegistry()

    private static let selfKey = "is_supporter"

    @Published private(set) var names: Set<String> = []
    @Published private(set) var selfIsSupporter: Bool

    private init() {
        selfIsSupporter = UserDefaults.standard.bool(forKey: Self.selfKey)
    }

    func contains(_ name: String) -> Bool {
        let key = Self.key(name)
        guard !key.isEmpty else { return false }
        if names.contains(key) { return true }
        return selfIsSupporter && ownKeys().contains(key)
    }

    /// Called wherever another person's profile is parsed.
    func record(name: String, isSupporter: Bool) {
        let key = Self.key(name)
        guard !key.isEmpty else { return }
        if isSupporter {
            if !names.contains(key) { names.insert(key) }
        } else if names.contains(key) {
            names.remove(key)
        }
    }

    /// A tip just went through on this device: flip the supporter flag and
    /// log the tip so the admin can see who gave what. Apple never says who
    /// paid, so this record (keyed by the App Store transaction id, so a
    /// retry can't double-count) is the only per-person ledger there is.
    func recordTip(transaction: StoreKit.Transaction, product: Product) {
        setSelf(true)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        db.collection("users").document(uid).setData(["isSupporter": true], merge: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        db.collection("tips").document(String(transaction.id)).setData([
            "uid": uid,
            "productID": product.id,
            "productName": product.displayName,
            "amount": NSDecimalNumber(decimal: product.price).doubleValue,
            "currency": product.priceFormatStyle.currencyCode,
            "appVersion": version,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    /// Our own published profile says we are a supporter (a new device, or a
    /// reinstall). Only ever turns the flag on.
    func adoptServerValue(_ isSupporter: Bool) {
        if isSupporter { setSelf(true) }
    }

    private func setSelf(_ value: Bool) {
        guard selfIsSupporter != value else { return }
        selfIsSupporter = value
        UserDefaults.standard.set(value, forKey: Self.selfKey)
    }

    private func ownKeys() -> Set<String> {
        var keys: Set<String> = []
        if let name = UserDefaults.standard.string(forKey: "profile_display_name") {
            keys.insert(Self.key(name))
        }
        if let username = FriendsService.shared.myUsername {
            keys.insert(Self.key(username))
        }
        return keys
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
