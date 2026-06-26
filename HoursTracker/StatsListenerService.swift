import Foundation
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

    func startListening(uid: String) {
        guard FirebaseMigrationFlags.useServerStats else { return }
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
        guard FirebaseMigrationFlags.useServerStats else { return }
        isPendingReconcile = true
    }

    private func markReconciledIfReady() {
        if weekListenerFired && payPeriodListenerFired && lifetimeListenerFired {
            isPendingReconcile = false
        }
    }
}
