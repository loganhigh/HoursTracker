import Foundation
import FirebaseAuth
import FirebaseFirestore
import StoreKit

/// Every tip a person makes, so their total keeps adding up across purchases
/// ($0.99 now + $4.99 next month = colours unlocked). The server adds each
/// `tips/{transactionId}` doc onto the user's tipTotal (notifyAdminOnTip).
///
/// Apple never tells us who paid, so this device's record is the only one.
/// Each tip is held here until Firestore confirms it, which covers tips
/// made while signed out, offline, or that finish later (Ask to Buy,
/// app closed mid-purchase). The doc id is the App Store transaction id and
/// the rules only allow creating it, so a retry can never count twice.
@MainActor
enum TipLedger {
    private static let pendingKey = "tip_ledger_pending"
    private static var listener: AuthStateDidChangeListenerHandle?

    static func isTip(_ productID: String) -> Bool {
        TipJarManager.tipProductIDs.contains(productID)
    }

    /// Hold a finished tip, then try to send it.
    static func record(_ transaction: StoreKit.Transaction, productName: String?) {
        guard isTip(transaction.productID), transaction.revocationDate == nil else { return }
        let amount = NSDecimalNumber(decimal: transaction.price ?? 0).doubleValue
        guard amount > 0 else { return }
        var pending = load()
        let id = String(transaction.id)
        if pending[id] == nil {
            pending[id] = [
                "productID": transaction.productID,
                "productName": String((productName ?? "Tip").prefix(40)),
                "amount": amount,
                "currency": String((transaction.currency?.identifier ?? "").prefix(3))
            ]
            save(pending)
        }
        flush()
    }

    /// Re-sends anything not confirmed yet. Runs on launch and on sign-in.
    static func start() {
        guard listener == nil else { return }
        listener = Auth.auth().addStateDidChangeListener { _, user in
            if user != nil { Task { @MainActor in flush() } }
        }
    }

    static func flush() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let pending = load()
        guard !pending.isEmpty else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let db = Firestore.firestore()
        for (id, tip) in pending {
            var data = tip
            data["uid"] = uid
            data["appVersion"] = String(version.prefix(20))
            data["createdAt"] = FieldValue.serverTimestamp()
            db.collection("tips").document(id).setData(data) { error in
                Task { @MainActor in
                    let ns = error as NSError?
                    // Already in the ledger shows up as permission denied
                    // (the doc exists, so this would be an update): done.
                    let done = error == nil || (ns?.domain == FirestoreErrorDomain
                        && ns?.code == FirestoreErrorCode.permissionDenied.rawValue)
                    if done { remove(id) }
                }
            }
        }
    }

    private static func load() -> [String: [String: Any]] {
        UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: [String: Any]] ?? [:]
    }

    private static func save(_ pending: [String: [String: Any]]) {
        UserDefaults.standard.set(pending, forKey: pendingKey)
    }

    private static func remove(_ id: String) {
        var pending = load()
        pending[id] = nil
        save(pending)
    }
}
