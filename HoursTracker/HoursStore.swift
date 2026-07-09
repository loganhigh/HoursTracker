import Foundation
import Combine
import UIKit
import os

/// Progression anchors synced privately to Firestore for multi-device restore.
struct RemoteGamificationAnchors {
    let prestige: Int
    /// Highest prestige level ever confirmed via an explicit prestige action.
    /// Written separately and never overwritten by profile-snapshot logic, so
    /// it survives corruption that zeroes the main `prestige` field.
    let highWaterPrestige: Int
    let prestigeXPSnapshots: [Int]
    let prestigeHourSnapshots: [Double]
    let bestStreak: Int
    let streakFreezes: Int
    let equippedTitle: String?
    let updatedAt: Date?
    /// The `level` field stored on the cloud profile doc.  Used as a recovery
    /// hint when the public profile `level` is manually corrected in Firestore.
    /// The app can synthesize a snapshot that reproduces this level so the
    /// user's position within a prestige tier is restored after corruption.
    let storedLevel: Int
    /// Admin-only override written to `gamification/current` as `levelOverride`.
    /// Takes priority over `storedLevel` and is cleared from Firestore after
    /// it is applied once, so the field acts as a one-shot correction.
    let levelOverride: Int?
    /// Admin-only one-shot prestige set from `gamification/current.prestigeOverride`.
    let prestigeOverride: Int?
    /// Admin XP bonus synced from `gamification/current.adminXPOffset`.
    let adminXPOffset: Int?
    /// Deprecated — legacy floor field; no longer used for level display.
    let adminFloorLevel: Int?
    /// Admin-set prestige floor on the user doc (`adminFloorPrestige`). Never
    /// written by the client. Acts as a floor on displayed prestige.
    let adminFloorPrestige: Int?
    /// Persistent admin override for the badge title shown on profiles
    /// (`adminEquippedTitle`). Never written by the client.
    let adminEquippedTitle: String?
}

/// Single source of truth for work entries and pay settings.
/// - Date/Time: Uses the device's current date, time, and calendar (Date(), Calendar.current).
/// - Persistence: All data (entries, settings) is saved to UserDefaults and persists indefinitely
///   until the app is uninstalled. No automatic expiration or deletion.
final class HoursStore: ObservableObject {
    @Published var entries: [WorkEntry] = [] {
        didSet {
            weekEntriesCache = nil
            monthHoursCache = nil
        }
    }
    @Published var yearArchives: [YearArchive] = []
    @Published var paySettings: PaySettings = PaySettings()
    @Published var payHistoryEntries: [PayHistoryEntry] = []
    @Published var certificateEntries: [CertificateEntry] = []
    @Published var awardEntries: [AwardEntry] = []
    @Published var gamificationProfile: GamificationProfile = .defaultProfile
    @Published var gamificationEventMessage: String?
    @Published private(set) var isLoaded = false
    /// DEAD legacy admin floor (`adminFloorLevel`). No display or publish path
    /// reads it anymore — level has ONE canonical source: the server-computed
    /// `stats/lifetime.level` (see `displayedLevel`), with the XP-derived local
    /// level as the offline fallback. Kept only so `applyAdminLevel` can keep
    /// clearing stale persisted values on old installs.
    @Published var adminLevelOverride: Int? = nil
    /// DEAD legacy admin-prestige floor (`adminFloorPrestige`) — same story as
    /// `adminLevelOverride`.
    @Published var adminPrestigeOverride: Int? = nil
    /// Persistent admin title override from `adminEquippedTitle` on the user doc.
    var adminEquippedTitleOverride: String? = nil
    private var isLoading = false
    private var pendingLoadCompletions: [() -> Void] = []

    private let entriesKey = "hours_entries_v1"
    private let settingsKey = "pay_settings_v1"
    private let payHistoryKey = "pay_history_v1"
    private let certificatesKey = "certificate_entries_v2"
    private let awardsKey = "award_entries_v1"
    private let yearArchivesKey = "year_archives_v1"
    private let gamificationKey = "gamification_profile_v1"
    private let autoYearlyResetKey = "auto_yearly_reset_enabled"
    private let adminLevelOverrideKey = "admin_level_override_v1"
    private let adminPrestigeOverrideKey = "admin_prestige_override_v1"
    private let cloudSync = CloudSyncManager.shared
    private let networkMonitor = NetworkMonitor.shared

