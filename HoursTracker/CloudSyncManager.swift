import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Cloud Sync Manager (Firestore)

final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var pendingChanges = 0
    @Published var showRemoteOverwriteAlert = false

    /// True when Firestore is available and user is signed in.
    var isCloudAvailable: Bool { currentUID != nil }

    /// Resolved lazily so we don't touch `Firestore.firestore()` at construction
    /// time. If `GoogleService-Info.plist` is missing and `FirebaseApp.configure`
    /// never ran, accessing `db` would otherwise crash with "Default FirebaseApp
    /// is not configured". With lazy initialization the singleton still
    /// constructs cleanly; only callers that actually try to read/write will
    /// hit Firebase's runtime check (and they all gate on `isCloudAvailable`
    /// / `currentUID` first, which stays `nil` without a signed-in user).
    private lazy var db: Firestore = Firestore.firestore()
    private let networkMonitor = NetworkMonitor.shared
    private var authService: AuthService?
    private weak var hoursStore: HoursStore?

    private var currentUID: String?
    private var entriesListener: ListenerRegistration?
    private var entriesListenerKey: String?
    private var settingsListener: ListenerRegistration?
    private var settingsListenerKey: String?
    /// True once Firestore has delivered at least one entries snapshot this session.
    /// HoursStore uses this to avoid stale UserDefaults overwriting cloud data.
    private(set) var hasAppliedRemoteEntries = false
    private var isPulling = false
    private var cancellables = Set<AnyCancellable>()

    private let remoteOverwriteConfirmedKey = "cloud_remote_overwrite_confirmed_v1"
    private let pendingProfileSyncKey = "pending_profile_sync"
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
                if isConnected { self?.syncWhenOnline() }
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
        let primaryCollection = FirebaseMigrationFlags.useTimeEntriesPath ? "timeEntries" : "entries"
        let primaryRef = db.collection("users").document(uid).collection(primaryCollection).document(entry.id.uuidString)

        FirestoreOperationLog.write(operation: "saveEntry.\(primaryCollection)", uid: uid) { done in
            primaryRef.setData(payload, merge: true, completion: done)
        } completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.queueEntryForSync(entry)
                    self.syncError = error.localizedDescription
                    completion(.failure(error))
                case .success:
                    self.markEntryAsSynced(entry.id)
                    self.checkPendingChanges()
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
                    completion(.success(()))
                }
            }
        }
    }

    func deleteEntry(_ entry: WorkEntry, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = currentUID else {
            completion(.success(()))
            return
        }
        guard networkMonitor.isConnected else {
            queueDeleteForSync(entry.id)
            completion(.success(()))
            return
        }
        let primaryCollection = FirebaseMigrationFlags.useTimeEntriesPath ? "timeEntries" : "entries"
        let primaryRef = db.collection("users").document(uid)
            .collection(primaryCollection).document(entry.id.uuidString)

        FirestoreOperationLog.write(operation: "deleteEntry.\(primaryCollection)", uid: uid) { done in
            primaryRef.delete(completion: done)
        } completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success:
                    if FirebaseMigrationFlags.useLegacyEntryMirror {
                        self.db.collection("users").document(uid)
                            .collection("entries").document(entry.id.uuidString)
                            .delete()
                    }
                    if FirebaseMigrationFlags.useServerStats {
                        Task { @MainActor in
                            StatsListenerService.shared.markEntryWritePending()
                        }
                    }
                    if !FirebaseMigrationFlags.skipProfileSnapshotOnEntryCRUD,
                       let store = self.hoursStore {
                        self.saveProfileSnapshot(store: store)
                    }
                    completion(.success(()))
                }
            }
        }
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
            DispatchQueue.main.async { completion() }
            return
        }
        isPulling = true
        fetchRemoteAndMerge { [weak self] in
            self?.isPulling = false
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
            if let entries = pulledEntries {
                self.hoursStore?.applyRemoteEntries(entries)
            }
            if let settings = pulledSettings {
                self.hoursStore?.applyRemoteSettings(settings)
            }
            // After entries are applied (totalXP is now correct), synthesise a
            // missing XP snapshot from the cloud-stored level so users whose
            // prestigeXPSnapshots were wiped by the Codable-corruption bug are
            // automatically restored to their previous level within the tier.
            // `levelOverride` (set on gamification/current) takes priority and
            // is cleared from Firestore after a single application so it acts
            // as a one-shot admin correction that cannot be overwritten by the
            // public profile listener race.
            if let anchors = pulledGamification {
                // Persistent admin override — clear local floor when absent in cloud.
                self.hoursStore?.applyAdminLevel(anchors.adminLevel)
                if let adminTitle = anchors.adminEquippedTitle, !adminTitle.isEmpty {
                    self.hoursStore?.applyAdminEquippedTitle(adminTitle)
                } else {
                    self.hoursStore?.applyAdminEquippedTitle(nil)
                }
                // One-shot levelOverride from gamification/current — upward recovery only.
                if let override = anchors.levelOverride {
                    self.hoursStore?.applySyntheticLevelSnapshot(storedLevel: override)
                    self.clearLevelOverride()
                } else if anchors.adminLevel == nil, anchors.storedLevel > 1 {
                    // When adminLevel is set, level follows XP with a floor — do not
                    // rewrite prestige snapshots from the public `level` field.
                    self.hoursStore?.applySyntheticLevelSnapshot(storedLevel: anchors.storedLevel)
                }
            } else {
                self.hoursStore?.applyAdminLevel(nil)
                self.hoursStore?.applyAdminEquippedTitle(nil)
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
        db.collection("users").document(uid).collection("paySettings").document("current")
            .setData(json, merge: true) { error in
                DispatchQueue.main.async {
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
                completion(.success(()))
            } catch {
                UserDefaults.standard.set(true, forKey: self.pendingProfileSyncKey)
                self.checkPendingChanges()
                completion(.failure(error))
            }
        }
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

    private func clearLevelOverride() {
        guard let uid = currentUID else { return }
        db.collection("users").document(uid).collection("gamification").document("current")
            .updateData(["levelOverride": FieldValue.delete()]) { _ in }
    }

    func saveGamificationAnchors(store: HoursStore, completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
        guard let uid = currentUID, networkMonitor.isConnected else {
            completion(.success(()))
            return
        }
        let profile = store.gamificationProfile
        let payload: [String: Any] = [
            "prestige": profile.prestige,
            "prestigeXPSnapshots": profile.prestigeXPSnapshots,
            "prestigeHourSnapshots": profile.prestigeHourSnapshots,
            "bestStreak": profile.bestStreak,
            "streakFreezes": profile.streakFreezes,
            "equippedTitle": profile.equippedTitle ?? "",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid).collection("gamification").document("current")
            .setData(payload, merge: true) { error in
                DispatchQueue.main.async {
                    if let error {
                        completion(.failure(error))
                    } else {
                        store.markGamificationCloudSynced()
                        completion(.success(()))
                    }
                }
            }
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
        // Persistent admin-level field on the public user doc — never written
        // by the client so it survives all future syncs untouched.
        let adminLevel = firestoreOptionalInt(data, key: "adminLevel")
        let adminEquippedTitle = (data["adminEquippedTitle"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let adminTitle = (adminEquippedTitle?.isEmpty == false) ? adminEquippedTitle : nil

        guard prestige > 0 || highWater > 0 || !snapshots.isEmpty || bestStreak > 0 || levelOverride != nil || adminLevel != nil || adminTitle != nil else { return nil }

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
            adminLevel: adminLevel,
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

    func confirmRemoteOverwrite() {
        UserDefaults.standard.set(true, forKey: remoteOverwriteConfirmedKey)
        showRemoteOverwriteAlert = false
        if let uid = currentUID {
            startCloudListeners(uid: uid)
            pullFromCloud()
        }
    }

    // MARK: - Auth lifecycle

    private let backfillKey = "friendships_backfill_complete_v1"

    private func handleSignedIn(uid: String) {
        currentUID = uid
        hasAppliedRemoteEntries = false
        migrateLocalDataIfNeeded(uid: uid)
        Task { @MainActor in
            await PushNotificationService.shared.registerForPushIfSignedIn()
            if FirebaseMigrationFlags.useServerStats {
                StatsListenerService.shared.startListening(uid: uid)
            }
            if !UserDefaults.standard.bool(forKey: backfillKey) {
                await backfillFriendships(uid: uid)
            }
        }
    }

    private func backfillFriendships(uid: String) async {
        do {
            let friendsSnap = try await db.collection("users").document(uid)
                .collection("friends").getDocuments()
            guard !friendsSnap.documents.isEmpty else {
                UserDefaults.standard.set(true, forKey: backfillKey)
                return
            }
            let batch = db.batch()
            var count = 0
            for doc in friendsSnap.documents {
                let friendUid = doc.documentID
                let sorted = [uid, friendUid].sorted()
                let pairId = "\(sorted[0])_\(sorted[1])"
                let ref = db.collection("friendships").document(pairId)
                let existing = try await ref.getDocument()
                if existing.exists { continue }
                let reciprocal = try await db.collection("users").document(friendUid)
                    .collection("friends").document(uid).getDocument()
                if !reciprocal.exists { continue }
                let addedAt = doc.data()["addedAt"] as? Timestamp ?? Timestamp(date: Date())
                batch.setData([
                    "userA": sorted[0],
                    "userB": sorted[1],
                    "createdAt": addedAt,
                    "createdBy": uid
                ], forDocument: ref)
                count += 1
            }
            if count > 0 {
                try await batch.commit()
            }
            UserDefaults.standard.set(true, forKey: backfillKey)
        } catch {
            #if DEBUG
            print("Friendship backfill error: \(error.localizedDescription)")
            #endif
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
        if let uid {
            FirebaseListenerRegistry.shared.stopAll(for: uid)
        }
        currentUID = nil
        hasAppliedRemoteEntries = false
        isPulling = false
        isSyncing = false
        syncError = nil
        showRemoteOverwriteAlert = false
        Task { @MainActor in
            ActivityFeedService.shared.stopListening()
            FriendsBoardService.shared.stopListening()
            FriendShiftNudgeService.shared.stopListening()
            FriendsService.shared.stopListening()
            StatsListenerService.shared.stopListening()
            ProfilePhotoManager.shared.clearFriendCache()
            if let uid {
                await PushNotificationService.shared.clearTokenOnSignOut(uid: uid)
            }
        }
    }

    private func migrateLocalDataIfNeeded(uid: String) {
        db.collection("users").document(uid).collection(entriesCollectionName()).limit(to: 1).getDocuments { [weak self] snapshot, error in
            guard let self else { return }
            DispatchQueue.main.async {
                // Bail if the user signed out or switched accounts before this callback fired.
                guard self.currentUID == uid else { return }
                if error != nil {
                    self.startCloudListeners(uid: uid)
                    self.hoursStore?.syncProfileOnLogin()
                    return
                }
                let remoteEmpty = snapshot?.documents.isEmpty ?? true
                guard let store = self.hoursStore else { return }

                if remoteEmpty, !store.entries.isEmpty {
                    self.isSyncing = true
                    self.syncAll(entries: store.entries, settings: store.paySettings) { [weak self] _ in
                        guard let self, self.currentUID == uid else { return }
                        self.isSyncing = false
                        self.startCloudListeners(uid: uid)
                        self.saveSettings(store.paySettings)
                    }
                } else if !remoteEmpty, !store.entries.isEmpty,
                          !UserDefaults.standard.bool(forKey: self.remoteOverwriteConfirmedKey) {
                    self.showRemoteOverwriteAlert = true
                } else {
                    self.startCloudListeners(uid: uid)
                    if !remoteEmpty {
                        self.pullFromCloud()
                    } else {
                        store.syncProfileSnapshotToCloud()
                    }
                }
            }
        }
    }

    private func startCloudListeners(uid: String) {
        startEntriesListener(uid: uid)
        startSettingsListener(uid: uid)
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
                    guard self.showRemoteOverwriteAlert == false else { return }
                    let entries = snapshot?.documents.compactMap { self.entry(from: $0.data()) } ?? []
                    self.hasAppliedRemoteEntries = true
                    self.hoursStore?.applyRemoteEntries(entries)
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
                    guard self.showRemoteOverwriteAlert == false else { return }
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
        FirebaseMigrationFlags.useTimeEntriesPath ? "timeEntries" : "entries"
    }

    // MARK: - Encoding

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

    private func getPendingDeletes() -> [String] {
        UserDefaults.standard.stringArray(forKey: "pending_deletes") ?? []
    }

    private func savePendingDeletes(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: "pending_deletes")
        checkPendingChanges()
    }

    private func syncPendingDeletes() {
        guard let uid = currentUID, networkMonitor.isConnected else { return }
        let pending = getPendingDeletes()
        guard !pending.isEmpty else { return }
        let collection = entriesCollectionName()
        var remaining = pending
        for idString in pending {
            db.collection("users").document(uid).collection(collection).document(idString)
                .delete { [weak self] error in
                    if error == nil {
                        remaining.removeAll { $0 == idString }
                        self?.savePendingDeletes(remaining)
                    }
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
            syncAll(entries: store.entries, settings: store.paySettings) { _ in }
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
            friendShiftAlerts: SmartNotifier.shared.friendShiftNotificationsEnabled
        )
    }

    nonisolated func makePayload() -> [String: Any] {
        let companyStartDate = companyStartTS > 0 ? Date(timeIntervalSince1970: companyStartTS) : nil
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
            "updatedAt": FieldValue.serverTimestamp(),
            "lookupEmail": FieldValue.delete(),
            "profileHoursDebug": FieldValue.delete()
        ]
        if !companyName.isEmpty {
            fields["companyName"] = companyName
        } else {
            fields["companyName"] = FieldValue.delete()
        }
        if !companyOccupation.isEmpty {
            fields["companyOccupation"] = companyOccupation
        } else {
            fields["companyOccupation"] = FieldValue.delete()
        }
        if companyStartTS > 0 {
            fields["companyStartDate"] = Timestamp(date: Date(timeIntervalSince1970: companyStartTS))
        } else {
            fields["companyStartDate"] = FieldValue.delete()
        }
        if shareHours, (!companyName.isEmpty || companyStartDate != nil) {
            fields["companyHoursLogged"] = companyHoursLogged
            fields["companyDaysWorked"] = companyDaysWorked
        } else {
            fields["companyHoursLogged"] = FieldValue.delete()
            fields["companyDaysWorked"] = FieldValue.delete()
        }
        if let profilePhotoURL {
            fields["profilePhotoURL"] = profilePhotoURL
        } else {
            fields["profilePhotoURL"] = FieldValue.delete()
        }
        if shareHours {
            fields["chequeDailySummary"] = chequeDailySummary.map {
                ["date": $0.date, "hours": $0.hours, "shifts": $0.shifts]
            }
            fields["chequeWindowStart"] = chequeWindowStart
            fields["chequeWindowCutoff"] = chequeWindowCutoff
        } else {
            fields["chequeDailySummary"] = FieldValue.delete()
            fields["chequeWindowStart"] = FieldValue.delete()
            fields["chequeWindowCutoff"] = FieldValue.delete()
        }
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
