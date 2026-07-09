import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import os

// MARK: - Cloud Sync Manager (Firestore)

final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var pendingChanges = 0

    /// True when Firestore is available and user is signed in.
    var isCloudAvailable: Bool { currentUID != nil }

    /// The signed-in Firebase uid, for callers that key caches per account
    /// (e.g. HoursStore.displayedLevel's server-level cache).
    var currentUserID: String? { currentUID }

    /// Resolved lazily so we don't touch `Firestore.firestore()` at construction
    /// time. If `GoogleService-Info.plist` is missing and `FirebaseApp.configure`
    /// never ran, accessing `db` would otherwise crash with "Default FirebaseApp
    /// is not configured". With lazy initialization the singleton still
    /// constructs cleanly; only callers that actually try to read/write will
    /// hit Firebase's runtime check (and they all gate on `isCloudAvailable`
    /// / `currentUID` first, which stays `nil` without a signed-in user).
    private lazy var db: Firestore = Firestore.firestore()
    private lazy var functions = Functions.functions(region: "us-central1")
    private let networkMonitor = NetworkMonitor.shared
    private var authService: AuthService?
    private weak var hoursStore: HoursStore?

    private var currentUID: String?
    private var entriesListener: ListenerRegistration?
    private var entriesListenerKey: String?
    private var settingsListener: ListenerRegistration?
    private var settingsListenerKey: String?
    private var gamificationListener: ListenerRegistration?
    private var gamificationListenerKey: String?
    /// True once Firestore has delivered at least one entries snapshot this session.
    /// HoursStore uses this to avoid stale UserDefaults overwriting cloud data.
    private(set) var hasAppliedRemoteEntries = false
    private var isPulling = false
    private var isRunningDailyRepairSync = false
    private var shouldRunDailyRepairAfterPull = false
    private var cancellables = Set<AnyCancellable>()

    private let pendingProfileSyncKey = "pending_profile_sync"
    private let dailyRepairSyncDateKeyPrefix = "cloud_daily_repair_sync_v3_date_"
    private let repairBatchSize = 200
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()

    private init() {
        checkPendingChanges()
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                if isConnected {
                    self?.syncWhenOnline()
                    self?.runDailyCloudRepairIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    func configure(authService: AuthService, store: HoursStore) {
        self.authService = authService
        self.hoursStore = store

        authService.onSignedIn = { [weak self] uid in
            self?.handleSignedIn(uid: uid)
        }
        authService.onSignedOut = { [weak self] in
            self?.handleSignedOut()
        }

        if let uid = authService.user?.uid {
            handleSignedIn(uid: uid)
        }
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    // MARK: - Sync status

    func checkPendingChanges() {
        let pendingEntries = UserDefaults.standard.integer(forKey: "pending_entries_count")
        let pendingDeletes = getPendingDeletes().count
        let pendingSettings = UserDefaults.standard.bool(forKey: "pending_settings_sync") ? 1 : 0
        let pendingProfile = UserDefaults.standard.bool(forKey: pendingProfileSyncKey) ? 1 : 0
        DispatchQueue.main.async { [weak self] in
            self?.pendingChanges = pendingEntries + pendingDeletes + pendingSettings + pendingProfile
        }
    }

    // MARK: - Entry CRUD

    func saveEntry(_ entry: WorkEntry, completion: @escaping (Result<Void, Error>) -> Void) {
        // Saving an entry cancels any pending deletion tombstone for the same id.
        clearDeleteTombstone(entry.id)
        guard let uid = currentUID else {
            queueEntryForSync(entry)
            completion(.success(()))
            return
        }
        guard networkMonitor.isConnected else {
            queueEntryForSync(entry)
            completion(.success(()))
            return
        }

        let payload = entryFirestorePayload(entry)
        let primaryCollection = entriesCollectionName()
        let primaryRef = db.collection("users").document(uid).collection(primaryCollection).document(entry.id.uuidString)

        // Watchdog: on some devices the direct SDK write channel hangs — the
        // setData completion below simply never fires (the documented reason
        // clientUploadTimeEntriesBatch exists). Before this, a stalled save
        // reached the cloud only at the NEXT DAILY repair, so a freshly logged
        // shift didn't hit stats/the leaderboard for up to ~24h on an affected
        // device. If the direct write hasn't confirmed within 5s, push this one
        // entry through the batch callable (Admin SDK, bypasses the stuck
        // channel). Idempotent by construction: same doc id, and the callable
        // skips unchanged docs server-side, so whichever path lands second is
        // a no-op.
        let watchdog = DispatchWorkItem { [weak self] in
            self?.uploadEntryViaBatchCallable(entry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: watchdog)

        FirestoreOperationLog.write(operation: "saveEntry.\(primaryCollection)", uid: uid) { done in
            primaryRef.setData(payload, merge: true, completion: done)
        } completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                watchdog.cancel()
                switch result {
                case .failure(let error):
                    self.queueEntryForSync(entry)
                    self.syncError = error.localizedDescription
                    completion(.failure(error))
                case .success:
                    self.markEntryAsSynced(entry.id)
                    self.checkPendingChanges()
                    self.traceRepairGate(reason: "saveEntrySuccess")
                    if FirebaseMigrationFlags.useServerStats {
                        Task { @MainActor in
                            StatsListenerService.shared.markEntryWritePending()
                        }
                    }
                    if FirebaseMigrationFlags.useLegacyEntryMirror {
                        let legacyRef = self.db.collection("users").document(uid)
                            .collection("entries").document(entry.id.uuidString)
                        legacyRef.setData(payload, merge: true)
                    }
                    if !FirebaseMigrationFlags.skipProfileSnapshotOnEntryCRUD,
                       let store = self.hoursStore {
                        self.saveProfileSnapshot(store: store)
                    }
                    // Keep friend-facing stats fresh in near-real-time. When the
                    // profile-snapshot path is skipped (its default), nothing else
                    // triggers the server recompute on a shift save, so friends
                    // would otherwise see stale stats until the daily sweep.
                    self.scheduleStatsRecomputeDebounced()
                    completion(.success(()))
                }
            }
        }
    }

    func deleteEntry(_ entry: WorkEntry, completion: @escaping (Result<Void, Error>) -> Void) {
        // Tombstone immediately (persisted) so a stale snapshot or the
        // applyRemoteEntries re-upload path can't resurrect the entry before the
        // server delete lands. Cleared by syncPendingDeletes on server-confirmed
        // deletion, or by reconcileTombstones once a snapshot shows the doc gone.
        //
        // The delete itself goes through the clientDeleteTimeEntriesBatch
        // callable (Admin SDK) rather than a direct Firestore SDK delete: on
        // devices where the SDK write channel hangs — the documented reason
        // clientUploadTimeEntriesBatch exists for saves — a direct delete never
        // completes, the tombstone retried the same hanging path forever, and
        // the phantom doc kept inflating the cloud total and leaderboard row.
        queueDeleteForSync(entry.id)
        guard currentUID != nil, networkMonitor.isConnected else {
            completion(.success(()))
            return
        }
        syncPendingDeletes()
        completion(.success(()))
    }

    // MARK: - Full sync

    func syncAll(entries: [WorkEntry], settings: PaySettings, completion: @escaping (Result<Void, Error>) -> Void) {
        guard currentUID != nil else {
            completion(.success(()))
            return
        }
        guard networkMonitor.isConnected else {
            syncError = "No internet connection. Changes will sync when online."
            completion(.failure(NSError(domain: "CloudSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "No internet connection"])))
            return
        }

        isSyncing = true
        syncError = nil

        let group = DispatchGroup()
        var syncErrors: [Error] = []

        for entry in entries {
            group.enter()
            saveEntry(entry) { result in
                if case .failure(let error) = result { syncErrors.append(error) }
                group.leave()
            }
        }

        group.enter()
        saveSettings(settings) { result in
            if case .failure(let error) = result { syncErrors.append(error) }
            group.leave()
        }

        if let store = hoursStore {
            group.enter()
            saveProfileSnapshot(store: store) { result in
                if case .failure(let error) = result { syncErrors.append(error) }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isSyncing = false
            self?.lastSyncDate = Date()
            if syncErrors.isEmpty {
                self?.syncError = nil
                completion(.success(()))
            } else {
                let error = syncErrors.first!
                self?.syncError = error.localizedDescription
                completion(.failure(error))
            }
        }
    }

    /// Explicit repair path for accounts where this device has older archived
    /// shifts that never made it into Firestore. Normal edits only touch the
    /// active `entries` array, but lifetime/career totals also include
    /// `yearArchives`; pushing this full set makes the server recompute match
    /// what the user sees locally on their own Career page.
    func forceUploadAllLocalData(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = currentUID, networkMonitor.isConnected else {
            completion(.failure(NSError(
                domain: "CloudSync",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in or offline"]
            )))
            return
        }
        guard let store = hoursStore else {
            completion(.failure(NSError(
                domain: "CloudSync",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Local data is still loading. Try again in a moment."]
            )))
            return
        }
        let allEntries = store.allEntriesIncludingArchive()
        let totalHours = allEntries
            .filter { !$0.isOffDay }
            .reduce(0.0) { $0 + $1.paidHours }
        writeRepairDiagnostic(uid: uid, status: "started", entryCount: allEntries.count, localHours: totalHours)

        isSyncing = true
        syncError = nil
        uploadEntriesInBatches(allEntries, uid: uid, uploaded: 0) { [weak self] uploadResult in
            DispatchQueue.main.async {
                guard let self else { return }
                switch uploadResult {
                case .failure(let error):
                    self.isSyncing = false
                    self.syncError = error.localizedDescription
                    self.writeRepairDiagnostic(
                        uid: uid,
                        status: "failed",
                        entryCount: allEntries.count,
                        localHours: totalHours,
                        error: error.localizedDescription
                    )
                    completion(.failure(error))
                case .success:
                    let group = DispatchGroup()
                    var syncErrors: [Error] = []

                    group.enter()
                    self.saveSettings(store.paySettings) { result in
                        if case .failure(let error) = result { syncErrors.append(error) }
                        group.leave()
                    }

                    group.enter()
                    self.saveProfileSnapshot(store: store) { result in
                        if case .failure(let error) = result { syncErrors.append(error) }
                        group.leave()
                    }

                    group.notify(queue: .main) {
                        self.isSyncing = false
                        self.lastSyncDate = Date()
                        if let error = syncErrors.first {
                            self.syncError = error.localizedDescription
                            self.writeRepairDiagnostic(
                                uid: uid,
                                status: "failed",
                                entryCount: allEntries.count,
                                localHours: totalHours,
                                error: error.localizedDescription
                            )
                            completion(.failure(error))
                        } else {
                            self.syncError = nil
                            self.writeRepairDiagnostic(
                                uid: uid,
                                status: "finished",
                                entryCount: allEntries.count,
                                localHours: totalHours
                            )
                            completion(.success(()))
                        }
                    }
                }
            }
        }
    }

    /// Automatic daily repair upload. This quietly publishes the complete local
    /// dataset (active + archived entries) once per day when the app is open,
    /// signed in, online, and the store has finished loading. It is intentionally
    /// keyed by uid so switching accounts cannot suppress another account's
    /// daily repair window.
    func runDailyCloudRepairIfNeeded() {
        traceRepairGate(reason: "runDailyCloudRepairIfNeeded")
        guard let uid = currentUID, networkMonitor.isConnected else {
            return
        }
        guard let store = hoursStore, store.isLoaded else {
            writeRepairDiagnostic(uid: uid, status: "waiting_for_store_load", entryCount: 0)
            return
        }
        if isPulling {
            shouldRunDailyRepairAfterPull = true
            let allEntries = store.allEntriesIncludingArchive()
            let totalHours = allEntries
                .filter { !$0.isOffDay }
                .reduce(0.0) { $0 + $1.paidHours }
            writeRepairDiagnostic(
                uid: uid,
                status: "waiting_for_pull",
                entryCount: allEntries.count,
                localHours: totalHours
            )
            return
        }
        guard !isRunningDailyRepairSync else {
            return
        }

        let todayKey = Self.dayKey(for: Date())
        let defaultsKey = dailyRepairSyncDateKeyPrefix + uid
        if UserDefaults.standard.string(forKey: defaultsKey) == todayKey {
            let allEntries = store.allEntriesIncludingArchive()
            let totalHours = allEntries
                .filter { !$0.isOffDay }
                .reduce(0.0) { $0 + $1.paidHours }
            writeRepairDiagnostic(
                uid: uid,
                status: "skipped_already_ran_today",
                entryCount: allEntries.count,
                localHours: totalHours
            )
            return
        }

        isRunningDailyRepairSync = true
        forceUploadAllLocalData { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunningDailyRepairSync = false
                if case .success = result {
                    UserDefaults.standard.set(todayKey, forKey: defaultsKey)
                }
            }
        }
    }

    func fetchEntries(completion: @escaping (Result<[WorkEntry], Error>) -> Void) {
        guard let uid = currentUID, networkMonitor.isConnected else {
            completion(.failure(NSError(domain: "CloudSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in or offline"])))
            return
        }
        db.collection("users").document(uid).collection(entriesCollectionName()).getDocuments { snapshot, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                    return
                }
                let entries = snapshot?.documents.compactMap { self.entry(from: $0.data()) } ?? []
                completion(.success(entries))
            }
        }
    }

    /// Fast-path fallback for a single stalled direct write (see the watchdog
    /// in `saveEntry`): pushes one entry through clientUploadTimeEntriesBatch.
    /// Never surfaces an error to the user — the direct write may still land,
    /// and the entry remains covered by the daily repair either way.
    private func uploadEntryViaBatchCallable(_ entry: WorkEntry) {
        guard currentUID != nil, networkMonitor.isConnected else { return }
        let payload = entryCallablePayload(entry)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.functions.httpsCallable("clientUploadTimeEntriesBatch").call(
                    self.functionsCallablePayload(["entries": [payload]])
                )
                self.markEntryAsSynced(entry.id)
                self.checkPendingChanges()
                if FirebaseMigrationFlags.useServerStats {
                    StatsListenerService.shared.markEntryWritePending()
                }
                self.scheduleStatsRecomputeDebounced()
                AppLogger.db.info("saveEntry watchdog: direct write stalled >5s; entry \(entry.id.uuidString, privacy: .public) uploaded via batch callable")
            } catch {
                // Keep it queued so the daily repair still covers it.
                self.queueEntryForSync(entry)
                AppLogger.db.warning("saveEntry watchdog: batch fallback failed (\(error.localizedDescription, privacy: .public)); entry queued for repair")
            }
        }
    }

    private func uploadEntriesInBatches(
        _ entries: [WorkEntry],
        uid: String,
        uploaded: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        Task { @MainActor [weak self] in
            await self?.uploadEntriesInBatchesOnMainActor(
                entries,
                uid: uid,
                uploaded: uploaded,
                completion: completion
            )
        }
    }

    @MainActor
    private func uploadEntriesInBatchesOnMainActor(
        _ entries: [WorkEntry],
        uid: String,
        uploaded: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) async {
        guard uploaded < entries.count else {
            completion(.success(()))
            return
        }

        let upperBound = min(uploaded + repairBatchSize, entries.count)
        let chunk = Array(entries[uploaded..<upperBound])
        let payloads = chunk.map { entryCallablePayload($0) }

        do {
            _ = try await functions.httpsCallable("clientUploadTimeEntriesBatch").call(
                functionsCallablePayload(["entries": payloads])
            )
            for entry in chunk {
                markEntryAsSynced(entry.id)
            }
            writeRepairDiagnostic(
                uid: uid,
                status: "uploading",
                entryCount: entries.count,
                uploadedCount: upperBound
            )
            await uploadEntriesInBatchesOnMainActor(
                entries,
                uid: uid,
                uploaded: upperBound,
                completion: completion
            )
        } catch {
            completion(.failure(error))
        }
    }

    private func writeRepairDiagnostic(
        uid: String,
        status: String,
        entryCount: Int,
        uploadedCount: Int? = nil,
        localHours: Double? = nil,
        error: String? = nil
    ) {
        var payload: [String: Any] = [
            "status": status,
            "entryCount": entryCount,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let uploadedCount { payload["uploadedCount"] = uploadedCount }
        if let localHours { payload["localHours"] = localHours }
        if let error { payload["error"] = error }

        let ref = db.collection("users").document(uid)
            .collection("syncDiagnostics").document("dailyRepair")
        FirestoreOperationLog.write(operation: "diagnostic.dailyRepair", uid: uid) { done in
            ref.setData(payload, merge: true, completion: done)
        } completion: { [weak self] result in
            if case .failure(let error) = result {
                DispatchQueue.main.async {
                    self?.syncError = "Diagnostic write failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func traceRepairGate(reason: String) {
        guard let uid = currentUID else { return }
        let entries = hoursStore?.allEntriesIncludingArchive() ?? []
        let localHours = entries
            .filter { !$0.isOffDay }
            .reduce(0.0) { $0 + $1.paidHours }
        let payload: [String: Any] = [
            "reason": reason,
            "networkConnected": networkMonitor.isConnected,
            "hasStore": hoursStore != nil,
            "storeLoaded": hoursStore?.isLoaded ?? false,
            "isPulling": isPulling,
            "isRunningDailyRepairSync": isRunningDailyRepairSync,
            "entryCount": entries.count,
            "localHours": localHours,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        let ref = db.collection("users").document(uid)
            .collection("debugEvents").document("repairGate")
        FirestoreOperationLog.write(operation: "diagnostic.repairGate", uid: uid) { done in
            ref.setData(payload, merge: true, completion: done)
        } completion: { [weak self] result in
            if case .failure(let error) = result {
                DispatchQueue.main.async {
                    self?.syncError = "Debug write failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func fetchSettings(completion: @escaping (Result<PaySettings, Error>) -> Void) {
        guard let uid = currentUID, networkMonitor.isConnected else {
            completion(.failure(NSError(domain: "CloudSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in or offline"])))
            return
        }
        db.collection("users").document(uid).collection("paySettings").document("current")
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    if let error {
                        completion(.failure(error))
                        return
                    }
                    guard let data = snapshot?.data(),
                          let json = try? JSONSerialization.data(withJSONObject: data),
                          let settings = try? self.decoder.decode(PaySettings.self, from: json) else {
                        completion(.failure(NSError(domain: "CloudSync", code: -3, userInfo: [NSLocalizedDescriptionKey: "Settings decode failed"])))
                        return
                    }
                    completion(.success(settings))
                }
            }
    }

    /// Pulls the latest entries and pay settings from Firestore, then pushes an
    /// updated friends profile snapshot. Uploads local shifts first so cloud
    /// never clobbers entries that haven't synced yet.
    func pullFromCloud(completion: @escaping () -> Void = {}) {
        guard currentUID != nil, networkMonitor.isConnected else {
            DispatchQueue.main.async { completion() }
            return
        }
        guard hoursStore != nil else {
            DispatchQueue.main.async { completion() }
            return
        }
        guard !isPulling else {
            shouldRunDailyRepairAfterPull = true
            DispatchQueue.main.async { completion() }
            return
        }
        isPulling = true
        fetchRemoteAndMerge { [weak self] in
            guard let self else { return }
            self.isPulling = false
            if self.shouldRunDailyRepairAfterPull {
                self.shouldRunDailyRepairAfterPull = false
                self.runDailyCloudRepairIfNeeded()
            }
            completion()
        }
    }

    private func fetchRemoteAndMerge(completion: @escaping () -> Void) {
        let group = DispatchGroup()
        var pulledEntries: [WorkEntry]?
        var pulledSettings: PaySettings?
        var pulledGamification: RemoteGamificationAnchors?

        group.enter()
        fetchEntries { result in
            if case .success(let entries) = result { pulledEntries = entries }
            group.leave()
        }

        group.enter()
        fetchSettings { result in
            if case .success(let settings) = result { pulledSettings = settings }
            group.leave()
        }

        group.enter()
        fetchGamificationAnchors { result in
            if case .success(let anchors) = result { pulledGamification = anchors }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else {
                completion()
                return
            }
            self.hoursStore?.applyRemoteGamificationAnchors(pulledGamification)
            if let anchors = pulledGamification {
                self.hoursStore?.applyAdminLevel(anchors.adminFloorLevel)
                self.hoursStore?.applyAdminPrestige(anchors.adminFloorPrestige)
                if let adminTitle = anchors.adminEquippedTitle, !adminTitle.isEmpty {
                    self.hoursStore?.applyAdminEquippedTitle(adminTitle)
                } else {
                    self.hoursStore?.applyAdminEquippedTitle(nil)
                }
                if anchors.levelOverride != nil || anchors.prestigeOverride != nil {
                    self.hoursStore?.applyCloudGamificationProgression(anchors)
                    if let store = self.hoursStore {
                        self.reconcileProgressionOverrideWithCloud(
                            store: store,
                            hadLevelOverride: anchors.levelOverride != nil,
                            hadPrestigeOverride: anchors.prestigeOverride != nil
                        )
                    }
                } else if let cloudOffset = anchors.adminXPOffset,
                          cloudOffset != self.hoursStore?.gamificationProfile.adminXPOffset {
                    self.hoursStore?.applyCloudGamificationProgression(anchors)
                }
            } else {
                self.hoursStore?.applyAdminLevel(nil)
                self.hoursStore?.applyAdminPrestige(nil)
                self.hoursStore?.applyAdminEquippedTitle(nil)
            }
            if let entries = pulledEntries {
                self.hoursStore?.applyRemoteEntries(entries)
            }
            if let settings = pulledSettings {
                self.hoursStore?.applyRemoteSettings(settings)
            }
            // Use forceSyncProfileAfterPull instead of syncProfileSnapshotToCloud:
            // the regular version gates on hasAppliedRemoteEntries which may still
            // be false if the entries snapshot listener hasn't fired yet, causing
            // the corrected prestige / level to never reach Firestore.
            self.hoursStore?.forceSyncProfileAfterPull()
            self.lastSyncDate = Date()
            completion()
        }
    }

    func saveSettings(_ settings: PaySettings, completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
        guard let uid = currentUID, networkMonitor.isConnected else {
            UserDefaults.standard.set(true, forKey: "pending_settings_sync")
            completion(.success(()))
            return
        }
        guard let data = try? encoder.encode(settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            completion(.failure(NSError(domain: "CloudSync", code: -2, userInfo: [NSLocalizedDescriptionKey: "Settings encode failed"])))
            return
        }
        // Same watchdog as saveEntry: on devices where the direct SDK write
        // channel hangs, this setData never completes — the cloud paySettings
        // doc went stale for WEEKS, so the server computed the friend-facing
        // cheque window from an old payday ("the payday I set doesn't stick").
        // If the direct write hasn't confirmed in 5s, save via the callable.
        let watchdog = DispatchWorkItem { [weak self] in
            self?.savePaySettingsViaCallable(json)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: watchdog)
        db.collection("users").document(uid).collection("paySettings").document("current")
            .setData(json, merge: true) { error in
                DispatchQueue.main.async {
                    watchdog.cancel()
                    if let error {
                        UserDefaults.standard.set(true, forKey: "pending_settings_sync")
                        completion(.failure(error))
                    } else {
                        UserDefaults.standard.set(false, forKey: "pending_settings_sync")
                        completion(.success(()))
                    }
                }
            }
    }

    /// Fallback for a stalled direct pay-settings write (see the watchdog in
    /// `saveSettings`): saves through the clientSavePaySettings callable, which
    /// also recomputes the friend-facing cheque window server-side.
    private func savePaySettingsViaCallable(_ settings: [String: Any]) {
        guard currentUID != nil, networkMonitor.isConnected else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.functions.httpsCallable("clientSavePaySettings").call(
                    self.functionsCallablePayload(["settings": settings])
                )
                UserDefaults.standard.set(false, forKey: "pending_settings_sync")
                AppLogger.db.info("saveSettings watchdog: direct write stalled >5s; settings saved via callable")
            } catch {
                UserDefaults.standard.set(true, forKey: "pending_settings_sync")
                AppLogger.db.warning("saveSettings watchdog: callable fallback failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func saveProfileSnapshot(store: HoursStore, completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
        guard let uid = currentUID else {
            UserDefaults.standard.set(true, forKey: pendingProfileSyncKey)
            checkPendingChanges()
            completion(.success(()))
            return
        }
        guard networkMonitor.isConnected else {
            UserDefaults.standard.set(true, forKey: pendingProfileSyncKey)
            checkPendingChanges()
            completion(.success(()))
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                completion(.success(()))
                return
            }
            let inputs = ProfileSnapshotInputs.capture(from: store)
            let payload = await Task.detached(priority: .utility) {
                inputs.makePayload()
            }.value

            do {
                try await self.db.collection("users").document(uid).setData(payload, merge: true)
                UserDefaults.standard.set(false, forKey: self.pendingProfileSyncKey)
                self.checkPendingChanges()
                self.saveGamificationAnchors(store: store)
                // Ask the server to recompute the friend-facing stats it owns
                // (chequeHours, chequeDailySummary, weekly stats, company stats)
                // for the current date/pay-period. This keeps the breakdown
                // consistent with the summary and heals any stale values that a
                // previous client snapshot may have left behind.
                self.requestStatsRecompute()
                completion(.success(()))
            } catch {
                UserDefaults.standard.set(true, forKey: self.pendingProfileSyncKey)
                self.checkPendingChanges()
                completion(.failure(error))
            }
        }
    }

    /// Fire-and-forget request for the server to recompute this user's
    /// friend-facing stats. The server (`recomputeUserStats`) is the sole
    /// writer of chequeHours, chequeDailySummary, weekly and company stats;
    /// triggering it here ensures those stay fresh for the current pay-period
    /// window even when no new time entry has been logged. Failures are
    /// non-fatal — the server also recomputes on every time-entry write.
    private func requestStatsRecompute() {
        guard currentUID != nil, networkMonitor.isConnected else { return }
        Task { [weak self] in
            _ = try? await self?.functions.httpsCallable("recomputeUserStatsCallable").call([:])
        }
    }

    private var recomputeDebounceWork: DispatchWorkItem?

    /// Debounced recompute request for the shift-CRUD path. Logging a shift must
    /// refresh the friend-facing `publicProfiles` stats promptly — otherwise a
    /// friend's leaderboard/board view only updates via the once-daily server
    /// sweep (~24h stale). Coalesces bursts (e.g. logging several shifts in a row,
    /// or an edit that saves repeatedly) into a single server call ~2s after the
    /// last write so we don't fan out one callable per keystroke-save.
    func scheduleStatsRecomputeDebounced() {
        guard currentUID != nil else { return }
        recomputeDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Push the client-owned XP/prestige anchors BEFORE asking the server
            // to recompute. The server derives the published `level` (stats/
            // lifetime, publicProfiles, leaderboard row) from
            // gamification/current.totalXP — a client-only value (it includes
            // streak/challenge bonuses the server can't rederive from entries).
            // Recomputing against the stale doc published yesterday's level even
            // though the entry write itself landed instantly; the anchors used to
            // sync only on the app-open profile snapshot.
            if let store = self.hoursStore {
                self.saveGamificationAnchors(store: store) { [weak self] _ in
                    self?.requestStatsRecompute()
                }
            } else {
                self.requestStatsRecompute()
            }
        }
        recomputeDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    /// Atomically bumps `highWaterPrestige` on the gamification doc.
    /// Called only from `performPrestige()` so it only ever goes up and is
    /// never touched by the profile-snapshot path. Acts as a recovery floor
    /// if the main `prestige` field is ever corrupted to 0.
    func recordHighWaterPrestige(_ level: Int) {
        guard let uid = currentUID, networkMonitor.isConnected, level > 0 else { return }
        let ref = db.collection("users").document(uid)
            .collection("gamification").document("current")
        // Use a transaction so we only ever increase, never decrease.
        db.runTransaction({ transaction, _ in
            let snap = try? transaction.getDocument(ref)
            let current = snap.flatMap { $0.data() }.flatMap { $0["highWaterPrestige"] as? Int } ?? 0
            if level > current {
                transaction.updateData(["highWaterPrestige": level], forDocument: ref)
            }
            return nil
        }, completion: { _, _ in })
    }

    /// After this device consumes an admin level/prestige override, publish its
    /// freshly-computed `adminXPOffset`/`totalXP`/`prestige` back to Firestore in
    /// the SAME write that clears the override flag(s).
    ///
    /// This must NOT be split into "clear the flag" then separately "sync the
    /// offset": clearing the flag alone re-fires this device's own gamification
    /// listener with the SERVER's original (pre-reconciliation) `adminXPOffset`
    /// still sitting in the doc. That original offset was computed by the
    /// server from ITS last-synced `totalXP` baseline, which can differ
    /// slightly from what this device just (correctly) computed the offset
    /// against. The listener then sees "cloud offset != local offset" and
    /// stomps the just-applied, correct level right back down — this was the
    /// live "sets to 17 then reverts" bug. Writing both fields atomically means
    /// the echoed-back snapshot always matches local state, so no mismatch is
    /// ever observed.
    private func reconcileProgressionOverrideWithCloud(
        store: HoursStore,
        hadLevelOverride: Bool,
        hadPrestigeOverride: Bool
    ) {
        guard let uid = currentUID else { return }
        let profile = store.gamificationProfile
        var payload: [String: Any] = [
            "adminXPOffset": profile.adminXPOffset,
            "totalXP": profile.totalXP,
            "prestige": profile.prestige,
            "prestigeXPSnapshots": profile.prestigeXPSnapshots,
            "level": profile.level,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if hadLevelOverride { payload["levelOverride"] = FieldValue.delete() }
        if hadPrestigeOverride { payload["prestigeOverride"] = FieldValue.delete() }
        db.collection("users").document(uid).collection("gamification").document("current")
            .setData(payload, merge: true) { _ in }
    }

    func saveGamificationAnchors(store: HoursStore, completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
        guard let uid = currentUID, networkMonitor.isConnected else {
            completion(.success(()))
            return
        }
        let ref = db.collection("users").document(uid).collection("gamification").document("current")
        ref.getDocument { [weak self] snapshot, error in
            guard let self else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "CloudSync", code: -1))) }
                return
            }
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            DispatchQueue.main.async {
                var hadLevelOverride = false
                var hadPrestigeOverride = false
                if let data = snapshot?.data(), let anchors = self.gamificationAnchors(from: data) {
                    let consumed = self.reconcileGamificationWithCloudBeforePush(store: store, anchors: anchors)
                    hadLevelOverride = consumed.hadLevelOverride
                    hadPrestigeOverride = consumed.hadPrestigeOverride
                }

                let profile = store.gamificationProfile
                let cloudOffset = snapshot.flatMap { self.firestoreOptionalInt($0.data() ?? [:], key: "adminXPOffset") } ?? 0
                // Never stomp an admin-set offset the device hasn't adopted yet.
                if !hadLevelOverride && !hadPrestigeOverride && cloudOffset != 0 && profile.adminXPOffset == 0 {
                    completion(.success(()))
                    return
                }

                var payload: [String: Any] = [
                    "prestige": profile.prestige,
                    "prestigeXPSnapshots": profile.prestigeXPSnapshots,
                    "prestigeHourSnapshots": profile.prestigeHourSnapshots,
                    "bestStreak": profile.bestStreak,
                    "streakFreezes": profile.streakFreezes,
                    "equippedTitle": profile.equippedTitle ?? "",
                    "totalXP": profile.totalXP,
                    "adminXPOffset": profile.adminXPOffset,
                    "level": profile.level,
                    // Parity telemetry for the server-XP migration: lets the
                    // server's shadow logs attribute any client/server XP drift
                    // to a specific component (overtime vs challenge vs entry math).
                    "xpBreakdown": store.xpComponentBreakdown(),
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                if hadLevelOverride { payload["levelOverride"] = FieldValue.delete() }
                if hadPrestigeOverride { payload["prestigeOverride"] = FieldValue.delete() }
                ref.setData(payload, merge: true) { error in
                    if let error {
                        completion(.failure(error))
                    } else {
                        store.markGamificationCloudSynced()
                        completion(.success(()))
                    }
                }
            }
        }
    }

    /// Returns which override flag(s), if any, were just consumed so the
    /// caller can clear them in the very same outgoing write — mirroring
    /// `reconcileProgressionOverrideWithCloud`. Applying an override here
    /// without ever clearing it would let it re-fire on every later
    /// `saveGamificationAnchors` call (e.g. after the next shift is logged),
    /// re-snapping the level back down to the admin-set value each time
    /// instead of letting newly-earned XP progress past it.
    private func reconcileGamificationWithCloudBeforePush(
        store: HoursStore,
        anchors: RemoteGamificationAnchors
    ) -> (hadLevelOverride: Bool, hadPrestigeOverride: Bool) {
        let cloudOffset = anchors.adminXPOffset ?? 0
        let localOffset = store.gamificationProfile.adminXPOffset
        if anchors.levelOverride != nil || anchors.prestigeOverride != nil {
            store.applyCloudGamificationProgression(anchors)
            return (anchors.levelOverride != nil, anchors.prestigeOverride != nil)
        }
        if cloudOffset != 0 && cloudOffset != localOffset {
            store.applyCloudGamificationProgression(anchors)
        }
        return (false, false)
    }

    func fetchGamificationAnchors(completion: @escaping (Result<RemoteGamificationAnchors?, Error>) -> Void) {
        guard let uid = currentUID, networkMonitor.isConnected else {
            completion(.failure(NSError(domain: "CloudSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in or offline"])))
            return
        }
        let gamificationRef = db.collection("users").document(uid).collection("gamification").document("current")
        gamificationRef.getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                    return
                }
                let gamificationData = (snapshot?.exists == true) ? snapshot?.data() : nil
                // Always read the public profile doc too. Its `level` field is
                // the admin-editable recovery hint; private gamification docs
                // intentionally don't store level because it is normally derived.
                self?.db.collection("users").document(uid).getDocument { userSnapshot, userError in
                    DispatchQueue.main.async {
                        if let userError {
                            completion(.failure(userError))
                            return
                        }
                        let userData = userSnapshot?.data()
                        guard gamificationData != nil || userData != nil else {
                            completion(.success(nil))
                            return
                        }
                        var combined = userData ?? [:]
                        if let gamificationData {
                            combined.merge(gamificationData) { _, privateValue in privateValue }
                            if let publicLevel = userData?["level"] {
                                combined["level"] = publicLevel
                            }
                            if let publicTitle = userData?["equippedTitle"] {
                                combined["equippedTitle"] = publicTitle
                            }
                        }
                        completion(.success(self?.gamificationAnchors(from: combined)))
                    }
                }
            }
        }
    }

    private func gamificationAnchors(from data: [String: Any]) -> RemoteGamificationAnchors? {
        let prestige = firestoreInt(data, key: "prestige", default: 0)
        let highWater = firestoreInt(data, key: "highWaterPrestige", default: 0)
        let snapshots = firestoreIntArray(data, key: "prestigeXPSnapshots")
        let hourSnapshots = firestoreDoubleArray(data, key: "prestigeHourSnapshots")
        let bestStreak = firestoreInt(data, key: "bestStreak", default: 0)
        let streakFreezes = firestoreInt(data, key: "streakFreezes", default: 0)
        let equippedTitle = data["equippedTitle"] as? String
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        let storedLevel = firestoreInt(data, key: "level", default: 1)
        let rawOverride = data["levelOverride"]
        let levelOverride: Int? = {
            guard let v = rawOverride else { return nil }
            if let i = v as? Int, i > 0 { return i }
            if let i64 = v as? Int64, i64 > 0 { return Int(i64) }
            if let n = v as? NSNumber, n.intValue > 0 { return n.intValue }
            // Tolerate string values (e.g. if admin types "13" instead of 13 in Firestore)
            if let s = v as? String, let i = Int(s), i > 0 { return i }
            return nil
        }()
        let rawPrestigeOverride = data["prestigeOverride"]
        let prestigeOverride: Int? = {
            guard let v = rawPrestigeOverride else { return nil }
            if let i = v as? Int, i >= 0 { return i }
            if let i64 = v as? Int64, i64 >= 0 { return Int(i64) }
            if let n = v as? NSNumber, n.intValue >= 0 { return n.intValue }
            if let s = v as? String, let i = Int(s), i >= 0 { return i }
            return nil
        }()
        // Admin-set floor fields on the user doc — never written by the client
        // (only by the admin panel Cloud Function) so they survive all syncs.
        let adminFloorLevel = firestoreOptionalInt(data, key: "adminFloorLevel")
        let adminFloorPrestige = firestoreOptionalInt(data, key: "adminFloorPrestige")
        let adminXPOffset = firestoreOptionalInt(data, key: "adminXPOffset")
        let adminEquippedTitle = (data["adminEquippedTitle"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let adminTitle = (adminEquippedTitle?.isEmpty == false) ? adminEquippedTitle : nil

        guard prestige > 0 || highWater > 0 || !snapshots.isEmpty || bestStreak > 0 || levelOverride != nil || prestigeOverride != nil || adminFloorLevel != nil || adminFloorPrestige != nil || adminTitle != nil || adminXPOffset != nil else { return nil }

        return RemoteGamificationAnchors(
            prestige: max(prestige, highWater),
            highWaterPrestige: highWater,
            prestigeXPSnapshots: snapshots,
            prestigeHourSnapshots: hourSnapshots,
            bestStreak: bestStreak,
            streakFreezes: streakFreezes,
            equippedTitle: equippedTitle,
            updatedAt: updatedAt,
            storedLevel: storedLevel,
            levelOverride: levelOverride,
            prestigeOverride: prestigeOverride,
            adminXPOffset: adminXPOffset,
            adminFloorLevel: adminFloorLevel,
            adminFloorPrestige: adminFloorPrestige,
            adminEquippedTitle: adminTitle
        )
    }

    private func firestoreInt(_ data: [String: Any], key: String, default defaultValue: Int) -> Int {
        if let value = data[key] as? Int { return value }
        if let value = data[key] as? Int64 { return Int(value) }
        if let value = data[key] as? Double { return Int(value) }
        if let value = data[key] as? NSNumber { return value.intValue }
        return defaultValue
    }

    private func firestoreOptionalInt(_ data: [String: Any], key: String) -> Int? {
        guard data[key] != nil else { return nil }
        if let value = data[key] as? Int { return value }
        if let value = data[key] as? Int64 { return Int(value) }
        if let value = data[key] as? Double { return Int(value) }
        if let value = data[key] as? NSNumber { return value.intValue }
        if let s = data[key] as? String, let i = Int(s) { return i }
        return nil
    }

    private func firestoreIntArray(_ data: [String: Any], key: String) -> [Int] {
        guard let raw = data[key] as? [Any] else { return [] }
        return raw.compactMap { element in
            if let value = element as? Int { return value }
            if let value = element as? Int64 { return Int(value) }
            if let value = element as? Double { return Int(value) }
            if let value = element as? NSNumber { return value.intValue }
            return nil
        }
    }

    private func firestoreDoubleArray(_ data: [String: Any], key: String) -> [Double] {
        guard let raw = data[key] as? [Any] else { return [] }
        return raw.compactMap { element in
            if let value = element as? Double { return value }
            if let value = element as? Int { return Double(value) }
            if let value = element as? Int64 { return Double(value) }
            if let value = element as? NSNumber { return value.doubleValue }
            return nil
        }
    }

    // MARK: - Auth lifecycle

    private func handleSignedIn(uid: String) {
        currentUID = uid
        hasAppliedRemoteEntries = false
        traceRepairGate(reason: "handleSignedIn")
        migrateLocalDataIfNeeded(uid: uid)
        runDailyCloudRepairIfNeeded()
        Task { @MainActor in
            await PushNotificationService.shared.registerForPushIfSignedIn()
            if FirebaseMigrationFlags.useServerStats {
                StatsListenerService.shared.startListening(uid: uid)
            }
            TopTrackersService.shared.startListening()
            // Friendship backfill is handled server-side by the reconcileFriendships
            // callable (Admin SDK), invoked on every FriendsService.startListening.
            // The former client-side backfill wrote friendship docs directly, which
            // the tightened firestore.rules now (correctly) forbid.
        }
    }

    private func handleSignedOut() {
        let uid = currentUID
        // Stop listeners FIRST to prevent callbacks from processing stale data.
        if let entriesListenerKey {
            FirebaseListenerRegistry.shared.remove(key: entriesListenerKey)
        }
        entriesListener?.remove()
        entriesListener = nil
        entriesListenerKey = nil
        if let settingsListenerKey {
            FirebaseListenerRegistry.shared.remove(key: settingsListenerKey)
        }
        settingsListener?.remove()
        settingsListener = nil
        settingsListenerKey = nil
        if let gamificationListenerKey {
            FirebaseListenerRegistry.shared.remove(key: gamificationListenerKey)
        }
        gamificationListener?.remove()
        gamificationListener = nil
        gamificationListenerKey = nil
        if let uid {
            FirebaseListenerRegistry.shared.stopAll(for: uid)
        }
        currentUID = nil
        hasAppliedRemoteEntries = false
        isPulling = false
        isSyncing = false
        syncError = nil
        Task { @MainActor [weak self] in
            // Only tear the shared listener singletons down if the user is still
            // signed out. If they signed back in (even as a different account)
            // before this deferred task ran, that new session's startListening
            // has already re-pointed these singletons at the new uid — tearing
            // them down here would silently wipe the new user's live listeners
            // and kill Friends/Activity until something re-triggered them.
            // handleSignedIn sets currentUID synchronously on this same actor,
            // so this guard reflects the latest sign-in state.
            if self?.currentUID == nil {
                ActivityFeedService.shared.stopListening()
                FriendsBoardService.shared.stopListening()
                FriendShiftNudgeService.shared.stopListening()
                FriendsService.shared.stopListening()
                StatsListenerService.shared.stopListening()
                TopTrackersService.shared.stopListening()
                ProfilePhotoManager.shared.clearFriendCache()
            }
            // The push token is keyed to the signing-out uid specifically, so
            // clearing it is always correct regardless of any subsequent sign-in.
            if let uid {
                await PushNotificationService.shared.clearTokenOnSignOut(uid: uid)
            }
        }
    }

    /// Ensures whatever this device holds locally always ends up in the cloud
    /// on sign-in — never left stranded on-device. This is always safe to do
    /// automatically without asking the user, because entries are keyed by
    /// their own stable UUID: `applyRemoteEntries` merges the cloud snapshot
    /// with local entries additively (any entry present in only one side is
    /// kept) and re-uploads anything local-only, so there is no path here
    /// that can silently discard a shift, regardless of whether the account
    /// already has cloud data from another device or a previous install.
    private func migrateLocalDataIfNeeded(uid: String) {
        let entriesRef = db.collection("users").document(uid).collection("entries")
        let timeEntriesRef = db.collection("users").document(uid).collection("timeEntries")

        entriesRef.limit(to: 1).getDocuments { [weak self] entriesSnap, _ in
            guard let self else { return }
            let hasLegacyEntries = !(entriesSnap?.documents.isEmpty ?? true)
            if hasLegacyEntries {
                self.finishMigrateLocalDataIfNeeded(uid: uid, remoteEmpty: false)
                return
            }
            timeEntriesRef.limit(to: 1).getDocuments { [weak self] timeSnap, error in
                guard let self else { return }
                let remoteEmpty = (timeSnap?.documents.isEmpty ?? true)
                self.finishMigrateLocalDataIfNeeded(uid: uid, remoteEmpty: remoteEmpty, loadError: error)
            }
        }
    }

    private func finishMigrateLocalDataIfNeeded(uid: String, remoteEmpty: Bool, loadError: Error? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.currentUID == uid else { return }
            if loadError != nil {
                self.startCloudListeners(uid: uid)
                self.hoursStore?.syncProfileOnLogin()
                return
            }
            guard let store = self.hoursStore else { return }

            self.startCloudListeners(uid: uid)

            let localEntries = store.allEntriesIncludingArchive()
            if remoteEmpty, !localEntries.isEmpty {
                self.isSyncing = true
                self.syncAll(entries: localEntries, settings: store.paySettings) { [weak self] _ in
                    guard let self, self.currentUID == uid else { return }
                    self.isSyncing = false
                    self.saveSettings(store.paySettings)
                }
            } else if !remoteEmpty {
                self.pullFromCloud()
            } else {
                store.syncProfileSnapshotToCloud()
            }
        }
    }

    private func startCloudListeners(uid: String) {
        startEntriesListener(uid: uid)
        startSettingsListener(uid: uid)
        startGamificationListener(uid: uid)
    }

    private func startGamificationListener(uid: String) {
        gamificationListener?.remove()
        let registration = db.collection("users").document(uid)
            .collection("gamification").document("current")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                DispatchQueue.main.async {
                    guard self.currentUID == uid else { return }
                    if let error {
                        FirestoreOperationLog.listenerError(
                            owner: .cloudSync,
                            purpose: "gamification",
                            uid: uid,
                            error: error
                        )
                        return
                    }
                    guard let data = snapshot?.data(),
                          let anchors = self.gamificationAnchors(from: data) else {
                        return
                    }
                    self.handleRemoteGamificationUpdate(anchors)
                }
            }
        gamificationListener = registration
        gamificationListenerKey = FirebaseListenerRegistry.shared.register(
            owner: .cloudSync,
            purpose: "gamification",
            uid: uid,
            registration: registration
        )
    }

    private func handleRemoteGamificationUpdate(_ anchors: RemoteGamificationAnchors) {
        guard let store = hoursStore else { return }

        if anchors.levelOverride != nil || anchors.prestigeOverride != nil {
            store.applyCloudGamificationProgression(anchors)
            reconcileProgressionOverrideWithCloud(
                store: store,
                hadLevelOverride: anchors.levelOverride != nil,
                hadPrestigeOverride: anchors.prestigeOverride != nil
            )
            return
        }

        let cloudOffset = anchors.adminXPOffset ?? 0
        if cloudOffset != store.gamificationProfile.adminXPOffset {
            store.applyCloudGamificationProgression(anchors)
        }
    }

    private func startEntriesListener(uid: String) {
        entriesListener?.remove()
        let collection = entriesCollectionName()
        let registration = db.collection("users").document(uid).collection(collection)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                DispatchQueue.main.async {
                    guard self.currentUID == uid else { return }
                    if let error {
                        FirestoreOperationLog.listenerError(owner: .cloudSync, purpose: collection, uid: uid, error: error)
                        self.syncError = error.localizedDescription
                        return
                    }
                    let entries = snapshot?.documents.compactMap { self.entry(from: $0.data()) } ?? []
                    // Tombstone reconciliation may only trust a snapshot that is
                    // server-sourced AND free of latency-compensated local
                    // mutations — a cached/pending-writes snapshot omits docs the
                    // user deleted locally even when the server still has them.
                    let isAuthoritative = (snapshot.map { !$0.metadata.isFromCache && !$0.metadata.hasPendingWrites }) ?? false
                    self.hasAppliedRemoteEntries = true
                    self.hoursStore?.applyRemoteEntries(entries, isAuthoritativeSnapshot: isAuthoritative)
                    self.lastSyncDate = Date()
                    self.syncError = nil
                }
            }
        entriesListener = registration
        entriesListenerKey = FirebaseListenerRegistry.shared.register(
            owner: .cloudSync,
            purpose: collection,
            uid: uid,
            registration: registration
        )
    }

    private func startSettingsListener(uid: String) {
        settingsListener?.remove()
        let registration = db.collection("users").document(uid).collection("paySettings").document("current")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                DispatchQueue.main.async {
                    guard self.currentUID == uid else { return }
                    if let error {
                        FirestoreOperationLog.listenerError(owner: .cloudSync, purpose: "paySettings", uid: uid, error: error)
                        self.syncError = error.localizedDescription
                        return
                    }
                    guard let data = snapshot?.data(),
                          let json = try? JSONSerialization.data(withJSONObject: data),
                          let settings = try? self.decoder.decode(PaySettings.self, from: json) else {
                        return
                    }
                    self.hoursStore?.applyRemoteSettings(settings)
                    self.lastSyncDate = Date()
                }
            }
        settingsListener = registration
        settingsListenerKey = FirebaseListenerRegistry.shared.register(
            owner: .cloudSync,
            purpose: "paySettings",
            uid: uid,
            registration: registration
        )
    }

    private func entriesCollectionName() -> String {
        // Direct Firestore subcollection writes from some devices hang waiting
        // for server ack on `timeEntries` / `debugEvents`. The legacy `entries`
        // collection still syncs reliably on those accounts, and the server
        // falls back to it whenever `timeEntries` is empty. Bulk repair uploads
        // go through Cloud Functions instead (see uploadEntriesInBatches).
        "entries"
    }

    // MARK: - Encoding

    /// Firebase Callable encoding only accepts Foundation JSON types
    /// (NSString/NSNumber/NSArray/NSDictionary). Swift Bool/String values
    /// and Firestore FieldValue objects must be converted first.
    private func functionsCallablePayload(_ value: Any) -> Any {
        switch value {
        case let string as String:
            return string as NSString
        case let number as NSNumber:
            return number
        case let int as Int:
            return NSNumber(value: int)
        case let int64 as Int64:
            return NSNumber(value: int64)
        case let double as Double:
            return NSNumber(value: double)
        case let float as Float:
            return NSNumber(value: float)
        case let bool as Bool:
            return NSNumber(value: bool)
        case let dict as [String: Any]:
            return NSDictionary(dictionary: dict.mapValues { functionsCallablePayload($0) })
        case let array as [Any]:
            return NSArray(array: array.map { functionsCallablePayload($0) })
        default:
            return String(describing: value) as NSString
        }
    }

    private func entryCallablePayload(_ entry: WorkEntry) -> [String: Any] {
        guard let data = try? encoder.encode(entry),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private func entryFirestorePayload(_ entry: WorkEntry) -> [String: Any] {
        guard let data = try? encoder.encode(entry),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        dict["updatedAt"] = FieldValue.serverTimestamp()
        return dict
    }

    private func entry(from data: [String: Any]) -> WorkEntry? {
        var payload = data
        payload.removeValue(forKey: "updatedAt")
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let entry = try? decoder.decode(WorkEntry.self, from: json) else {
            return nil
        }
        return entry
    }

    // MARK: - Offline queue

    private func queueDeleteForSync(_ entryID: UUID) {
        var pending = getPendingDeletes()
        if !pending.contains(entryID.uuidString) {
            pending.append(entryID.uuidString)
        }
        savePendingDeletes(pending)
    }

    /// Entry ids the user has deleted that must stay hidden until an
    /// authoritative snapshot confirms removal. Consulted by
    /// `HoursStore.applyRemoteEntries`. Includes both queued deletes and
    /// server-confirmed ones — after the delete callable succeeds, the client
    /// SDK's cache still holds the doc until the listener receives the next
    /// server snapshot, so dropping the tombstone at callable success let a
    /// relaunch's cache-sourced snapshot resurrect the entry (and the
    /// local-only re-upload path then re-created the doc on the server).
    func pendingDeletionIDs() -> Set<String> {
        Set(getPendingDeletes()).union(getConfirmedDeletes())
    }

    /// Clears tombstones for entries the server no longer returns (deletion
    /// confirmed). Keeps tombstones for ids still present remotely so the
    /// deletion keeps applying until it fully propagates.
    func reconcileTombstones(presentRemoteIDs: Set<String>) {
        let pending = getPendingDeletes()
        if !pending.isEmpty {
            let stillPending = pending.filter { presentRemoteIDs.contains($0) }
            if stillPending.count != pending.count {
                savePendingDeletes(stillPending)
            }
        }
        let confirmed = getConfirmedDeletes()
        if !confirmed.isEmpty {
            let stillConfirmed = confirmed.filter { presentRemoteIDs.contains($0) }
            if stillConfirmed.count != confirmed.count {
                saveConfirmedDeletes(stillConfirmed)
            }
        }
    }

    /// Cancels a pending deletion tombstone (e.g. when the same entry is saved).
    private func clearDeleteTombstone(_ entryID: UUID) {
        let id = entryID.uuidString
        let pending = getPendingDeletes()
        if pending.contains(id) {
            savePendingDeletes(pending.filter { $0 != id })
        }
        let confirmed = getConfirmedDeletes()
        if confirmed.contains(id) {
            saveConfirmedDeletes(confirmed.filter { $0 != id })
        }
    }

    private func getPendingDeletes() -> [String] {
        UserDefaults.standard.stringArray(forKey: "pending_deletes") ?? []
    }

    private func savePendingDeletes(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: "pending_deletes")
        checkPendingChanges()
    }

    /// Ids the delete callable has confirmed removed server-side but that an
    /// authoritative listener snapshot hasn't yet shown as absent. They must
    /// keep filtering snapshots (the SDK cache can still carry the doc) but
    /// no longer need the callable retried, so they don't count as pending
    /// changes.
    private func getConfirmedDeletes() -> [String] {
        UserDefaults.standard.stringArray(forKey: "confirmed_delete_tombstones") ?? []
    }

    private func saveConfirmedDeletes(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: "confirmed_delete_tombstones")
    }

    private var isSyncingPendingDeletes = false

    /// Pushes queued deletion tombstones through the server-side
    /// clientDeleteTimeEntriesBatch callable (which also recomputes stats and
    /// patches the leaderboard). Chunked at the callable's 200-id cap and
    /// re-entrancy-guarded; tombstones are only cleared after the server
    /// confirms, so a failed call just retries on the next foreground/online
    /// tick.
    private func syncPendingDeletes() {
        guard currentUID != nil, networkMonitor.isConnected else { return }
        guard !isSyncingPendingDeletes else { return }
        let pending = getPendingDeletes()
        guard !pending.isEmpty else { return }
        isSyncingPendingDeletes = true
        let chunk = Array(pending.prefix(200))
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.functions.httpsCallable("clientDeleteTimeEntriesBatch").call(
                    self.functionsCallablePayload(["entryIds": chunk])
                )
                let chunkSet = Set(chunk)
                let remaining = self.getPendingDeletes().filter { !chunkSet.contains($0) }
                // Server confirmed — but keep the ids as tombstones until an
                // authoritative snapshot shows them gone. The SDK cache still
                // has the docs, and a relaunch replays that cache as the first
                // snapshot; without the tombstone it resurrects the entries.
                var confirmed = self.getConfirmedDeletes()
                for id in chunk where !confirmed.contains(id) {
                    confirmed.append(id)
                }
                self.saveConfirmedDeletes(confirmed)
                self.savePendingDeletes(remaining)
                StatsListenerService.shared.markEntryWritePending()
                // Deleting shifts lowers entry-derived XP; push the fresh anchors
                // and recompute so the published level/leaderboard row drop too
                // (the callable's own recompute ran against the pre-delete XP).
                self.scheduleStatsRecomputeDebounced()
                self.isSyncingPendingDeletes = false
                if !remaining.isEmpty {
                    self.syncPendingDeletes()
                }
            } catch {
                // Leave the tombstones queued; retried on the next sync tick.
                self.isSyncingPendingDeletes = false
            }
        }
    }

    private func queueEntryForSync(_ entry: WorkEntry) {
        var pending = getPendingEntries()
        if let idx = pending.firstIndex(where: { $0.id == entry.id }) {
            pending[idx] = entry
        } else {
            pending.append(entry)
        }
        savePendingEntries(pending)
    }

    private func getPendingEntries() -> [WorkEntry] {
        guard let data = UserDefaults.standard.data(forKey: "pending_entries") else { return [] }
        return (try? decoder.decode([WorkEntry].self, from: data)) ?? []
    }

    private func savePendingEntries(_ entries: [WorkEntry]) {
        if let data = try? encoder.encode(entries) {
            UserDefaults.standard.set(data, forKey: "pending_entries")
            UserDefaults.standard.set(entries.count, forKey: "pending_entries_count")
        }
        checkPendingChanges()
    }

    private func markEntryAsSynced(_ entryID: UUID) {
        var pending = getPendingEntries()
        pending.removeAll { $0.id == entryID }
        savePendingEntries(pending)
    }

    private func syncWhenOnline() {
        guard currentUID != nil, networkMonitor.isConnected, let store = hoursStore else { return }
        let pendingProfile = UserDefaults.standard.bool(forKey: pendingProfileSyncKey)
        syncPendingDeletes()
        if pendingChanges > 0 {
            syncAll(entries: store.allEntriesIncludingArchive(), settings: store.paySettings) { _ in }
        } else if pendingProfile {
            saveProfileSnapshot(store: store) { _ in }
        }
    }
}