    init() {
        AppLogger.lifecycle.info("HoursStore init (main thread: \(Thread.isMainThread))")
        initializeYearlyResetDefaultIfNeeded()

        // *** Race-condition guard ***
        // The Firestore entries listener can fire (from cached data) before
        // loadAsync finishes reading UserDefaults on the background queue.
        // When applyRemoteEntries fires in that window, entries / yearArchives /
        // gamificationProfile are still at their default empty/zero values, which
        // causes totalHours and prestige to be written incorrectly to Firestore.
        // Pre-loading synchronously here is cheap and ensures correct data before
        // any listener callback can race with loadAsync.
        // Must match the .iso8601 strategy used by saveLocallyOnly / saveAsync.
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: entriesKey),
           let loadedEntries = try? dec.decode([WorkEntry].self, from: data) {
            entries = loadedEntries.sorted { $0.date > $1.date }
        }
        if let data = UserDefaults.standard.data(forKey: yearArchivesKey),
           let archives = try? dec.decode([YearArchive].self, from: data) {
            yearArchives = archives
        }
        if let data = UserDefaults.standard.data(forKey: gamificationKey),
           let profile = try? dec.decode(GamificationProfile.self, from: data) {
            gamificationProfile = profile
        }
        // NOTE: the legacy admin-level/prestige floor is deliberately NOT
        // restored from UserDefaults anymore. Nothing reads those overrides for
        // display or publishing — the server-computed level is the single
        // source of truth — so restoring them only kept conflicting state
        // alive. `applyAdminLevel`/`applyAdminPrestige` still clear any values
        // persisted by old builds.
    }

    /// Reload data from storage. Use for pull-to-refresh.
    func refresh(completion: (() -> Void)? = nil) {
        isLoaded = false
        isLoading = false
        pendingLoadCompletions.removeAll()
        loadAsync(completion: completion)
    }

    /// Async version for SwiftUI .refreshable.
    func refreshData() async {
        if cloudSync.isCloudAvailable {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                cloudSync.pullFromCloud { cont.resume() }
            }
        } else {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                refresh { cont.resume() }
            }
        }
    }

    /// Call to load data; completion invoked on main when ready. Safe to call multiple times.
    func ensureDataLoaded(completion: @escaping () -> Void) {
        if isLoaded {
            DispatchQueue.main.async { completion() }
            return
        }
        pendingLoadCompletions.append(completion)
        guard !isLoading else { return }
        isLoading = true
        loadAsync { [weak self] in
            guard let self else { return }
            self.isLoading = false
            let completions = self.pendingLoadCompletions
            self.pendingLoadCompletions = []
            completions.forEach { $0() }
        }
    }
    
    func configureCloudSync(authService: AuthService) {
        cloudSync.configure(authService: authService, store: self)
        setupCloudSync()
    }

    private func setupCloudSync() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.networkMonitor.isConnected,
               self.cloudSync.isCloudAvailable {
                // pullFromCloud merges entries first, then pushes an accurate profile
                // snapshot — avoids writing weeklyHours: 0 before cloud data arrives.
                self.cloudSync.pullFromCloud()
            } else {
                self.syncProfileSnapshotToCloud()
            }
        }
    }

    /// Merges Firestore entries into local data (keeps local-only shifts) and
    /// pushes an updated friends profile snapshot.
    ///
    /// `isAuthoritativeSnapshot` must only be true for a listener snapshot that
    /// came from the server with no pending local writes — it gates deletion-
    /// tombstone reconciliation (see below).
    func applyRemoteEntries(_ remoteEntries: [WorkEntry], isAuthoritativeSnapshot: Bool = false) {
        // Entries the user just deleted must stay gone even if a stale snapshot
        // (or an in-flight pull) still carries them. `pending_deletes` acts as a
        // tombstone set until the server confirms the removal.
        let tombstones = cloudSync.pendingDeletionIDs()

        // Drop tombstoned docs from the remote set so they can't be re-added,
        // and drop any locally-held copy so the row disappears immediately.
        let liveRemote = tombstones.isEmpty
            ? remoteEntries
            : remoteEntries.filter { !tombstones.contains($0.id.uuidString) }
        let remoteIDs = Set(liveRemote.map(\.id))

        var merged = tombstones.isEmpty
            ? entries
            : entries.filter { !tombstones.contains($0.id.uuidString) }
        // Index by id so each remote entry is an O(1) lookup instead of a linear
        // scan of `merged` — the previous `firstIndex(where:)` per remote made
        // this O(n·m) on every remote snapshot; it's now O(n+m).
        var indexByID = [UUID: Int](minimumCapacity: merged.count)
        for (i, entry) in merged.enumerated() { indexByID[entry.id] = i }
        for remote in liveRemote {
            if let idx = indexByID[remote.id] {
                merged[idx] = remote
            } else {
                indexByID[remote.id] = merged.count
                merged.append(remote)
            }
        }
        entries = merged.sorted { $0.date > $1.date }
        recalculateGamification(eventHint: nil)
        saveLocallyOnly()
        WidgetDataManager.shared.updateWidgetData(
            entries: entries,
            paySettings: paySettings,
            prestige: gamificationProfile.prestige
        )

        // Re-upload only genuinely local-only entries (offline-created) — never
        // tombstoned ones, which are already excluded from `merged`.
        let localOnly = merged.filter { !remoteIDs.contains($0.id) }
        for entry in localOnly {
            cloudSync.saveEntry(entry) { _ in }
        }

        // Clear tombstones the server has confirmed gone (absent from the raw
        // snapshot) — but ONLY from an authoritative snapshot. Firestore's
        // latency compensation removes a locally-deleted doc from cached
        // snapshots immediately, before the server ever hears about the delete;
        // treating that absence as "server confirmed" cleared the tombstone on
        // devices whose write channel hangs, so the server delete never
        // happened and the phantom doc inflated cloud totals forever.
        if isAuthoritativeSnapshot {
            cloudSync.reconcileTombstones(presentRemoteIDs: Set(remoteEntries.map { $0.id.uuidString }))
        }

        syncProfileSnapshotToCloud()
    }

    /// Applies pay settings from Firestore without triggering a cloud upload loop.
    func applyRemoteSettings(_ remoteSettings: PaySettings) {
        paySettings = remoteSettings
        normalizePaySettings()
        saveLocallyOnly()
        WidgetDataManager.shared.updateWidgetData(
            entries: entries,
            paySettings: paySettings,
            prestige: gamificationProfile.prestige
        )
    }

    /// Merges prestige / progression anchors pulled from the private
    /// `users/{uid}/gamification/current` doc so a second device (e.g. iPad)
    /// picks up the same prestige level as the user's phone.
    func applyRemoteGamificationAnchors(_ anchors: RemoteGamificationAnchors?) {
        guard let anchors else { return }

        let cloudPrestige = anchors.prestige
        let localPrestige = gamificationProfile.prestige
        let localSyncedAt = UserDefaults.standard.object(forKey: gamificationCloudSyncedAtKey) as? Date

        let shouldApplyCloud: Bool = {
            if cloudPrestige > localPrestige { return true }
            if cloudPrestige < localPrestige { return false }
            if let cloudUpdatedAt = anchors.updatedAt, let localSyncedAt {
                return cloudUpdatedAt > localSyncedAt
            }
            return cloudPrestige > 0 || !anchors.prestigeXPSnapshots.isEmpty
        }()
        let cloudTitle = anchors.equippedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard shouldApplyCloud else {
            // Even if we don't apply full anchors, always ratchet the floor up
            // to the cloud high-water mark so corrupted accounts self-heal.
            var didUpdate = false
            let hwm = anchors.highWaterPrestige
            if hwm > (gamificationProfile.prestigeFloor ?? 0) {
                gamificationProfile.prestigeFloor = hwm
                if hwm > gamificationProfile.prestige {
                    gamificationProfile.prestige = hwm
                }
                didUpdate = true
            }
            if let cloudTitle, !cloudTitle.isEmpty,
               cloudTitle != gamificationProfile.equippedTitle {
                gamificationProfile.equippedTitle = cloudTitle
                didUpdate = true
            }
            if let cloudOffset = anchors.adminXPOffset,
               cloudOffset != gamificationProfile.adminXPOffset {
                gamificationProfile.adminXPOffset = cloudOffset
                didUpdate = true
            }
            if didUpdate {
                recalculateGamification(eventHint: nil)
                saveLocallyOnly()
            }
            return
        }

        gamificationProfile.prestige = cloudPrestige
        gamificationProfile.prestigeFloor = max(gamificationProfile.prestigeFloor ?? 0, cloudPrestige, anchors.highWaterPrestige)
        if !anchors.prestigeXPSnapshots.isEmpty {
            gamificationProfile.prestigeXPSnapshots = anchors.prestigeXPSnapshots
        }
        if !anchors.prestigeHourSnapshots.isEmpty {
            gamificationProfile.prestigeHourSnapshots = anchors.prestigeHourSnapshots
        }
        if anchors.bestStreak > gamificationProfile.bestStreak {
            gamificationProfile.bestStreak = anchors.bestStreak
        }
        gamificationProfile.streakFreezes = max(gamificationProfile.streakFreezes, anchors.streakFreezes)
        if let cloudOffset = anchors.adminXPOffset, cloudOffset != gamificationProfile.adminXPOffset {
            gamificationProfile.adminXPOffset = cloudOffset
        }
        if let cloudTitle, !cloudTitle.isEmpty {
            gamificationProfile.equippedTitle = cloudTitle
        }
        if let cloudUpdatedAt = anchors.updatedAt {
            UserDefaults.standard.set(cloudUpdatedAt, forKey: gamificationCloudSyncedAtKey)
        }
        saveLocallyOnly()
    }

    private var gamificationCloudSyncedAtKey: String { "gamification_cloud_synced_at" }

    func markGamificationCloudSynced(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: gamificationCloudSyncedAtKey)
    }

    /// Persists to UserDefaults only — skips cloud push (used when applying remote data).
    private func saveLocallyOnly() {
        let entriesCopy = entries
        let settingsCopy = paySettings
        let payHistoryCopy = payHistoryEntries
        let yearArchivesCopy = yearArchives
        let gamificationCopy = gamificationProfile
        let entriesKey = self.entriesKey
        let settingsKey = self.settingsKey
        let payHistoryKey = self.payHistoryKey
        let yearArchivesKey = self.yearArchivesKey
        let gamificationKey = self.gamificationKey
        let prestigeCopy = gamificationCopy.prestige

        // PaySettings and GamificationProfile have main-actor-isolated Encodable
        // conformances, so they must be encoded on the main actor (they're tiny,
        // so the cost is negligible). The large entries/payHistory/yearArchives
        // arrays — the ones that made this a main-thread stall on every save for
        // a multi-year history — are encoded on the background queue below.
        let mainEnc = JSONEncoder()
        mainEnc.dateEncodingStrategy = .iso8601
        let settingsData: Data
        let gamificationData: Data
        do {
            settingsData = try mainEnc.encode(settingsCopy)
            gamificationData = try mainEnc.encode(gamificationCopy)
        } catch {
            AppLogger.db.error("saveLocallyOnly failed (settings/gamification): \(String(describing: error))")
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            let entriesData: Data
            let payHistoryData: Data
            let yearArchivesData: Data
            do {
                entriesData = try enc.encode(entriesCopy)
                payHistoryData = try enc.encode(payHistoryCopy)
                yearArchivesData = try enc.encode(yearArchivesCopy)
            } catch {
                AppLogger.db.error("saveLocallyOnly failed: \(String(describing: error))")
                return
            }
            UserDefaults.standard.set(entriesData, forKey: entriesKey)
            UserDefaults.standard.set(settingsData, forKey: settingsKey)
            UserDefaults.standard.set(payHistoryData, forKey: payHistoryKey)
            UserDefaults.standard.set(yearArchivesData, forKey: yearArchivesKey)
            UserDefaults.standard.set(gamificationData, forKey: gamificationKey)
            WidgetDataManager.shared.updateWidgetData(
                entries: entriesCopy,
                paySettings: settingsCopy,
                prestige: prestigeCopy
            )
        }
    }

    private var pendingProfileSyncWork: DispatchWorkItem?

    func syncProfileSnapshotToCloud() {
        guard cloudSync.isCloudAvailable else { return }
        pendingProfileSyncWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.ensureDataLoaded { [weak self] in
                guard let self else { return }
                if self.networkMonitor.isConnected,
                   !self.cloudSync.hasAppliedRemoteEntries {
                    return
                }
                self.recalculateGamification(eventHint: nil)
                self.cloudSync.saveProfileSnapshot(store: self)
            }
        }
        pendingProfileSyncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    /// Variant called by `pullFromCloud` after remote gamification anchors have
    /// been applied. Bypasses the `hasAppliedRemoteEntries` gate so the corrected
    /// prestige / level always gets written to Firestore even when the entries
    /// snapshot listener hasn't fired yet on this launch.
    func forceSyncProfileAfterPull() {
        guard cloudSync.isCloudAvailable else { return }
        ensureDataLoaded { [weak self] in
            guard let self else { return }
            self.recalculateGamification(eventHint: nil)
            self.cloudSync.saveProfileSnapshot(store: self)
        }
    }

    /// Level shown in UI — prefers server-computed level when available.
    var displayedLevel: Int {
        if FirebaseMigrationFlags.useServerStats,
           let serverLevel = StatsListenerService.shared.lifetimeStats?.level {
            return serverLevel
        }
        return gamificationProfile.level
    }

    /// Prestige shown in UI.
    var displayedPrestige: Int {
        gamificationProfile.prestige
    }

    /// Gamification snapshot for UI cards.
    func displayedGamificationProfile() -> GamificationProfile {
        var profile = gamificationProfile
        profile.prestige = displayedPrestige
        return profile
    }

    /// Applies a cloud-synced admin XP offset (multi-device / server admin set).
    func syncAdminXPOffsetFromCloud(_ offset: Int) {
        guard offset != gamificationProfile.adminXPOffset else { return }
        gamificationProfile.adminXPOffset = offset
        recalculateGamification(eventHint: nil)
        saveLocallyOnly()
    }

    /// Applies admin progression written remotely (admin panel / other device).
    ///
    /// Always ADOPTS the cloud values (prestige, snapshots, adminXPOffset)
    /// rather than re-deriving a local offset from levelOverride/prestigeOverride
    /// flags. The old re-derivation path computed a slightly different offset on
    /// every device (each against its own local XP), so devices never agreed and
    /// each listener fire re-snapped XP back to the target level — replaying
    /// level-ups endlessly. The server-computed offset is the single source of
    /// truth; local XP earned since simply stacks on top of it.
    func applyCloudGamificationProgression(_ anchors: RemoteGamificationAnchors) {
        var dirty = false
        if anchors.prestige != gamificationProfile.prestige {
            gamificationProfile.prestige = anchors.prestige
            gamificationProfile.prestigeFloor = max(
                gamificationProfile.prestigeFloor ?? 0,
                anchors.prestige,
                anchors.highWaterPrestige
            )
            dirty = true
        }
        if !anchors.prestigeXPSnapshots.isEmpty,
           anchors.prestigeXPSnapshots != gamificationProfile.prestigeXPSnapshots {
            gamificationProfile.prestigeXPSnapshots = anchors.prestigeXPSnapshots
            dirty = true
        }
        if let cloudOffset = anchors.adminXPOffset,
           cloudOffset != gamificationProfile.adminXPOffset {
            gamificationProfile.adminXPOffset = cloudOffset
            dirty = true
        }
        guard dirty else { return }
        recalculateGamification(eventHint: nil)
        saveLocallyOnly()
    }

    /// Deprecated — legacy admin floors; no longer clears progression sets.
    func applyAdminLevel(_ adminLevel: Int?) {
        adminLevelOverride = nil
        UserDefaults.standard.removeObject(forKey: adminLevelOverrideKey)
    }

    /// Deprecated — legacy admin floors; no longer clears progression sets.
    func applyAdminPrestige(_ adminPrestige: Int?) {
        adminPrestigeOverride = nil
        UserDefaults.standard.removeObject(forKey: adminPrestigeOverrideKey)
    }

    /// Stores the admin title override so profile sync re-publishes it.
    func applyAdminEquippedTitle(_ title: String?) {
        guard let title else {
            adminEquippedTitleOverride = nil
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        adminEquippedTitleOverride = trimmed.isEmpty ? nil : trimmed
    }

    /// Title shown on profile cards — admin override wins when set.
    var displayedEquippedTitle: String {
        if let admin = adminEquippedTitleOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !admin.isEmpty {
            return admin
        }
        return gamificationProfile.equippedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Per-component XP breakdown for the server's XP-migration shadow logs.
    /// See GamificationEngine.xpComponentBreakdown.
    func xpComponentBreakdown() -> [String: Int] {
        GamificationEngine.xpComponentBreakdown(
            activeEntries: entries,
            archivedEntries: yearArchives.flatMap(\.entries),
            adminXPOffset: gamificationProfile.adminXPOffset,
            overtimeHours: { [weak self] entry in
                self?.payBreakdown(for: entry).overtimeHours ?? 0
            }
        )
    }

    /// Call when the user opens the app or completes sign-in so friends/leaderboard
    /// fields (level, prestige, streaks) are pushed to Firestore promptly.
    func syncProfileOnLogin() {
        syncProfileSnapshotToCloud()
    }

    /// Paid hours across active + archived entries — used for cloud profile snapshots.
    func totalPaidWorkHours() -> Double {
        let all = entries + yearArchives.flatMap(\.entries)
        return all.filter { !$0.isOffDay }.reduce(0.0) { $0 + $1.paidHours }
    }

    /// Best available paid-hours total for profile publishing. This intentionally
    /// compares the current in-memory store with the persisted UserDefaults copy
    /// because Firestore listeners can temporarily replace `entries` before the
    /// full local load has finished.
    func bestAvailablePaidWorkHours() -> Double {
        max(totalPaidWorkHours(), persistedPaidWorkHours())
    }

    private func persistedPaidWorkHours() -> Double {
        persistedEntriesIncludingArchive()
            .filter { !$0.isOffDay }
            .reduce(0.0) { $0 + $1.paidHours }
    }

    private func persistedEntriesIncludingArchive() -> [WorkEntry] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let persistedEntries: [WorkEntry] = {
            guard let data = UserDefaults.standard.data(forKey: entriesKey),
                  let entries = try? dec.decode([WorkEntry].self, from: data) else {
                return []
            }
            return entries
        }()
        let persistedArchives: [YearArchive] = {
            guard let data = UserDefaults.standard.data(forKey: yearArchivesKey),
                  let archives = try? dec.decode([YearArchive].self, from: data) else {
                return []
            }
            return archives
        }()
        var seen = Set<UUID>()
        return (persistedEntries + persistedArchives.flatMap(\.entries))
            .filter { seen.insert($0.id).inserted }
    }

    // MARK: - CRUD

    func add(_ entry: WorkEntry) {
        // Prevent duplicate entries
        guard !entries.contains(where: { $0.id == entry.id }) else {
            #if DEBUG
            print("Prevented duplicate entry with ID: \(entry.id)")
            #endif
            return
        }

        let previousProfile = gamificationProfile
        let previousMonthHours = monthTotalHours(monthDate: entry.date)

        entries.append(entry)
        recalculateGamification(eventHint: "Shift logged")
        if FirebaseMigrationFlags.emitClientActivityEvents {
            emitActivityEvents(
                previous: previousProfile,
                previousMonthHours: previousMonthHours,
                newEntry: entry
            )
        }
        save(syncProfile: false)
        WeeklyMilestoneNotifier.shared.checkMilestones(for: entries)
        SmartNotifier.shared.checkPayPeriodProgress(for: entries, paySettings: paySettings)
        SmartNotifier.shared.cancelDailyReminderIfNeeded(for: entry.date, entries: entries)
        SmartNotifier.shared.cancelForgotHoursReminderIfNeeded(for: entry.date, entries: entries)
        SmartNotifier.shared.scheduleMotivationReminderIfNeeded(entries: entries)
        SmartNotifier.shared.scheduleStreakNotificationsIfNeeded(entries: entries, currentStreak: gamificationProfile.currentStreak)
        
        // Sync to cloud (handles offline automatically)
        cloudSync.saveEntry(entry) { result in
            if case .failure(let error) = result {
                #if DEBUG
                print("Cloud sync error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func update(_ entry: WorkEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
        recalculateGamification(eventHint: "Shift updated")
        save(syncProfile: false)
        WeeklyMilestoneNotifier.shared.checkMilestones(for: entries)
        SmartNotifier.shared.checkPayPeriodProgress(for: entries, paySettings: paySettings)
        SmartNotifier.shared.cancelDailyReminderIfNeeded(for: entry.date, entries: entries)
        SmartNotifier.shared.cancelForgotHoursReminderIfNeeded(for: entry.date, entries: entries)
        SmartNotifier.shared.scheduleMotivationReminderIfNeeded(entries: entries)
        SmartNotifier.shared.scheduleStreakNotificationsIfNeeded(entries: entries, currentStreak: gamificationProfile.currentStreak)
        
        // Sync to cloud
        cloudSync.saveEntry(entry) { result in
            if case .failure(let error) = result {
                #if DEBUG
                print("Cloud sync error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func delete(_ entry: WorkEntry) {
        entries.removeAll { $0.id == entry.id }
        recalculateGamification(eventHint: "Shift removed")
        save(syncProfile: false)
        WeeklyMilestoneNotifier.shared.checkMilestones(for: entries)
        
        cloudSync.deleteEntry(entry) { _ in }
    }

    func deleteEntries(inMonth monthDate: Date) {
        let monthEntries = entries(inMonth: monthDate)
        let ids = Set(monthEntries.map(\.id))
        entries.removeAll { ids.contains($0.id) }
        recalculateGamification(eventHint: "Month entries removed")
        save(syncProfile: false)
        WeeklyMilestoneNotifier.shared.checkMilestones(for: entries)
        // Tombstone + push each cloud deletion — without this the cloud docs
        // survived a month wipe and kept inflating server totals forever.
        for entry in monthEntries {
            cloudSync.deleteEntry(entry) { _ in }
        }
    }
    
    // MARK: - Cloud Sync
    func syncToCloud(completion: ((Result<Void, Error>) -> Void)? = nil) {
        cloudSync.syncAll(entries: entries, settings: paySettings) { result in
            switch result {
            case .success:
                #if DEBUG
                print("Sync successful")
                #endif
            case .failure(let error):
                #if DEBUG
                print("Sync failed: \(error.localizedDescription)")
                #endif
            }
            completion?(result)
        }
    }
    
    func fetchFromCloud(completion: @escaping (Bool) -> Void) {
        cloudSync.fetchEntries { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let cloudEntries):
                // Merge with local entries (cloud takes precedence for conflicts)
                self.mergeEntries(cloudEntries)
                completion(true)
            case .failure:
                completion(false)
            }
        }
    }
    
    private func mergeEntries(_ cloudEntries: [WorkEntry]) {
        // Simple merge: cloud entries take precedence
        var merged = entries
        
        for cloudEntry in cloudEntries {
            if let index = merged.firstIndex(where: { $0.id == cloudEntry.id }) {
                merged[index] = cloudEntry
            } else {
                merged.append(cloudEntry)
            }
        }
        
        entries = merged.sorted { $0.date > $1.date }
        save()
    }
    
    func deleteAllData() {
        entries.removeAll()
        yearArchives.removeAll()
        paySettings = PaySettings()
        payHistoryEntries.removeAll()
        certificateEntries.removeAll()
        awardEntries.removeAll()
        gamificationProfile = .defaultProfile
        gamificationEventMessage = nil
        isLoaded = false
        UserDefaults.standard.removeObject(forKey: entriesKey)
        UserDefaults.standard.removeObject(forKey: settingsKey)
        UserDefaults.standard.removeObject(forKey: payHistoryKey)
        UserDefaults.standard.removeObject(forKey: certificatesKey)
        UserDefaults.standard.removeObject(forKey: awardsKey)
        UserDefaults.standard.removeObject(forKey: yearArchivesKey)
        UserDefaults.standard.removeObject(forKey: gamificationKey)
        if let dir = certificatesDirectoryURL() {
            try? FileManager.default.removeItem(at: dir)
        }
        if let dir = awardsDirectoryURL() {
            try? FileManager.default.removeItem(at: dir)
        }
        if let backupURL = try? LocalBackupService.backupFileURL() {
            try? FileManager.default.removeItem(at: backupURL)
        }
    }

    // MARK: - Certificates (training certificate photos)
    private static let certificatesFolderName = "certificates"
    private static let awardsFolderName = "awards"

    func certificatesDirectoryURL() -> URL? {
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(HoursStore.certificatesFolderName, isDirectory: true)
    }

    func certificateFileURL(for filename: String) -> URL? {
        certificatesDirectoryURL()?.appendingPathComponent(filename)
    }

    func awardsDirectoryURL() -> URL? {
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(HoursStore.awardsFolderName, isDirectory: true)
    }

    func awardFileURL(for filename: String) -> URL? {
        awardsDirectoryURL()?.appendingPathComponent(filename)
    }

    func addCertificate(imageData: Data, label: String = "") {
        guard let dir = certificatesDirectoryURL() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).jpg"
        let url = dir.appendingPathComponent(filename)
        do {
            try imageData.write(to: url)
            certificateEntries.append(CertificateEntry(filename: filename, label: label))
            saveCertificates()
        } catch { }
    }

    func updateCertificateLabel(id: UUID, label: String) {
        guard let idx = certificateEntries.firstIndex(where: { $0.id == id }) else { return }
        certificateEntries[idx].label = label
        saveCertificates()
    }

    func deleteCertificate(entry: CertificateEntry) {
        certificateEntries.removeAll { $0.id == entry.id }
        if let url = certificateFileURL(for: entry.filename) {
            try? FileManager.default.removeItem(at: url)
        }
        saveCertificates()
    }

    private func saveCertificates() {
        guard let data = try? JSONEncoder().encode(certificateEntries) else { return }
        UserDefaults.standard.set(data, forKey: certificatesKey)
    }

    private func loadCertificates() {
        guard let data = UserDefaults.standard.data(forKey: certificatesKey) else { return }
        let dec = JSONDecoder()
        if let entries = try? dec.decode([CertificateEntry].self, from: data) {
            certificateEntries = entries
            return
        }
        if let legacy = try? dec.decode([String].self, from: data) {
            certificateEntries = legacy.map { CertificateEntry(filename: $0, label: "") }
        }
    }

    // MARK: - Awards (job awards photos)
    func addAward(imageData: Data, label: String = "") {
        guard let dir = awardsDirectoryURL() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).jpg"
        let url = dir.appendingPathComponent(filename)
        do {
            try imageData.write(to: url)
            awardEntries.append(AwardEntry(filename: filename, label: label))
            saveAwards()
        } catch { }
    }

    func updateAwardLabel(id: UUID, label: String) {
        guard let idx = awardEntries.firstIndex(where: { $0.id == id }) else { return }
        awardEntries[idx].label = label
        saveAwards()
    }

    func deleteAward(entry: AwardEntry) {
        awardEntries.removeAll { $0.id == entry.id }
        if let url = awardFileURL(for: entry.filename) {
            try? FileManager.default.removeItem(at: url)
        }
        saveAwards()
    }

    private func saveAwards() {
        guard let data = try? JSONEncoder().encode(awardEntries) else { return }
        UserDefaults.standard.set(data, forKey: awardsKey)
    }

    // MARK: - Pay history (promotions / raises)

    func addPayHistoryEntry(_ entry: PayHistoryEntry) {
        payHistoryEntries.append(entry)
        payHistoryEntries.sort { $0.year < $1.year }
        save()
    }

    func updatePayHistoryEntry(_ entry: PayHistoryEntry) {
        guard let idx = payHistoryEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        payHistoryEntries[idx] = entry
        payHistoryEntries.sort { $0.year < $1.year }
        save()
    }

    func deletePayHistoryEntry(_ entry: PayHistoryEntry) {
        payHistoryEntries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: - Filtering helpers

    func allEntriesIncludingArchive() -> [WorkEntry] {
        let archived = yearArchives.flatMap(\.entries)
        var merged = archived + entries
        var seen = Set<UUID>()
        merged = merged.filter { seen.insert($0.id).inserted }
        return merged.sorted { $0.date > $1.date }
    }

    func entries(inMonth monthDate: Date) -> [WorkEntry] {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return [] }
        return entries.filter { $0.date >= start && $0.date < end }
    }

    // Memoized month → total-paid-hours, invalidated whenever `entries` changes
    // (see the didSet on `entries`). The dashboard renders a 12-month chart and a
    // best-month scan that previously called this once per month on every body
    // evaluation — each an O(n) filter over all entries — so it re-scanned full
    // history dozens of times per render, including during confetti/XP animations.
    // Caching by month-start makes repeat renders O(1) lookups.
    private var monthHoursCache: [Date: Double]?

    func monthTotalHours(monthDate: Date) -> Double {
        let cal = Calendar.current
        guard let key = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)) else {
            return entries(inMonth: monthDate).reduce(0) { $0 + $1.paidHours }
        }
        if let cached = monthHoursCache?[key] { return cached }
        let value = entries(inMonth: monthDate).reduce(0) { $0 + $1.paidHours }
        var cache = monthHoursCache ?? [:]
        cache[key] = value
        monthHoursCache = cache
        return value
    }

    func monthEstimatedPay(monthDate: Date) -> Double {
        entries(inMonth: monthDate).reduce(0) { $0 + payBreakdown(for: $1).pay }
    }
    
    func monthRegularHours(monthDate: Date) -> Double {
        entries(inMonth: monthDate).reduce(0) { $0 + payBreakdown(for: $1).regularHours }
    }

    func monthOvertimeHours(monthDate: Date) -> Double {
        let monthEntries = entries(inMonth: monthDate)
        return monthEntries.reduce(0) { $0 + payBreakdown(for: $1).overtimeHours }
    }

    func monthOvertimeHoursAt1_5(monthDate: Date) -> Double {
        entries(inMonth: monthDate).reduce(0) { $0 + payBreakdown(for: $1).overtimeHoursAt1_5 }
    }

    func monthOvertimeHoursAt2_0(monthDate: Date) -> Double {
        entries(inMonth: monthDate).reduce(0) { $0 + payBreakdown(for: $1).overtimeHoursAt2_0 }
    }
    
    func monthEffectiveRate(monthDate: Date) -> Double {
        let totalHours = monthTotalHours(monthDate: monthDate)
        guard totalHours > 0 else { return 0 }
        let totalPay = monthEstimatedPay(monthDate: monthDate)
        return totalPay / totalHours
    }
    
    // MARK: - Streak Calculation
    
    /// Returns the current active work streak (consecutive days worked ending at the most recent work day).
    /// Only counts actually-worked days (off-days are excluded), spans the year
    /// archive so the streak survives the Jan-1 rollover, and reports 0 unless the
    /// most recent worked day is today or yesterday — otherwise a long-idle user
    /// would keep seeing a stale streak that can never decay.
    func currentWorkStreak() -> Int {
        let cal = Calendar.current
        let workDates = Set(
            allEntriesIncludingArchive()
                .filter { !$0.isOffDay }
                .map { cal.startOfDay(for: $0.date) }
        ).sorted(by: >)

        guard let mostRecent = workDates.first else { return 0 }

        let today = cal.startOfDay(for: Date())
        let daysSinceLastWork = cal.dateComponents([.day], from: mostRecent, to: today).day ?? 99
        guard daysSinceLastWork <= 1 else { return 0 }

        var streak = 1
        var currentDate = mostRecent

        for i in 1..<workDates.count {
            let previousDate = workDates[i]
            let daysDiff = cal.dateComponents([.day], from: previousDate, to: currentDate).day ?? 0
            
            if daysDiff == 1 {
                streak += 1
                currentDate = previousDate
            } else {
                break
            }
        }
        
        return streak
    }

    // MARK: - Gamification

    func consumeStreakFreezeIfNeeded() -> Bool {
        guard gamificationProfile.streakFreezes > 0 else { return false }
        gamificationProfile.streakFreezes -= 1
        gamificationEventMessage = "Streak Freeze used. Streak protected."
        save()
        return true
    }

    func performPrestige() -> Bool {
        guard gamificationProfile.canPrestige else { return false }
        guard gamificationProfile.prestige < 10 else { return false }

        // Recalculate first so snapshots match the current entry-derived totals.
        recalculateGamification(eventHint: nil)
        guard gamificationProfile.canPrestige else { return false }

        let hours = totalPaidWorkHours()
        gamificationProfile.prestigeXPSnapshots.append(gamificationProfile.totalXP)
        gamificationProfile.prestigeHourSnapshots.append(hours)
        gamificationProfile.prestige += 1
        // Advance the floor to match the new prestige level.
        gamificationProfile.prestigeFloor = max(gamificationProfile.prestigeFloor ?? 0, gamificationProfile.prestige)
        recalculateGamification(eventHint: nil)
        gamificationEventMessage = "Prestige \(gamificationProfile.prestige) unlocked."
        save()
        syncProfileSnapshotToCloud()
        // Write highWaterPrestige to a dedicated Firestore field that profile-snapshot
        // logic never touches. This is the recovery source for corrupted accounts.
        cloudSync.recordHighWaterPrestige(gamificationProfile.prestige)
        return true
    }

    // MARK: - Activity feed emission

    /// Decides which (if any) `ActivityFeedService` events should fire after a
    /// new entry has been added and gamification has recalculated. Compares the
    /// previous gamification snapshot against the freshly built one so we only
    /// emit "milestone hit" / "badge unlocked" events on the actual transition.
    /// Off-day entries are silenced — no friend wants a feed full of "Logan
    /// took a day off" pings.
    private func emitActivityEvents(
        previous: GamificationProfile,
        previousMonthHours: Double,
        newEntry: WorkEntry
    ) {
        let feed = ActivityFeedService.shared
        let current = gamificationProfile

        // Shift-logged ping — only for real work entries, only when the entry
        // is recent enough to be socially relevant (today or yesterday). Older
        // backfills don't need to fan out to friends' feeds.
        if !newEntry.isOffDay,
           Calendar.current.dateComponents([.day], from: newEntry.date, to: Date()).day ?? 99 <= 1,
           newEntry.paidHours > 0 {
            let hoursStr = AppTheme.Format.hours(newEntry.paidHours)
            let body: String
            if Calendar.current.isDateInToday(newEntry.date) {
                body = "worked \(hoursStr) today"
            } else if Calendar.current.isDateInYesterday(newEntry.date) {
                body = "worked \(hoursStr) yesterday"
            } else {
                body = "logged a \(hoursStr) shift"
            }
            feed.publish(
                kind: .shiftLogged,
                body: body,
                metric: newEntry.paidHours,
                documentId: "shift_\(newEntry.id.uuidString)"
            )
        }

        // Newly unlocked badges (set diff against previous snapshot).
        let newBadges = Set(current.unlockedBadges).subtracting(previous.unlockedBadges)
        for badge in newBadges {
            // Use the friendliest available label — title for badges that map
            // to an unlockable title, else the badge id (still readable).
            let label = current.unlockedTitles.first { $0.localizedCaseInsensitiveContains(badge) }
                ?? badge.replacingOccurrences(of: "_", with: " ").capitalized
            feed.publish(kind: .badgeUnlocked, body: "unlocked \(label)")
        }

        // Streak milestones — emit when crossing a notable bucket.
        let streakBuckets = [5, 10, 14, 21, 30, 50, 75, 100]
        if let crossed = streakBuckets.first(where: { previous.currentStreak < $0 && current.currentStreak >= $0 }) {
            feed.publish(kind: .streakMilestone, body: "hit a \(crossed)-day streak", metric: Double(crossed))
        }

        // Monthly milestones — emit when this month's total crosses a bucket.
        let monthHours = monthTotalHours(monthDate: newEntry.date)
        let monthBuckets: [Double] = [50, 100, 150, 200, 250, 300]
        if let crossed = monthBuckets.first(where: { previousMonthHours < $0 && monthHours >= $0 }) {
            let df = DateFormatter()
            df.dateFormat = "MMMM"
            let monthName = df.string(from: newEntry.date)
            feed.publish(
                kind: .monthlyMilestone,
                body: "hit \(Int(crossed))h in \(monthName)",
                metric: crossed
            )
        }

        // Prestige promotion — recalc may bump prestige (rare; usually only
        // via performPrestige but we cover both paths).
        if current.prestige > previous.prestige {
            feed.publish(kind: .prestige, body: "reached Prestige \(current.prestige)", metric: Double(current.prestige))
        }
    }

    private func recalculateGamification(eventHint: String?) {
        let previous = gamificationProfile
        gamificationProfile = GamificationEngine.buildProfile(
            previous: previous,
            activeEntries: entries,
            archivedEntries: yearArchives.flatMap(\.entries),
            overtimeHours: { [weak self] entry in
                self?.payBreakdown(for: entry).overtimeHours ?? 0
            }
        )

        if let event = GamificationEngine.eventMessage(previous: previous, current: gamificationProfile, hint: eventHint) {
            gamificationEventMessage = event
        }
    }

    // MARK: - Pay

    struct PayBreakdown {
        enum DayType { case weekday, saturday, sunday }
        let dayType: DayType
        let rawHours: Double
        let regularHours: Double
        let overtimeHoursAt1_5: Double
        let overtimeHoursAt2_0: Double
        /// Sum of overtimeHoursAt1_5 + overtimeHoursAt2_0 (for backward compatibility).
        var overtimeHours: Double { overtimeHoursAt1_5 + overtimeHoursAt2_0 }
        let multiplierUsed: Double
        let pay: Double
    }

    /// Week = Monday–Sunday. Returns start-of-week (Monday 00:00) for the given date.
    private func weekStart(for date: Date, calendar: Calendar) -> Date? {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        return cal.dateInterval(of: .weekOfYear, for: date)?.start
    }

    /// Returns all non-off-day entries in the same Mon–Sun week as `date`, sorted oldest-first.
    /// Memoized week buckets (week-start → that week's non-off-day entries,
    /// ascending). Invalidated whenever `entries` changes (see the didSet on
    /// `entries`). Building this once per entries-generation turns the weekly
    /// overtime pay path from O(n²) — `weekEntries(for:)` previously re-filtered
    /// the entire entries array on every call, and it's called once per entry
    /// from `payBreakdown`, itself called per entry on every render and every
    /// add/update — into O(n).
    private var weekEntriesCache: [Date: [WorkEntry]]?

    private func weekEntries(for date: Date) -> [WorkEntry] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        guard let ws = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        if let cache = weekEntriesCache {
            return cache[ws] ?? []
        }
        var buckets: [Date: [WorkEntry]] = [:]
        var c = Calendar.current
        c.firstWeekday = 2
        for entry in entries where !entry.isOffDay {
            guard let start = c.dateInterval(of: .weekOfYear, for: entry.date)?.start else { continue }
            buckets[start, default: []].append(entry)
        }
        for key in buckets.keys {
            buckets[key]?.sort { $0.date < $1.date }
        }
        weekEntriesCache = buckets
        return buckets[ws] ?? []
    }

    func payBreakdown(for entry: WorkEntry) -> PayBreakdown {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: entry.date) // 1=Sun, 7=Sat
        let raw = entry.paidHours
        let wage = paySettings.hourlyWage
        let sat = paySettings.saturdayOvertimeAfterHours
        let satMult = paySettings.saturdayMultiplier
        let sunMult = paySettings.sundayMultiplier
        let wdAfter = paySettings.weekdayOvertimeAfterHours
        let wdMult = paySettings.weekdayOvertimeMultiplier
        let weeklyThreshold = paySettings.weeklyOvertimeThreshold

        let effectiveWage: Double = (paySettings.holidayPayEnabled && entry.isHoliday)
            ? wage * paySettings.holidayPayMultiplier
            : wage

        let b: OvertimeRules.Breakout
        let dayType: PayBreakdown.DayType
        let mult: Double

        // Saturday and Sunday always use their own per-day rules regardless of overtimeType.
        if weekday == 7 || weekday == 1 {
            b = OvertimeRules.breakdown(
                weekday: weekday,
                rawHours: raw,
                wage: effectiveWage,
                saturdayThreshold: sat,
                saturdayMultiplier: satMult,
                sundayMultiplier: sunMult,
                weekdayOTAfterHours: wdAfter,
                weekdayOTMultiplier: wdMult
            )
            if weekday == 7 {
                dayType = .saturday
                mult = b.overtimeHoursAt1_5 > 0 ? satMult : 1.0
            } else {
                dayType = .sunday
                mult = sunMult
            }
        } else {
            // Weekday: route through the appropriate OT type
            switch paySettings.overtimeType {

            case .daily:
                b = OvertimeRules.breakdown(
                    weekday: weekday,
                    rawHours: raw,
                    wage: effectiveWage,
                    saturdayThreshold: sat,
                    saturdayMultiplier: satMult,
                    sundayMultiplier: sunMult,
                    weekdayOTAfterHours: wdAfter,
                    weekdayOTMultiplier: wdMult
                )
                dayType = .weekday
                mult = b.overtimeHoursAt1_5 > 0 ? wdMult : 1.0

            case .weekly:
                let we = weekEntries(for: entry.date)
                let (reg, ot) = OvertimeRules.weeklyBreakdown(entry: entry, weekEntries: we, weeklyCap: weeklyThreshold)
                b = OvertimeRules.Breakout(
                    regularHours: reg,
                    overtimeHoursAt1_5: ot,
                    overtimeHoursAt2_0: 0,
                    pay: reg * effectiveWage + ot * effectiveWage * wdMult
                )
                dayType = .weekday
                mult = ot > 0 ? wdMult : 1.0

            case .dailyAndWeekly:
                let we = weekEntries(for: entry.date)
                let (regH, dailyOT, weeklyOT) = OvertimeRules.dailyAndWeeklyBreakdown(
                    entry: entry,
                    weekEntries: we,
                    dailyThreshold: wdAfter,
                    weeklyCap: weeklyThreshold
                )
                let totalOT = dailyOT + weeklyOT
                let pay = regH * effectiveWage + totalOT * effectiveWage * wdMult
                b = OvertimeRules.Breakout(regularHours: regH, overtimeHoursAt1_5: totalOT, overtimeHoursAt2_0: 0, pay: pay)
                dayType = .weekday
                mult = totalOT > 0 ? wdMult : 1.0
            }
        }

        var totalPay = b.pay
        if paySettings.vacationPayEnabled {
            totalPay += b.pay * (paySettings.vacationPayPercentage / 100.0)
        }

        return PayBreakdown(
            dayType: dayType,
            rawHours: raw,
            regularHours: b.regularHours,
            overtimeHoursAt1_5: b.overtimeHoursAt1_5,
            overtimeHoursAt2_0: b.overtimeHoursAt2_0,
            multiplierUsed: mult,
            pay: totalPay
        )
    }

    // MARK: - Persistence

    /// Persist entries and settings to disk. Call when settings change (e.g. nextPayday in Settings/Onboarding).
    func persist() {
        save()
    }

    // MARK: - Local backup (device only)

    var hasLocalBackup: Bool {
        LocalBackupService.backupExists()
    }

    func lastLocalBackupDate() -> Date? {
        LocalBackupService.lastBackupDate()
    }

    /// Saves a full snapshot to Application Support. Overwrites the previous backup.
    func createLocalBackup() throws {
        let snapshot = try LocalBackupService.makeBackup(from: self)
        try LocalBackupService.writeBackup(snapshot)
    }

    /// Merges the last backup into current data without duplicates.
    /// Entries/archives from backup are added only if their ID doesn't already exist.
    /// Settings, pay history, certificates, and awards are merged the same way.
    /// Gamification profile is kept as-is (never roll back XP or level).
    func restoreFromLocalBackup() throws {
        let backup = try LocalBackupService.readBackup()

        // --- Entries: union by ID, current entries take precedence ---
        let existingIDs = Set(entries.map(\.id))
        let newEntries = backup.entries.filter { !existingIDs.contains($0.id) }
        entries = (entries + newEntries).sorted { $0.date > $1.date }

        // --- Year archives: merge each year's entries by ID ---
        var archiveByYear: [Int: [WorkEntry]] = [:]
        for archive in yearArchives {
            archiveByYear[archive.year, default: []].append(contentsOf: archive.entries)
        }
        for archive in backup.yearArchives {
            var existing = archiveByYear[archive.year] ?? []
            let existingArchiveIDs = Set(existing.map(\.id))
            let added = archive.entries.filter { !existingArchiveIDs.contains($0.id) }
            existing.append(contentsOf: added)
            archiveByYear[archive.year] = existing
        }
        yearArchives = archiveByYear.keys.sorted().map { YearArchive(year: $0, entries: archiveByYear[$0]!) }

        // --- Pay history: add entries not already present ---
        let existingPayIDs = Set(payHistoryEntries.map(\.id))
        let newPayHistory = backup.payHistoryEntries.filter { !existingPayIDs.contains($0.id) }
        payHistoryEntries = (payHistoryEntries + newPayHistory).sorted { $0.year < $1.year }

        // --- Certificates: restore any whose file isn't already on disk ---
        if let dir = certificatesDirectoryURL() {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, data) in backup.certificateFiles {
                let url = dir.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try? data.write(to: url, options: [.atomic])
                }
            }
        }
        let existingCertFilenames = Set(certificateEntries.map(\.filename))
        let newCerts = backup.certificateEntries.filter { !existingCertFilenames.contains($0.filename) }
        certificateEntries.append(contentsOf: newCerts)

        // --- Awards: same merge as certificates ---
        if let dir = awardsDirectoryURL() {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, data) in backup.awardFiles {
                let url = dir.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try? data.write(to: url, options: [.atomic])
                }
            }
        }
        let existingAwardFilenames = Set(awardEntries.map(\.filename))
        let newAwards = backup.awardEntries.filter { !existingAwardFilenames.contains($0.filename) }
        awardEntries.append(contentsOf: newAwards)

        saveCertificates()
        saveAwards()
        save()
    }

    /// Advances nextPayday (and nextCutoff when set) while they're in the past.
    /// Call on app/dashboard load.
    func advanceNextPaydayIfNeeded() {
        guard let payday = paySettings.nextPayday else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var current = cal.startOfDay(for: payday)
        let step = PayCycleEngine.spanDays(for: paySettings.payPeriodType)
        var advances = 0
        // Advance while nextPayday is on or before today: the cycle engine already
        // rolls over to the new period the moment today == payday, so nextPayday
        // must also move forward on payday day itself to stay in sync.
        while current <= today {
            guard let next = cal.date(byAdding: .day, value: step, to: current) else { break }
            current = next
            advances += 1
        }
        guard advances > 0, current != cal.startOfDay(for: payday) else { return }

        paySettings.nextPayday = current

        if PayCycleEngine.usesSavedCutoff(paySettings), let cutoff = paySettings.nextCutoff {
            var currentCutoff = cal.startOfDay(for: cutoff)
            for _ in 0..<advances {
                guard let next = cal.date(byAdding: .day, value: step, to: currentCutoff) else { break }
                currentCutoff = next
            }
            paySettings.nextCutoff = currentCutoff
        }

        save()
    }

    /// Marks past usual work days without a log as off days (forgotten shifts).
    func applyAutoOffDaysForForgottenShifts(now: Date = Date()) {
        guard isLoaded else { return }

        let newEntries = AutoOffDayFiller.makeOffDayEntries(entries: entries, now: now)
        guard !newEntries.isEmpty else { return }

        let cal = Calendar.current
        let toAdd = newEntries.filter { entry in
            !entries.contains(where: { cal.isDate($0.date, inSameDayAs: entry.date) })
        }
        guard !toAdd.isEmpty else { return }

        entries.append(contentsOf: toAdd)
        entries.sort { $0.date > $1.date }

        recalculateGamification(eventHint: nil)
        save(syncProfile: false)
        WeeklyMilestoneNotifier.shared.checkMilestones(for: entries)
        SmartNotifier.shared.scheduleForgotHoursReminderIfNeeded(entries: entries)
        SmartNotifier.shared.scheduleStreakNotificationsIfNeeded(
            entries: entries,
            currentStreak: gamificationProfile.currentStreak
        )
        WidgetDataManager.shared.updateWidgetData(
            entries: entries,
            paySettings: paySettings,
            prestige: gamificationProfile.prestige
        )

        for entry in toAdd {
            cloudSync.saveEntry(entry) { _ in }
        }
        syncProfileSnapshotToCloud()
    }

    /// Cutoff only applies when enabled and a date is saved.
    private func normalizePaySettings() {
        let cal = Calendar.current
        let minReasonableDate = cal.date(from: DateComponents(year: 2020, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
        let maxReasonableDate = cal.date(byAdding: .year, value: 5, to: Date()) ?? Date().addingTimeInterval(5 * 365 * 24 * 60 * 60)

        func isReasonablePayBoundary(_ date: Date?) -> Bool {
            guard let date else { return true }
            return date >= minReasonableDate && date <= maxReasonableDate
        }

        if !isReasonablePayBoundary(paySettings.nextPayday) {
            paySettings.nextPayday = nil
        }
        if !isReasonablePayBoundary(paySettings.nextCutoff) {
            paySettings.nextCutoff = nil
            paySettings.payPeriodUsesCutoff = false
        }
        if paySettings.payPeriodUsesCutoff && paySettings.nextCutoff == nil {
            paySettings.payPeriodUsesCutoff = false
        }
        // Migrate legacy weeklyOvertimeAfterHours optional → new enum + threshold.
        // Only triggers on old data where weeklyOvertimeAfterHours was explicitly set
        // and overtimeType still holds the default (.daily).
        if let legacyWeekly = paySettings.weeklyOvertimeAfterHours {
            if paySettings.overtimeType == .daily {
                paySettings.overtimeType = .weekly
                paySettings.weeklyOvertimeThreshold = legacyWeekly
            }
            paySettings.weeklyOvertimeAfterHours = nil
        }
        if paySettings.overtimeType == .dailyAndWeekly {
            paySettings.overtimeType = .daily
        }
    }

    func currentPayCycle(calendar: Calendar = .current) -> PayCycle {
        PayCycleEngine.currentCycle(settings: paySettings, asOf: Date(), calendar: calendar)
    }

    func payCycle(containing date: Date, calendar: Calendar = .current) -> PayCycle {
        PayCycleEngine.cycle(containing: date, settings: paySettings, calendar: calendar)
    }

    func recentPayCycles(count: Int = 8, calendar: Calendar = .current) -> [PayCycle] {
        PayCycleEngine.recentCyclesEndingBeforeNow(settings: paySettings, count: count, calendar: calendar)
    }

    func save(syncProfile: Bool = true) {
        // Deduplicate entries before saving (prevent duplicate bug)
        var seenIDs = Set<UUID>()
        let deduplicatedEntries = entries.filter { entry in
            if seenIDs.contains(entry.id) {
                #if DEBUG
                print("Removed duplicate entry during save: \(entry.id)")
                #endif
                return false
            }
            seenIDs.insert(entry.id)
            return true
        }
        
        let entriesCopy = deduplicatedEntries
        let yearArchivesCopy = yearArchives
        let settingsCopy = paySettings
        let payHistoryCopy = payHistoryEntries
        let gamificationCopy = gamificationProfile
        let entriesKey = self.entriesKey
        let settingsKey = self.settingsKey
        let payHistoryKey = self.payHistoryKey
        let yearArchivesKey = self.yearArchivesKey
        let gamificationKey = self.gamificationKey
        let prestigeCopy = gamificationCopy.prestige

        // PaySettings and GamificationProfile have main-actor-isolated Encodable
        // conformances, so they're encoded here on the main actor (tiny, so
        // negligible). The large entries/payHistory/yearArchives arrays are
        // encoded on the background queue below so serializing a large history no
        // longer blocks the main thread on every add/edit/delete. (Cloud sync
        // below is independent and stays on the main path.)
        let mainEnc = JSONEncoder()
        mainEnc.dateEncodingStrategy = .iso8601
        let settingsData: Data
        let gamificationData: Data
        do {
            settingsData = try mainEnc.encode(settingsCopy)
            gamificationData = try mainEnc.encode(gamificationCopy)
        } catch {
            AppLogger.db.error("save failed (settings/gamification): \(String(describing: error))")
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            let entriesData: Data
            let payHistoryData: Data
            let yearArchivesData: Data
            do {
                entriesData = try enc.encode(entriesCopy)
                payHistoryData = try enc.encode(payHistoryCopy)
                yearArchivesData = try enc.encode(yearArchivesCopy)
            } catch {
                AppLogger.db.error("save failed: \(String(describing: error))")
                return
            }
            AppLogger.db.debug("save: writing to UserDefaults on background")
            UserDefaults.standard.set(entriesData, forKey: entriesKey)
            UserDefaults.standard.set(settingsData, forKey: settingsKey)
            UserDefaults.standard.set(payHistoryData, forKey: payHistoryKey)
            UserDefaults.standard.set(yearArchivesData, forKey: yearArchivesKey)
            UserDefaults.standard.set(gamificationData, forKey: gamificationKey)

            // Update widget data
            WidgetDataManager.shared.updateWidgetData(
                entries: entriesCopy,
                paySettings: settingsCopy,
                prestige: prestigeCopy
            )
        }

        if cloudSync.isCloudAvailable {
            cloudSync.saveSettings(paySettings)
            if syncProfile {
                syncProfileSnapshotToCloud()
            }
        }
    }

    private func loadAsync(completion: (() -> Void)? = nil) {
        let entriesKey = self.entriesKey
        let settingsKey = self.settingsKey
        let payHistoryKey = self.payHistoryKey
        let yearArchivesKey = self.yearArchivesKey
        let gamificationKey = self.gamificationKey

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            AppLogger.db.debug("loadAsync: reading on background")

            var loadedEntries: [WorkEntry] = []
            var loadedSettings: PaySettings = PaySettings()
            var loadedPayHistory: [PayHistoryEntry] = []
            var loadedYearArchives: [YearArchive] = []
            var loadedGamification: GamificationProfile = .defaultProfile
            var loadedCertificates: [CertificateEntry] = []
            var loadedAwards: [AwardEntry] = []
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601

            if let entriesData = UserDefaults.standard.data(forKey: entriesKey) {
                do {
                    loadedEntries = try dec.decode([WorkEntry].self, from: entriesData)
                } catch {
                    AppLogger.db.error("loadAsync: entries decode failed: \(String(describing: error))")
                }
            }
            if let settingsData = UserDefaults.standard.data(forKey: settingsKey) {
                do {
                    loadedSettings = try decodePaySettingsNonisolated(from: settingsData, decoder: dec)
                } catch {
                    AppLogger.db.error("loadAsync: paySettings decode failed: \(String(describing: error))")
                }
            }
            if let payHistoryData = UserDefaults.standard.data(forKey: payHistoryKey) {
                do {
                    loadedPayHistory = try dec.decode([PayHistoryEntry].self, from: payHistoryData)
                } catch {
                    AppLogger.db.error("loadAsync: payHistory decode failed: \(String(describing: error))")
                }
            }
            if let yearArchivesData = UserDefaults.standard.data(forKey: yearArchivesKey) {
                do {
                    loadedYearArchives = try dec.decode([YearArchive].self, from: yearArchivesData)
                } catch {
                    AppLogger.db.error("loadAsync: yearArchives decode failed: \(String(describing: error))")
                }
            }
            if let gamificationData = UserDefaults.standard.data(forKey: gamificationKey) {
                do {
                    loadedGamification = try decodeGamificationProfileNonisolated(from: gamificationData, decoder: dec)
                } catch {
                    AppLogger.db.error("loadAsync: gamification decode failed: \(String(describing: error))")
                }
            }
            if let certData = UserDefaults.standard.data(forKey: self.certificatesKey) {
                if let entries = try? dec.decode([CertificateEntry].self, from: certData) {
                    loadedCertificates = entries
                } else if let legacy = try? dec.decode([String].self, from: certData) {
                    loadedCertificates = legacy.map { CertificateEntry(filename: $0, label: "") }
                }
            } else if let legacyData = UserDefaults.standard.data(forKey: "certificate_filenames_v1"),
                      let legacy = try? dec.decode([String].self, from: legacyData) {
                loadedCertificates = legacy.map { CertificateEntry(filename: $0, label: "") }
            }
            if let awardsData = UserDefaults.standard.data(forKey: self.awardsKey),
               let entries = try? dec.decode([AwardEntry].self, from: awardsData) {
                loadedAwards = entries
            }

            DispatchQueue.main.async {
                // Deduplicate entries when loading (prevent duplicate bug)
                var seenIDs = Set<UUID>()
                let deduplicatedEntries = loadedEntries.filter { entry in
                    if seenIDs.contains(entry.id) {
                        #if DEBUG
                        print("Removed duplicate entry during load: \(entry.id)")
                        #endif
                        return false
                    }
                    seenIDs.insert(entry.id)
                    return true
                }

                let normalizedArchives = self.normalizeArchives(loadedYearArchives)
                let skipSyncedEntries = self.cloudSync.hasAppliedRemoteEntries
                var shouldRepublishProfileAfterLoad = false

                if skipSyncedEntries {
                    // Entries were already applied from Firestore. Still load local-only
                    // data: yearArchives (never in Firestore) and gamificationProfile
                    // (prestige / XP snapshots come from UserDefaults + cloud gamification
                    // anchors, NOT from the entries listener). Without this, prestige resets
                    // to 0 and lifetime hours drop to current-year only whenever Firestore's
                    // offline cache fires before this loadAsync callback runs.
                    //
                    // IMPORTANT: When applyRemoteEntries ran, store.entries was still empty
                    // (loadAsync hadn't completed yet), so local-only entries were never
                    // merged in. Merge them now so entries that exist in UserDefaults but
                    // not in the Firestore snapshot are not silently discarded.
                    let remoteIDs = Set(self.entries.map(\.id))
                    var mergedEntries = self.entries
                    for localEntry in deduplicatedEntries where !remoteIDs.contains(localEntry.id) {
                        mergedEntries.append(localEntry)
                    }
                    // Re-upload any local-only entries that weren't in the Firestore snapshot.
                    // Include archived years too: Career/lifetime totals count
                    // `yearArchives`, while the server can only recompute from
                    // docs that exist in Firestore. Without this, older archived
                    // shifts remain visible locally but missing from public/admin
                    // profile totals.
                    let localOnlyEntries = deduplicatedEntries.filter { !remoteIDs.contains($0.id) }
                    for entry in localOnlyEntries {
                        self.cloudSync.saveEntry(entry) { _ in }
                    }
                    let localOnlyArchivedEntries = normalizedArchives
                        .flatMap(\.entries)
                        .filter { !remoteIDs.contains($0.id) }
                    for entry in localOnlyArchivedEntries {
                        self.cloudSync.saveEntry(entry) { _ in }
                    }
                    let rollover = self.archivePriorYearsIfNeeded(entries: mergedEntries, archives: normalizedArchives)
                    self.entries = rollover.activeEntries
                    self.yearArchives = rollover.archives
                    self.paySettings = loadedSettings
                    self.normalizePaySettings()
                    self.payHistoryEntries = loadedPayHistory.sorted { $0.year < $1.year }
                    self.certificateEntries = loadedCertificates
                    self.awardEntries = loadedAwards
                    self.gamificationProfile = loadedGamification
                    self.recalculateGamification(eventHint: nil)
                    self.saveLocallyOnly()
                    // Firestore listener applied entries before loadAsync finished,
                    // so an earlier profile push likely wrote stale totalHours.
                    // Re-push after isLoaded flips true below so the sync can run
                    // immediately instead of queueing behind this same load.
                    shouldRepublishProfileAfterLoad = true
                } else {
                    let rollover = self.archivePriorYearsIfNeeded(entries: deduplicatedEntries, archives: normalizedArchives)

                    self.entries = rollover.activeEntries
                    self.yearArchives = rollover.archives
                    self.paySettings = loadedSettings
                    self.normalizePaySettings()
                    self.payHistoryEntries = loadedPayHistory.sorted { $0.year < $1.year }
                    self.certificateEntries = loadedCertificates
                    self.awardEntries = loadedAwards
                    self.gamificationProfile = loadedGamification
                    self.recalculateGamification(eventHint: nil)
                    if rollover.didArchive {
                        self.save()
                    }
                }

                self.isLoaded = true
                AppLogger.db.debug("loadAsync: done, \(deduplicatedEntries.count) entries (removed \(loadedEntries.count - deduplicatedEntries.count) duplicates), skipSyncedEntries=\(skipSyncedEntries)")
                // Push current data to widget on every app launch
                WidgetDataManager.shared.updateWidgetData(
                    entries: self.entries,
                    paySettings: self.paySettings,
                    prestige: self.gamificationProfile.prestige
                )
                if self.cloudSync.isCloudAvailable && !self.cloudSync.hasAppliedRemoteEntries {
                    self.cloudSync.pullFromCloud()
                }
                if shouldRepublishProfileAfterLoad {
                    self.syncProfileSnapshotToCloud()
                }
                self.cloudSync.runDailyCloudRepairIfNeeded()
                completion?()
            }
        }
    }

    func applyYearlyResetIfNeeded() {
        let rollover = archivePriorYearsIfNeeded(entries: entries, archives: yearArchives)
        guard rollover.didArchive else { return }
        entries = rollover.activeEntries
        yearArchives = rollover.archives
        save()
    }

    private func initializeYearlyResetDefaultIfNeeded() {
        if UserDefaults.standard.object(forKey: autoYearlyResetKey) == nil {
            UserDefaults.standard.set(true, forKey: autoYearlyResetKey)
        }
    }

    private var autoYearlyResetEnabled: Bool {
        UserDefaults.standard.bool(forKey: autoYearlyResetKey)
    }

    private func normalizeArchives(_ archives: [YearArchive]) -> [YearArchive] {
        var byYear: [Int: [WorkEntry]] = [:]
        for archive in archives {
            byYear[archive.year, default: []].append(contentsOf: archive.entries)
        }
        return byYear.keys.sorted().map { year in
            var seen = Set<UUID>()
            let deduped = (byYear[year] ?? [])
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.date > $1.date }
            return YearArchive(year: year, entries: deduped)
        }
    }

    private func archivePriorYearsIfNeeded(
        entries: [WorkEntry],
        archives: [YearArchive]
    ) -> (activeEntries: [WorkEntry], archives: [YearArchive], didArchive: Bool) {
        guard autoYearlyResetEnabled else {
            return (entries.sorted { $0.date > $1.date }, normalizeArchives(archives), false)
        }

        let currentYear = Calendar.current.component(.year, from: Date())
        let priorEntries = entries.filter { Calendar.current.component(.year, from: $0.date) < currentYear }
        let activeEntries = entries
            .filter { Calendar.current.component(.year, from: $0.date) >= currentYear }
            .sorted { $0.date > $1.date }

        guard !priorEntries.isEmpty else {
            return (activeEntries, normalizeArchives(archives), false)
        }

        var archiveMap: [Int: [WorkEntry]] = [:]
        for archive in archives {
            archiveMap[archive.year, default: []].append(contentsOf: archive.entries)
        }
        for entry in priorEntries {
            let year = Calendar.current.component(.year, from: entry.date)
            archiveMap[year, default: []].append(entry)
        }

        let merged = archiveMap.keys.sorted().map { year -> YearArchive in
            var seen = Set<UUID>()
            let deduped = (archiveMap[year] ?? [])
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.date > $1.date }
            return YearArchive(year: year, entries: deduped)
        }
        return (activeEntries, merged, true)
    }
}

