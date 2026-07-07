import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

/// Listens to server-maintained `users/{uid}/stats/*` summary documents.
@MainActor
final class StatsListenerService: ObservableObject {
    static let shared = StatsListenerService()

    @Published private(set) var weekStats: ServerWeekStats?
    @Published private(set) var payPeriodStats: ServerPayPeriodStats?
    @Published private(set) var lifetimeStats: ServerLifetimeStats?
    @Published private(set) var isPendingReconcile = false

    private let db = Firestore.firestore()
    private var weekKey: String?
    private var payPeriodKey: String?
    private var lifetimeKey: String?
    private var activeUid: String?
    private var weekListenerFired = false
    private var payPeriodListenerFired = false
    private var lifetimeListenerFired = false

    private init() {}

    /// Idempotent: resolves the signed-in uid and attaches the listeners if
    /// they aren't already running. Screens that display server stats (Career,
    /// pay-cycle hero) call this on appear so a missed sign-in callback or a
    /// stale legacy kill-switch can never leave them silently reading local
    /// sums while the leaderboard shows server totals.
    func ensureListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        startListening(uid: uid)
    }

    // Note: deliberately NOT gated on FirebaseMigrationFlags.useServerStats.
    // That kill-switch predates the server-stats migration being complete — the
    // global leaderboard and friend profiles are server-fed regardless, so a
    // device-local opt-out here only desynced Career's lifetime hours from the
    // leaderboard (751.45 vs 784.95 class of bug).
    func startListening(uid: String) {
        if activeUid == uid, weekKey != nil { return }
        stopListening()
        activeUid = uid
        isPendingReconcile = true

        weekKey = FirebaseListenerRegistry.shared.register(
            owner: .statsListener,
            purpose: "stats.currentWeek",
            uid: uid,
            registration: db.collection("users").document(uid)
                .collection("stats").document("currentWeek")
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self, self.activeUid == uid else { return }
                        if let error {
                            FirestoreOperationLog.listenerError(owner: .statsListener, purpose: "stats.currentWeek", uid: uid, error: error)
                            return
                        }
                        self.weekStats = ServerWeekStats.fromFirestore(snapshot?.data())
                        self.weekListenerFired = true
                        self.markReconciledIfReady()
                    }
                }
        )

        payPeriodKey = FirebaseListenerRegistry.shared.register(
            owner: .statsListener,
            purpose: "stats.currentPayPeriod",
            uid: uid,
            registration: db.collection("users").document(uid)
                .collection("stats").document("currentPayPeriod")
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self, self.activeUid == uid else { return }
                        if let error {
                            FirestoreOperationLog.listenerError(owner: .statsListener, purpose: "stats.currentPayPeriod", uid: uid, error: error)
                            return
                        }
                        self.payPeriodStats = ServerPayPeriodStats.fromFirestore(snapshot?.data())
                        self.payPeriodListenerFired = true
                        self.markReconciledIfReady()
                    }
                }
        )

        lifetimeKey = FirebaseListenerRegistry.shared.register(
            owner: .statsListener,
            purpose: "stats.lifetime",
            uid: uid,
            registration: db.collection("users").document(uid)
                .collection("stats").document("lifetime")
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self, self.activeUid == uid else { return }
                        if let error {
                            FirestoreOperationLog.listenerError(owner: .statsListener, purpose: "stats.lifetime", uid: uid, error: error)
                            return
                        }
                        self.lifetimeStats = ServerLifetimeStats.fromFirestore(snapshot?.data())
                        self.lifetimeListenerFired = true
                        self.markReconciledIfReady()
                    }
                }
        )
    }

    func stopListening() {
        if let weekKey { FirebaseListenerRegistry.shared.remove(key: weekKey) }
        if let payPeriodKey { FirebaseListenerRegistry.shared.remove(key: payPeriodKey) }
        if let lifetimeKey { FirebaseListenerRegistry.shared.remove(key: lifetimeKey) }
        weekKey = nil
        payPeriodKey = nil
        lifetimeKey = nil
        activeUid = nil
        weekStats = nil
        payPeriodStats = nil
        lifetimeStats = nil
        weekListenerFired = false
        payPeriodListenerFired = false
        lifetimeListenerFired = false
        isPendingReconcile = false
    }

    func markEntryWritePending() {
        isPendingReconcile = true
    }

    private func markReconciledIfReady() {
        if weekListenerFired && payPeriodListenerFired && lifetimeListenerFired {
            isPendingReconcile = false
        }
    }
}