// MARK: - Profile snapshot payload (built off main thread)

private struct ChequeDaySnapshot: Sendable {
    let date: String
    let hours: Double
    let shifts: Int
}

private struct ProfileSnapshotInputs {
    let displayName: String
    let shareHours: Bool
    let shareBadges: Bool
    let shareActivity: Bool
    let acceptInvites: Bool
    let companyName: String
    let companyOccupation: String
    let companyStartTS: Double
    let companyHoursLogged: Double
    let companyDaysWorked: Int
    let unlockedBadges: [SharedBadgeSummary]
    let publishedEquippedTitle: String
    let chequeDailySummary: [ChequeDaySnapshot]
    let chequeWindowStart: String
    let chequeWindowCutoff: String
    let profilePhotoURL: String?
    let friendShiftAlerts: Bool
    let countryCode: String

    @MainActor
    static func capture(from store: HoursStore) -> ProfileSnapshotInputs {
        let profile = store.gamificationProfile
        let displayName = UserDefaults.standard.string(forKey: "profile_display_name") ?? "Worker"
        let privacy = SocialPrivacyStore.shared.flags
        let companyName = UserDefaults.standard.string(forKey: "company_name")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let companyOccupation = UserDefaults.standard.string(forKey: "company_occupation")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let companyStartTS = UserDefaults.standard.double(forKey: "company_start_date_ts")
        let companyStartDate = companyStartTS > 0 ? Date(timeIntervalSince1970: companyStartTS) : nil
        let companyEntries: [WorkEntry] = {
            guard privacy.shareHours else { return [] }
            let allWorkEntries = store.allEntriesIncludingArchive().filter { !$0.isOffDay }
            guard let companyStartDate else { return allWorkEntries }
            let startDay = Calendar.current.startOfDay(for: companyStartDate)
            return allWorkEntries.filter { Calendar.current.startOfDay(for: $0.date) >= startDay }
        }()
        let companyHoursLogged = companyEntries.reduce(0) { $0 + $1.paidHours }
        let companyDaysWorked = Set(companyEntries.map { Calendar.current.startOfDay(for: $0.date) }).count
        let sharedBadges = privacy.shareBadges
            ? AchievementsView.earnedBadgesForSharing(from: store)
            : []
        let equippedTitle = privacy.shareBadges ? (profile.equippedTitle ?? "") : ""
        let publishedEquippedTitle = store.adminEquippedTitleOverride ?? equippedTitle
        let currentCycle = store.currentPayCycle()
        let cycleEntries = PayCycleEngine.entries(store.entries, in: currentCycle)

        let isoFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.calendar = Calendar.current
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()

        let chequeDailySummary: [ChequeDaySnapshot]
        let chequeWindowStart: String
        let chequeWindowCutoff: String
        if privacy.shareHours {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let grouped = Dictionary(grouping: cycleEntries.filter { !$0.isOffDay }) {
                cal.startOfDay(for: $0.date)
            }
            var summary: [ChequeDaySnapshot] = []
            var cursor = cal.startOfDay(for: currentCycle.start)
            let lastIncluded = min(cal.startOfDay(for: currentCycle.cutoff), today)
            while cursor <= lastIncluded {
                let dayEntries = grouped[cursor] ?? []
                summary.append(ChequeDaySnapshot(
                    date: isoFormatter.string(from: cursor),
                    hours: dayEntries.reduce(0.0) { $0 + $1.paidHours },
                    shifts: dayEntries.count
                ))
                guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            chequeDailySummary = summary
            chequeWindowStart = isoFormatter.string(from: currentCycle.start)
            chequeWindowCutoff = isoFormatter.string(from: currentCycle.cutoff)
        } else {
            chequeDailySummary = []
            chequeWindowStart = ""
            chequeWindowCutoff = ""
        }

        return ProfileSnapshotInputs(
            displayName: displayName,
            shareHours: privacy.shareHours,
            shareBadges: privacy.shareBadges,
            shareActivity: privacy.shareActivity,
            acceptInvites: privacy.acceptInvites,
            companyName: companyName,
            companyOccupation: companyOccupation,
            companyStartTS: companyStartTS,
            companyHoursLogged: companyHoursLogged,
            companyDaysWorked: companyDaysWorked,
            unlockedBadges: sharedBadges,
            publishedEquippedTitle: publishedEquippedTitle,
            chequeDailySummary: chequeDailySummary,
            chequeWindowStart: chequeWindowStart,
            chequeWindowCutoff: chequeWindowCutoff,
            profilePhotoURL: ProfilePhotoManager.shared.remotePhotoURL,
            friendShiftAlerts: SmartNotifier.shared.friendShiftNotificationsEnabled,
            countryCode: CountryFlag.hasChosenCountry ? CountryFlag.resolvedCode : ""
        )
    }

    nonisolated func makePayload() -> [String: Any] {
        // Server (Cloud Function recomputeUserStats) is the sole writer of:
        // level, prestige, totalXP, currentStreak, bestStreak, totalHours,
        // chequeHours, weeklyHours, weeklyShiftsLogged, weeklyDaysLogged, badgeCount.
        // Client only writes display, privacy, and social fields here.
        var fields: [String: Any] = [
            "displayName": displayName,
            "equippedTitle": publishedEquippedTitle,
            "privacy": [
                "shareHours": shareHours,
                "shareBadges": shareBadges,
                "shareActivity": shareActivity,
                "acceptInvites": acceptInvites
            ],
            "acceptInvites": acceptInvites,
            "friendShiftAlerts": friendShiftAlerts,
            "clientSyncBuild": "repair-diagnostics-v4",
            "updatedAt": FieldValue.serverTimestamp(),
            "lookupEmail": FieldValue.delete(),
            "profileHoursDebug": FieldValue.delete()
        ]
        if !countryCode.isEmpty {
            fields["countryCode"] = countryCode
        } else {
            fields["countryCode"] = FieldValue.delete()
        }
        // Company PII (name/occupation/start-date) is written to users/{uid}, which
        // is world-readable to any signed-in user. Only publish it when the user has
        // opted into hour-sharing; when shareHours is off, actively delete any values
        // a prior build may have left behind so opted-out users stop leaking their
        // employer/title/start-date. The server only reads these when shareHours is on.
        if shareHours && !companyName.isEmpty {
            fields["companyName"] = companyName
        } else {
            fields["companyName"] = FieldValue.delete()
        }
        if shareHours && !companyOccupation.isEmpty {
            fields["companyOccupation"] = companyOccupation
        } else {
            fields["companyOccupation"] = FieldValue.delete()
        }
        if shareHours && companyStartTS > 0 {
            fields["companyStartDate"] = Timestamp(date: Date(timeIntervalSince1970: companyStartTS))
        } else {
            fields["companyStartDate"] = FieldValue.delete()
        }
        if let profilePhotoURL {
            fields["profilePhotoURL"] = profilePhotoURL
        } else {
            fields["profilePhotoURL"] = FieldValue.delete()
        }
        // Company stats (companyHoursLogged/companyDaysWorked) and the cheque
        // breakdown (chequeDailySummary/chequeWindowStart/chequeWindowCutoff)
        // are owned exclusively by the server (recomputeUserStats). The client
        // must not write them: a stale client snapshot would clobber the
        // server's fresh values, causing a friend's "This Cheque" daily
        // breakdown to disagree with chequeHours. The server also clears these
        // fields when shareHours is off, so privacy stays enforced.
        // (companyName/companyOccupation/companyStartDate above are user inputs
        //  the server reads, so those are still written here.)
        if shareBadges {
            fields["unlockedBadgeSummaries"] = unlockedBadges.map { badge in
                [
                    "icon": badge.icon,
                    "name": badge.name,
                    "detail": badge.detail,
                    "isLegend": badge.isLegend,
                    "order": badge.order
                ]
            }
        } else {
            fields["unlockedBadgeSummaries"] = FieldValue.delete()
        }
        return fields
    }
}