// Top-level helper function to decode PaySettings in a nonisolated context
// This avoids Swift 6 main actor isolation issues
private func decodePaySettingsNonisolated(from data: Data, decoder: JSONDecoder) throws -> PaySettings {
    return try decoder.decode(PaySettings.self, from: data)
}

private func decodeGamificationProfileNonisolated(from data: Data, decoder: JSONDecoder) throws -> GamificationProfile {
    return try decoder.decode(GamificationProfile.self, from: data)
}

enum AchievementRarity: String, Codable, CaseIterable {
    case common
    case uncommon
    case rare
    case epic
    case legendary
    case mythic

    var xpMultiplier: Double {
        switch self {
        case .common: return 1.0
        case .uncommon: return 1.15
        case .rare: return 1.35
        case .epic: return 1.65
        case .legendary: return 2.0
        case .mythic: return 2.5
        }
    }
}

enum RewardType: String, Codable {
    case badge
    case title
    case theme
    case xpBoost
    case streakFreeze
}

struct GamificationReward: Codable, Hashable {
    var id: String
    var type: RewardType
    var name: String
    var value: Int
}

struct GamificationAchievement: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var detail: String
    var rarity: AchievementRarity
    var isHidden: Bool
    var unlockedAt: Date?
}

enum ChallengeCadence: String, Codable {
    case daily
    case weekly
}

