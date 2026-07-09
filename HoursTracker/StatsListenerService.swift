import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine
import os

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
                        let previous = self.lifetimeStats
                        let updated = ServerLifetimeStats.fromFirestore(snapshot?.data())
                        self.lifetimeStats = updated
                        if let updated {
                            Self.cacheServerLevel(updated.level, uid: uid)
                        }
                        if let updated, updated != previous {
                            AppLogger.stats.info("stats.lifetime updated: level \(previous?.level ?? 0, privacy: .public) -> \(updated.level, privacy: .public), prestige \(previous?.prestige ?? 0, privacy: .public) -> \(updated.prestige, privacy: .public), totalXP \(previous?.totalXP ?? 0, privacy: .public) -> \(updated.totalXP, privacy: .public), totalHours \(String(format: "%.2f", previous?.totalHours ?? 0), privacy: .public) -> \(String(format: "%.2f", updated.totalHours), privacy: .public) (fromCache: \(snapshot?.metadata.isFromCache == true, privacy: .public))")
                        }
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

    // MARK: - Cold-launch server-level cache

    /// The last server-published level, persisted per uid. Used by
    /// `HoursStore.displayedLevel` as the cold-launch fallback so the first
    /// rendered frames show the last-known TRUE level instead of the locally
    /// persisted `gamificationProfile.level`, which can be stale (observed
    /// live: Home flashed a stale local 19 before the server's 12 arrived).
    private static func levelCacheKey(uid: String) -> String {
        "server_level_cache_v1_\(uid)"
    }

    static func cachedServerLevel(uid: String?) -> Int? {
        guard let uid else { return nil }
        let v = UserDefaults.standard.integer(forKey: levelCacheKey(uid: uid))
        return v > 0 ? v : nil
    }

    fileprivate static func cacheServerLevel(_ level: Int, uid: String) {
        UserDefaults.standard.set(level, forKey: levelCacheKey(uid: uid))
    }

    private func markReconciledIfReady() {
        if weekListenerFired && payPeriodListenerFired && lifetimeListenerFired {
            isPendingReconcile = false
        }
    }
}