struct ChallengeProgress: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var cadence: ChallengeCadence
    var current: Double
    var target: Double
    var completed: Bool
    var rewardXP: Int
    var rewardStreakFreeze: Int
}

struct BattlePassReward: Codable, Hashable {
    var track: String // "free" / "premium"
    var reward: GamificationReward
}

struct BattlePassTier: Codable, Hashable {
    var tier: Int
    var xpRequired: Int
    var rewards: [BattlePassReward]
}

struct BattlePassProgress: Codable, Hashable {
    var seasonID: String
    var seasonXP: Int
    var currentTier: Int
    var tiers: [BattlePassTier]
}

struct XPBoostEvent: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var multiplier: Double
    var startDate: Date
    var endDate: Date
}

struct RivalProgress: Codable, Hashable {
    var friendName: String
    var targetXPGap: Int
    var isActive: Bool
}

struct CrewProgress: Codable, Hashable {
    var crewName: String
    var memberCount: Int
    var weeklyCrewXPGoal: Int
}

struct GamificationProfile: Codable {
    var totalXP: Int
    var level: Int
    var prestige: Int
    /// Ratchet floor: the highest prestige the user has ever legitimately earned.
    /// Only ever increases — recalculation enforces `prestige >= prestigeFloor`
    /// so a future bug can never zero out prestige permanently.
    /// Optional so synthesized Codable uses decodeIfPresent — avoids throwing
    /// keyNotFound on existing saves that predate this field, which would wipe
    /// the entire profile including prestigeXPSnapshots and drop the user's level.
    var prestigeFloor: Int? = nil
    // Records the actual cumulative XP at the moment of each prestige,
    // so early-prestige doesn't break the XP pool subtraction math.
    var prestigeXPSnapshots: [Int] = []
    /// Paid work hours at each prestige — prestige only rolls back when hours are deleted.
    var prestigeHourSnapshots: [Double] = []
    /// Admin XP bonus applied on top of shift-derived XP so an admin level set
    /// becomes the user's current level while shifts still add XP normally.
    var adminXPOffset: Int = 0
    var xpIntoCurrentLevel: Int
    var xpForNextLevel: Int
    var canPrestige: Bool
    var currentStreak: Int
    var bestStreak: Int
    var streakFreezes: Int
    var unlockedBadges: [String]
    var unlockedTitles: [String]
    var equippedTitle: String?
    var achievements: [GamificationAchievement]
    var dailyChallenges: [ChallengeProgress]
    var weeklyChallenges: [ChallengeProgress]
    var battlePass: BattlePassProgress
    var activeBoosts: [XPBoostEvent]
    var seasonalProgressionResets: Int
    var rival: RivalProgress?
    var crew: CrewProgress?

    static let defaultProfile = GamificationProfile(
        totalXP: 0,
        level: 1,
        prestige: 0,
        xpIntoCurrentLevel: 0,
        xpForNextLevel: GamificationEngine.xpRequiredForLevel(1),
        canPrestige: false,
        currentStreak: 0,
        bestStreak: 0,
        streakFreezes: 0,
        unlockedBadges: [],
        unlockedTitles: [],
        equippedTitle: nil,
        achievements: [],
        dailyChallenges: [],
        weeklyChallenges: [],
        battlePass: BattlePassProgress(
            seasonID: GamificationEngine.currentSeasonID(),
            seasonXP: 0,
            currentTier: 1,
            tiers: GamificationEngine.makeBattlePassTiers()
        ),
        activeBoosts: [],
        seasonalProgressionResets: 0,
        rival: nil,
        crew: nil
    )
}

private enum GamificationEngine {
    private static let xpPerHour = 100
    private static let shiftLogXP = 50
    private static let overtimeXPPerHour = 150
    private static let streakDayXP = 200
    private static let longShiftXP = 300
    private static let weeklyCompletionXP = 500

    static func buildProfile(
        previous: GamificationProfile,
        activeEntries: [WorkEntry],
        archivedEntries: [WorkEntry],
        overtimeHours: (WorkEntry) -> Double
    ) -> GamificationProfile {
        let allEntries = (activeEntries + archivedEntries).sorted { $0.date < $1.date }
        let workEntries = allEntries.filter { !$0.isOffDay }
        let workedDays = distinctWorkedDays(from: workEntries)
        let streak = currentStreak(from: workedDays)
        let bestStreak = bestStreakLength(from: workedDays)
        let freezeEarned = workedDays.count / 7

        let hourlyXP = Int(workEntries.reduce(0.0) { $0 + ($1.paidHours * Double(xpPerHour)) }.rounded())
        let loggingXP = workEntries.count * shiftLogXP
        let overtimeXP = Int(workEntries.reduce(0.0) { $0 + (overtimeHours($1) * Double(overtimeXPPerHour)) }.rounded())
        let streakXP = workedDays.count * streakDayXP
        let longShiftCount = workEntries.filter { $0.paidHours >= 12.0 }.count
        let longShiftBonus = longShiftCount * longShiftXP
        let weeklyCompletionCount = completedWeekCount(from: workEntries)
        let weeklyCompletionBonus = weeklyCompletionCount * weeklyCompletionXP

        var totalXP = hourlyXP + loggingXP + overtimeXP + streakXP + longShiftBonus + weeklyCompletionBonus

        // Daily + weekly challenge rewards.
        let daily = makeDailyChallenges(entries: workEntries)
        let weekly = makeWeeklyChallenges(entries: workEntries)
        let challengeXP = (daily + weekly)
            .filter(\.completed)
            .reduce(0) { $0 + $1.rewardXP }
        let challengeFreezes = (daily + weekly)
            .filter(\.completed)
            .reduce(0) { $0 + $1.rewardStreakFreeze }

        totalXP += challengeXP

        totalXP += previous.adminXPOffset

        // XP boost events (backend-ready; currently empty unless configured).
        let boostMultiplier = max(previous.activeBoosts.map(\.multiplier).max() ?? 1.0, 1.0)
        totalXP = Int((Double(totalXP) * boostMultiplier).rounded())

        let totalPaidHours = workEntries.reduce(0.0) { $0 + $1.paidHours }

        // Prestige is sticky once earned — only roll back when logged hours are removed,
        // not when bonus/challenge XP fluctuates between recalculations.
        // prestigeFloor is a ratchet: once set it only goes up, so a future bug that
        // zeros `previous.prestige` still can't permanently erase earned prestige.
        let floor = min(max(previous.prestigeFloor ?? 0, 0), 10)
        var adjustedPrestige = min(max(max(previous.prestige, floor), 0), 10)
        var adjustedSnapshots = previous.prestigeXPSnapshots
        var adjustedHourSnapshots = previous.prestigeHourSnapshots

        // Grandfather existing prestiged profiles that predate hour snapshots.
        while adjustedHourSnapshots.count < adjustedPrestige {
            adjustedHourSnapshots.append(totalPaidHours)
        }

        while adjustedPrestige > 0,
              let lastHours = adjustedHourSnapshots.last,
              totalPaidHours < lastHours - 0.0001 {
            adjustedHourSnapshots.removeLast()
            if !adjustedSnapshots.isEmpty {
                adjustedSnapshots.removeLast()
            }
            adjustedPrestige -= 1
        }
        let manualPrestige = adjustedPrestige
        let (level, xpIntoLevel, xpForNext, canPrestige) = levelState(
            for: max(totalXP, 0),
            prestige: manualPrestige,
            snapshots: adjustedSnapshots
        )
        let seasonID = currentSeasonID()
        let seasonResetHappened = previous.battlePass.seasonID != seasonID
        let seasonXP = seasonXPValue(for: workEntries, overtimeHours: overtimeHours, seasonID: seasonID)
        let tiers = makeBattlePassTiers()
        let currentTier = battlePassTier(for: seasonXP, tiers: tiers)
        // Carry over only achievement-based titles; recalculate milestone/prestige titles fresh
        // so they always reflect the actual current level (prevents stale titles at wrong levels)
        let nonMilestoneTitles = previous.unlockedTitles.filter {
            !$0.hasPrefix("Level ") && !$0.hasPrefix("Prestige ")
        }
        var unlockedTitles = Set(nonMilestoneTitles)
        var unlockedBadges = Set(previous.unlockedBadges)

        for milestone in [10, 25, 50, 75, 100] where level >= milestone {
            // Level 10 is reached too quickly to feel like a "Veteran" milestone —
            // the badge still unlocks at 10, but the equippable title starts at 25.
            if milestone >= 25 {
                unlockedTitles.insert("Level \(milestone) Veteran")
            }
            unlockedBadges.insert("level_\(milestone)")
        }
        for p in 1...10 where manualPrestige >= p {
            unlockedTitles.insert("Prestige \(p)")
            unlockedBadges.insert("prestige_\(p)")
        }

        let achievements = evaluateAchievements(
            existing: previous.achievements,
            entries: workEntries,
            workedDays: workedDays,
            totalXP: totalXP,
            level: level,
            prestige: manualPrestige,
            overtimeHours: overtimeHours
        )

        let newlyUnlockedTitles = achievements
            .filter { $0.unlockedAt != nil }
            .map(\.name)
            .filter { $0.contains("Title: ") }
            .map { $0.replacingOccurrences(of: "Title: ", with: "") }
        for title in newlyUnlockedTitles { unlockedTitles.insert(title) }

        // Validate equipped title is still unlocked; clear if not (e.g. level dropped below threshold)
        let equippedTitle: String?
        if let prev = previous.equippedTitle, unlockedTitles.contains(prev) {
            equippedTitle = prev
        } else {
            // Auto-select best available: highest milestone title, or first alphabetically
            let milestoneOrder = ["Level 100 Veteran", "Level 75 Veteran", "Level 50 Veteran", "Level 25 Veteran"]
            equippedTitle = milestoneOrder.first { unlockedTitles.contains($0) } ?? unlockedTitles.sorted().first
        }

        return GamificationProfile(
            totalXP: totalXP,
            level: level,
            prestige: manualPrestige,
            prestigeFloor: max(floor, manualPrestige) as Int?,
            prestigeXPSnapshots: adjustedSnapshots,
            prestigeHourSnapshots: adjustedHourSnapshots,
            xpIntoCurrentLevel: xpIntoLevel,
            xpForNextLevel: xpForNext,
            canPrestige: canPrestige,
            currentStreak: streak,
            bestStreak: max(bestStreak, previous.bestStreak),
            streakFreezes: max(previous.streakFreezes, freezeEarned + challengeFreezes),
            unlockedBadges: unlockedBadges.sorted(),
            unlockedTitles: unlockedTitles.sorted(),
            equippedTitle: equippedTitle,
            achievements: achievements,
            dailyChallenges: daily,
            weeklyChallenges: weekly,
            battlePass: BattlePassProgress(
                seasonID: seasonID,
                seasonXP: seasonXP,
                currentTier: currentTier,
                tiers: tiers
            ),
            activeBoosts: previous.activeBoosts.filter { $0.endDate >= Date() },
            seasonalProgressionResets: previous.seasonalProgressionResets + (seasonResetHappened ? 1 : 0),
            rival: previous.rival,
            crew: previous.crew
        )
    }

    /// Per-component XP breakdown mirroring `buildProfile`'s totalXP math.
    /// Pushed with the gamification anchors so the server's XP-migration
    /// shadow logs can attribute client/server drift to a specific component.
    static func xpComponentBreakdown(
        activeEntries: [WorkEntry],
        archivedEntries: [WorkEntry],
        adminXPOffset: Int,
        overtimeHours: (WorkEntry) -> Double
    ) -> [String: Int] {
        let allEntries = (activeEntries + archivedEntries).sorted { $0.date < $1.date }
        let workEntries = allEntries.filter { !$0.isOffDay }
        let workedDays = distinctWorkedDays(from: workEntries)
        let daily = makeDailyChallenges(entries: workEntries)
        let weekly = makeWeeklyChallenges(entries: workEntries)
        let challengeXP = (daily + weekly)
            .filter(\.completed)
            .reduce(0) { $0 + $1.rewardXP }
        return [
            "hourly": Int(workEntries.reduce(0.0) { $0 + ($1.paidHours * Double(xpPerHour)) }.rounded()),
            "logging": workEntries.count * shiftLogXP,
            "overtime": Int(workEntries.reduce(0.0) { $0 + (overtimeHours($1) * Double(overtimeXPPerHour)) }.rounded()),
            "streakDays": workedDays.count * streakDayXP,
            "longShift": workEntries.filter { $0.paidHours >= 12.0 }.count * longShiftXP,
            "weeklyCompletion": completedWeekCount(from: workEntries) * weeklyCompletionXP,
            "challenge": challengeXP,
            "adminOffset": adminXPOffset,
        ]
    }

    static func eventMessage(previous: GamificationProfile, current: GamificationProfile, hint: String?) -> String? {
        if current.prestige > previous.prestige {
            return "Prestige \(current.prestige) unlocked."
        }
        if current.level > previous.level {
            return "Level up! You're now level \(current.level)."
        }
        let newAchievements = Set(current.achievements.filter { $0.unlockedAt != nil }.map(\.id))
            .subtracting(previous.achievements.filter { $0.unlockedAt != nil }.map(\.id))
        if !newAchievements.isEmpty {
            return "Achievement unlocked."
        }
        if current.totalXP > previous.totalXP, let hint {
            return "\(hint) • +\(current.totalXP - previous.totalXP) XP"
        }
        return nil
    }

    static func currentSeasonID() -> String {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let month = cal.component(.month, from: Date())
        let quarter = ((month - 1) / 3) + 1
        return "\(year)-S\(quarter)"
    }

    static func xpRequiredForLevel(_ level: Int) -> Int {
        GamificationLevelCalculator.xpRequiredForLevel(level)
    }

    static func makeBattlePassTiers() -> [BattlePassTier] {
        (1...50).map { tier in
            let xpRequired = tier * 1000
            return BattlePassTier(
                tier: tier,
                xpRequired: xpRequired,
                rewards: [
                    BattlePassReward(
                        track: "free",
                        reward: GamificationReward(
                            id: "free_t\(tier)",
                            type: tier % 10 == 0 ? .title : .badge,
                            name: tier % 10 == 0 ? "Tier \(tier) Title" : "Tier \(tier) Badge",
                            value: tier
                        )
                    ),
                    BattlePassReward(
                        track: "premium",
                        reward: GamificationReward(
                            id: "premium_t\(tier)",
                            type: tier % 5 == 0 ? .theme : .xpBoost,
                            name: tier % 5 == 0 ? "Theme Variant \(tier / 5)" : "XP Boost \(tier)",
                            value: tier % 5 == 0 ? 1 : 15
                        )
                    )
                ]
            )
        }
    }

    static func maxLevelForPrestige(_ prestige: Int) -> Int {
        GamificationLevelCalculator.maxLevelForPrestige(prestige)
    }

    private static func levelState(
        for totalXP: Int,
        prestige: Int,
        snapshots: [Int] = []
    ) -> (level: Int, xpIntoLevel: Int, xpForNext: Int, canPrestige: Bool) {
        GamificationLevelCalculator.levelState(for: totalXP, prestige: prestige, snapshots: snapshots)
    }

    private static func distinctWorkedDays(from entries: [WorkEntry]) -> [Date] {
        let cal = Calendar.current
        return Array(Set(entries.map { cal.startOfDay(for: $0.date) })).sorted()
    }

    private static func currentStreak(from workedDays: [Date]) -> Int {
        guard let last = workedDays.last else { return 0 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dayDiff = cal.dateComponents([.day], from: last, to: today).day ?? 99
        guard dayDiff <= 1 else { return 0 }
        var streak = 1
        var cursor = last
        for day in workedDays.dropLast().reversed() {
            let diff = cal.dateComponents([.day], from: day, to: cursor).day ?? 99
            if diff == 1 {
                streak += 1
                cursor = day
            } else {
                break
            }
        }
        return streak
    }

    private static func bestStreakLength(from workedDays: [Date]) -> Int {
        guard !workedDays.isEmpty else { return 0 }
        let cal = Calendar.current
        var best = 1
        var current = 1
        for idx in 1..<workedDays.count {
            let diff = cal.dateComponents([.day], from: workedDays[idx - 1], to: workedDays[idx]).day ?? 99
            if diff == 1 {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }

    private static func completedWeekCount(from entries: [WorkEntry]) -> Int {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        var weekHours: [Date: Double] = [:]
        for entry in entries {
            guard let start = cal.dateInterval(of: .weekOfYear, for: entry.date)?.start else { continue }
            weekHours[start, default: 0] += entry.paidHours
        }
        return weekHours.values.filter { $0 >= 40 }.count
    }

    private static func makeDailyChallenges(entries: [WorkEntry]) -> [ChallengeProgress] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayEntries = entries.filter { cal.isDate($0.date, inSameDayAs: today) }
        let hasShift = !todayEntries.isEmpty
        let hoursToday = todayEntries.reduce(0.0) { $0 + $1.paidHours }
        let loggedBefore9PM = todayEntries.contains {
            let comps = cal.dateComponents([.hour], from: $0.date)
            return (comps.hour ?? 23) < 21
        }

        return [
            ChallengeProgress(id: "daily_log_shift", title: "Log a shift", cadence: .daily, current: hasShift ? 1 : 0, target: 1, completed: hasShift, rewardXP: 200, rewardStreakFreeze: 0),
            ChallengeProgress(id: "daily_8_hours", title: "Work 8+ hours", cadence: .daily, current: hoursToday, target: 8, completed: hoursToday >= 8, rewardXP: 300, rewardStreakFreeze: 0),
            ChallengeProgress(id: "daily_log_early", title: "Log before 9 PM", cadence: .daily, current: loggedBefore9PM ? 1 : 0, target: 1, completed: loggedBefore9PM, rewardXP: 250, rewardStreakFreeze: 0)
        ]
    }

    private static func makeWeeklyChallenges(entries: [WorkEntry]) -> [ChallengeProgress] {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
              let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else {
            return []
        }
        let weekEntries = entries.filter { $0.date >= weekStart && $0.date < weekEnd }
        let weekHours = weekEntries.reduce(0.0) { $0 + $1.paidHours }
        let workedWeekend = weekEntries.contains {
            let wd = cal.component(.weekday, from: $0.date)
            return wd == 1 || wd == 7
        }
        let shiftCount = Set(weekEntries.map { cal.startOfDay(for: $0.date) }).count
        return [
            ChallengeProgress(id: "weekly_50_hours", title: "Hit 50 hours", cadence: .weekly, current: weekHours, target: 50, completed: weekHours >= 50, rewardXP: 700, rewardStreakFreeze: 1),
            ChallengeProgress(id: "weekly_weekend", title: "Work a weekend", cadence: .weekly, current: workedWeekend ? 1 : 0, target: 1, completed: workedWeekend, rewardXP: 500, rewardStreakFreeze: 0),
            ChallengeProgress(id: "weekly_5_shifts", title: "Log 5 shifts", cadence: .weekly, current: Double(shiftCount), target: 5, completed: shiftCount >= 5, rewardXP: 600, rewardStreakFreeze: 1)
        ]
    }

    private static func seasonXPValue(
        for entries: [WorkEntry],
        overtimeHours: (WorkEntry) -> Double,
        seasonID: String
    ) -> Int {
        let seasonEntries = entries.filter { entry in
            seasonIDForDate(entry.date) == seasonID
        }
        let hoursXP = Int(seasonEntries.reduce(0.0) { $0 + ($1.paidHours * Double(xpPerHour)) }.rounded())
        let otXP = Int(seasonEntries.reduce(0.0) { $0 + (overtimeHours($1) * Double(overtimeXPPerHour)) }.rounded())
        let shiftXP = seasonEntries.count * shiftLogXP
        return max(0, hoursXP + otXP + shiftXP)
    }

    private static func battlePassTier(for seasonXP: Int, tiers: [BattlePassTier]) -> Int {
        var tier = 1
        for t in tiers where seasonXP >= t.xpRequired {
            tier = max(tier, t.tier)
        }
        return tier
    }

    private static func seasonIDForDate(_ date: Date) -> String {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let quarter = ((month - 1) / 3) + 1
        return "\(year)-S\(quarter)"
    }

    private static func evaluateAchievements(
        existing: [GamificationAchievement],
        entries: [WorkEntry],
        workedDays: [Date],
        totalXP: Int,
        level: Int,
        prestige: Int,
        overtimeHours: (WorkEntry) -> Double
    ) -> [GamificationAchievement] {
        let cal = Calendar.current
        let existingMap = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let overtimeShifts = entries.filter { overtimeHours($0) > 0 }.count
        let holidayShifts = entries.filter(\.isHoliday).count
        let veryEarlyShifts = entries.filter { (cal.component(.hour, from: $0.start) < 4) }.count
        let longShiftStreak = longestConsecutive(entries.filter { $0.paidHours >= 12 }.map { cal.startOfDay(for: $0.date) })

        let defs: [(String, String, String, AchievementRarity, Bool, Bool)] = [
            ("ach_total_10k_xp", "XP Recruit", "Reach 10,000 XP", .common, false, totalXP >= 10_000),
            ("ach_total_100k_xp", "XP War Machine", "Reach 100,000 XP", .legendary, false, totalXP >= 100_000),
            ("ach_ot_king", "Title: OT King", "Log 25 overtime shifts", .epic, false, overtimeShifts >= 25),
            ("ach_prestige_1", "Prestige Initiate", "Reach Prestige 1", .epic, false, prestige >= 1),
            ("ach_prestige_5", "Prestige Warlord", "Reach Prestige 5", .mythic, false, prestige >= 5),
            ("ach_level_max", "Centurion", "Max out your level", .mythic, false, level >= maxLevelForPrestige(prestige)),
            ("ach_early_bird", "Hidden: Pre-Dawn Grinder", "Log a shift before 4 AM", .rare, true, veryEarlyShifts >= 1),
            ("ach_long_shift_chain", "Hidden: Iron Marathon", "Log 3 long shifts in a row", .legendary, true, longShiftStreak >= 3),
            ("ach_holiday_shift", "Hidden: Holiday Hero", "Work 3 holiday shifts", .epic, true, holidayShifts >= 3),
            ("ach_streak_30", "Unbreakable", "Maintain a 30-day streak", .mythic, false, currentStreak(from: workedDays) >= 30)
        ]

        return defs.map { id, name, detail, rarity, hidden, isUnlockedNow in
            var item = existingMap[id] ?? GamificationAchievement(
                id: id,
                name: name,
                detail: detail,
                rarity: rarity,
                isHidden: hidden,
                unlockedAt: nil
            )
            if isUnlockedNow && item.unlockedAt == nil {
                item.unlockedAt = Date()
            }
            return item
        }.sorted { ($0.unlockedAt ?? .distantFuture) < ($1.unlockedAt ?? .distantFuture) }
    }

    private static func longestConsecutive(_ days: [Date]) -> Int {
        guard !days.isEmpty else { return 0 }
        let cal = Calendar.current
        let sorted = Array(Set(days)).sorted()
        var best = 1
        var current = 1
        for i in 1..<sorted.count {
            let diff = cal.dateComponents([.day], from: sorted[i - 1], to: sorted[i]).day ?? 99
            if diff == 1 {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }
}
