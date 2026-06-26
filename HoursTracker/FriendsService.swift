import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct FriendProfile: Identifiable, Equatable, Hashable {
    var id: String { uid }
    let uid: String
    let displayName: String
    let level: Int
    let prestige: Int
    let currentStreak: Int
    let bestStreak: Int
    let totalHours: Double
    /// Hours logged in the friend's current pay period (their cheque window).
    let chequeHours: Double
    /// Hours logged in the current Monday-aligned week (per `WeeklyStatsCalculator`).
    /// Drives the "Most Hours This Week" leaderboard category.
    let weeklyHours: Double
    /// Shift entries logged in the current Monday-aligned week.
    /// Drives the "Most Shifts" leaderboard category.
    let weeklyShiftsLogged: Int
    /// Distinct calendar days the friend logged a non-off-day entry this week.
    /// Drives "Consistency Streak" alongside `currentStreak`.
    let weeklyDaysLogged: Int
    let badgeCount: Int
    /// Earned badges shared on the friend's public profile.
    let unlockedBadgeSummaries: [SharedBadgeSummary]
    let equippedTitle: String
    /// Public download URL for the friend's profile photo (Firebase Storage).
    let profilePhotoURL: String?
    /// Employer name shared on their public profile (optional).
    let companyName: String
    /// Job title / role shared on their public profile (optional).
    let companyOccupation: String
    /// When they started at their current company (optional).
    let companyStartDate: Date?
    /// Paid hours shared since their company start date.
    let companyHoursLogged: Double
    /// Distinct worked days shared since their company start date.
    let companyDaysWorked: Int
    /// When this friend's stats doc was last written to Firestore.
    /// Used to sort the friends list by most-recently-active.
    let updatedAt: Date?
    /// When the current user and this friend connected (from the friends sub-doc).
    let friendsSince: Date?
    /// Per-day breakdown for the friend's current pay cheque (privacy-gated).
    let chequeDailySummary: [FriendDailyEntry]
    /// "yyyy-MM-dd" start of the friend's current cheque window.
    let chequeWindowStart: String
    /// "yyyy-MM-dd" last work day (cutoff) of the friend's current cheque window.
    let chequeWindowCutoff: String

    var hasChequeDetail: Bool {
        !chequeWindowStart.isEmpty || !chequeDailySummary.isEmpty || chequeHours > 0
    }

    var hasBadgeDetail: Bool {
        !unlockedBadgeSummaries.isEmpty || badgeCount > 0
    }
    /// Friend's privacy flags as broadcast in their last profile snapshot.
    /// We respect these on the consumer side even though Firestore rules
    /// also enforce visibility — this keeps the UI honest if a flag was
    /// flipped recently and the data is still resident locally.
    let privacy: SocialPrivacyFlags

    var levelDisplayLine: String {
        GamificationLevelCalculator.displayLevelLine(level: level, prestige: prestige)
    }

    var rankTitle: String {
        GamificationLevelCalculator.rankTitle(forLevel: level, prestige: prestige)
    }

    var prestigeTier: PrestigeTheme.Tier {
        PrestigeTheme.tier(for: prestige)
    }

    var hasCompanyInfo: Bool {
        !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !companyOccupation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || companyStartDate != nil
    }
}

/// One day's hours within a friend's current pay cheque.
struct FriendDailyEntry: Identifiable, Equatable, Hashable {
    var id: String { date }
    /// ISO-8601 date string "yyyy-MM-dd".
    let date: String
    let hours: Double
    let shifts: Int

    static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var calendarDate: Date? { Self.isoFormatter.date(from: date) }
}

struct FriendRequestItem: Identifiable, Equatable {
    var id: String { fromUid }
    let fromUid: String
    let fromName: String
    let sentAt: Date?
}

// MARK: - Friends (Firestore)

@MainActor
final class FriendsService: ObservableObject {
    static let shared = FriendsService()

    @Published var friends: [FriendProfile] = []
    @Published var pendingRequests: [FriendRequestItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var myFriendCode: String?

    private let db = Firestore.firestore()
    private var friendIdsListener: ListenerRegistration?
    private var friendIdsListenerKey: String?
    private var friendshipListenerA: ListenerRegistration?
    private var friendshipListenerAKey: String?
    private var friendshipListenerB: ListenerRegistration?
    private var friendshipListenerBKey: String?
    private var requestsListener: ListenerRegistration?
    private var requestsListenerKey: String?
    private var profileListeners: [String: ListenerRegistration] = [:]
    private var profileListenerKeys: [String: String] = [:]
    private var weeklyStatsListeners: [String: ListenerRegistration] = [:]
    private var weeklyStatsListenerKeys: [String: String] = [:]
    private var friendWeeklyStatsCache: [String: [String: Any]] = [:]
    private var myProfileListener: ListenerRegistration?
    private var myProfileListenerKey: String?
    private var activeListeningUid: String?
    /// Caches the `addedAt` timestamp from each friendship doc for display.
    private var friendAddedAtMap: [String: Date] = [:]
    /// Friend UIDs still awaiting their first profile snapshot this load cycle.
    private var pendingProfileLoads: Set<String> = []
    private var friendIdsResolved = false
    private var legacyFriendIds: Set<String> = []
    private var friendshipIdsFromA: Set<String> = []
    private var friendshipIdsFromB: Set<String> = []
    /// Periodic background refresh — runs every 10 s while listeners are active
    /// to recover from silently-dropped snapshot listeners (network blips, etc.).
    private var refreshTimer: Timer?
    private var loadingTimeoutTask: Task<Void, Never>?

    func startListening(uid: String) {
        if activeListeningUid == uid,
           friendIdsListener != nil || friendshipListenerA != nil {
            // Already listening — kick off an immediate profile refresh to make
            // sure we have the latest data (handles sheet re-opens, tab switches).
            Task { await refreshFriendProfiles() }
            return
        }
        stopListening()
        activeListeningUid = uid
        isLoading = true

        startRefreshTimer()
        startLoadingTimeout()
        Task { await ensureFriendCode(uid: uid) }

        myProfileListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self, self.activeListeningUid == uid else { return }
                    let code = snapshot?.data()?["friendCode"] as? String
                    if let code, !code.isEmpty {
                        self.myFriendCode = code
                    }
                }
            }
        myProfileListenerKey = FirebaseListenerRegistry.shared.register(
            owner: .friendsService,
            purpose: "myFriendCode",
            uid: uid,
            registration: myProfileListener!
        )

        // Always listen to legacy friends subcollection so existing friends
        // appear even before the friendships backfill has run.
        friendIdsListener = db.collection("users").document(uid).collection("friends")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.activeListeningUid == uid else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        self.clearLoadingState()
                        return
                    }
                    let docs = snapshot?.documents ?? []
                    for doc in docs {
                        if let ts = doc.data()["addedAt"] as? Timestamp {
                            self.friendAddedAtMap[doc.documentID] = ts.dateValue()
                        }
                    }
                    self.legacyFriendIds = Set(docs.map(\.documentID))
                    if FirebaseMigrationFlags.useFriendshipsCollection {
                        self.mergeFriendshipIds()
                    } else {
                        self.friendIdsResolved = true
                        self.resubscribeProfiles(friendUids: Array(self.legacyFriendIds))
                    }
                }
            }
        friendIdsListenerKey = FirebaseListenerRegistry.shared.register(
            owner: .friendsService,
            purpose: "friends",
            uid: uid,
            registration: friendIdsListener!
        )

        if FirebaseMigrationFlags.useFriendshipsCollection {
            startFriendshipListeners(uid: uid)
        }

        requestsListener = db.collection("users").document(uid).collection("friendRequests")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.activeListeningUid == uid else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        self.clearLoadingState()
                        return
                    }
                    self.pendingRequests = snapshot?.documents.compactMap { doc in
                        let data = doc.data()
                        let name = data["fromName"] as? String ?? "Friend"
                        let sentAt = (data["sentAt"] as? Timestamp)?.dateValue()
                        return FriendRequestItem(fromUid: doc.documentID, fromName: name, sentAt: sentAt)
                    } ?? []
                }
            }
        requestsListenerKey = FirebaseListenerRegistry.shared.register(
            owner: .friendsService,
            purpose: "friendRequests",
            uid: uid,
            registration: requestsListener!
        )
    }

    private func startFriendshipListeners(uid: String) {
        friendshipIdsFromA = []
        friendshipIdsFromB = []

        friendshipListenerA = db.collection("friendships")
            .whereField("userA", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.activeListeningUid == uid else { return }
                    if let error {
                        FirestoreOperationLog.listenerError(owner: .friendsService, purpose: "friendships.userA", uid: uid, error: error)
                        return
                    }
                    for doc in snapshot?.documents ?? [] {
                        let data = doc.data()
                        if let other = FriendshipPairId.otherUid(in: data, myUid: uid),
                           let created = data["createdAt"] as? Timestamp {
                            self.friendAddedAtMap[other] = created.dateValue()
                        }
                    }
                    self.friendshipIdsFromA = Set(snapshot?.documents.compactMap {
                        FriendshipPairId.otherUid(in: $0.data(), myUid: uid)
                    } ?? [])
                    self.mergeFriendshipIds()
                }
            }
        friendshipListenerAKey = FirebaseListenerRegistry.shared.register(
            owner: .friendsService,
            purpose: "friendships.userA",
            uid: uid,
            registration: friendshipListenerA!
        )

        friendshipListenerB = db.collection("friendships")
            .whereField("userB", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.activeListeningUid == uid else { return }
                    if let error {
                        FirestoreOperationLog.listenerError(owner: .friendsService, purpose: "friendships.userB", uid: uid, error: error)
                        return
                    }
                    for doc in snapshot?.documents ?? [] {
                        let data = doc.data()
                        if let other = FriendshipPairId.otherUid(in: data, myUid: uid),
                           let created = data["createdAt"] as? Timestamp {
                            self.friendAddedAtMap[other] = created.dateValue()
                        }
                    }
                    self.friendshipIdsFromB = Set(snapshot?.documents.compactMap {
                        FriendshipPairId.otherUid(in: $0.data(), myUid: uid)
                    } ?? [])
                    self.mergeFriendshipIds()
                }
            }
        friendshipListenerBKey = FirebaseListenerRegistry.shared.register(
            owner: .friendsService,
            purpose: "friendships.userB",
            uid: uid,
            registration: friendshipListenerB!
        )
    }

    private func mergeFriendshipIds() {
        let ids = Array(legacyFriendIds
            .union(friendshipIdsFromA)
            .union(friendshipIdsFromB))
        friendIdsResolved = true
        resubscribeProfiles(friendUids: ids)
    }

    private func clearLoadingState() {
        isLoading = false
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
    }

    private func markProfileLoaded(uid: String) {
        pendingProfileLoads.remove(uid)
        evaluateLoadingState()
    }

    private func evaluateLoadingState() {
        guard friendIdsResolved else { return }
        if pendingProfileLoads.isEmpty {
            clearLoadingState()
        }
    }

    func stopListening() {
        activeListeningUid = nil
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
        stopRefreshTimer()
        if let friendIdsListenerKey { FirebaseListenerRegistry.shared.remove(key: friendIdsListenerKey) }
        friendIdsListener?.remove()
        friendIdsListener = nil
        friendIdsListenerKey = nil
        if let friendshipListenerAKey { FirebaseListenerRegistry.shared.remove(key: friendshipListenerAKey) }
        friendshipListenerA?.remove()
        friendshipListenerA = nil
        friendshipListenerAKey = nil
        if let friendshipListenerBKey { FirebaseListenerRegistry.shared.remove(key: friendshipListenerBKey) }
        friendshipListenerB?.remove()
        friendshipListenerB = nil
        friendshipListenerBKey = nil
        if let requestsListenerKey { FirebaseListenerRegistry.shared.remove(key: requestsListenerKey) }
        requestsListener?.remove()
        requestsListener = nil
        requestsListenerKey = nil
        if let myProfileListenerKey { FirebaseListenerRegistry.shared.remove(key: myProfileListenerKey) }
        myProfileListener?.remove()
        myProfileListener = nil
        myProfileListenerKey = nil
        for key in profileListenerKeys.values { FirebaseListenerRegistry.shared.remove(key: key) }
        profileListeners.values.forEach { $0.remove() }
        profileListeners.removeAll()
        profileListenerKeys.removeAll()
        for key in weeklyStatsListenerKeys.values { FirebaseListenerRegistry.shared.remove(key: key) }
        weeklyStatsListeners.values.forEach { $0.remove() }
        weeklyStatsListeners.removeAll()
        weeklyStatsListenerKeys.removeAll()
        friendWeeklyStatsCache.removeAll()
        publicProfileRawCache.removeAll()
        friends = []
        pendingRequests = []
        myFriendCode = nil
        isLoading = false
        errorMessage = nil
        friendAddedAtMap.removeAll()
        pendingProfileLoads.removeAll()
        friendIdsResolved = false
        legacyFriendIds = []
        friendshipIdsFromA = []
        friendshipIdsFromB = []
    }

    /// Friend codes are 2 uppercase letters + 4 digits, picked from sets that
    /// avoid visually ambiguous characters (no I, L, O, 0, 1).
    static func generateFriendCode() -> String {
        let letters: [Character] = Array("ABCDEFGHJKMNPQRSTUVWXYZ")
        let digits: [Character] = Array("23456789")
        let l1 = letters.randomElement() ?? "A"
        let l2 = letters.randomElement() ?? "A"
        var code = "\(l1)\(l2)"
        for _ in 0..<4 {
            code.append(digits.randomElement() ?? "2")
        }
        return code
    }

    /// Reads the current user's doc and stamps a `friendCode` if one isn't set yet.
    /// Idempotent — existing codes are left untouched.
    func ensureFriendCode(uid: String) async {
        let ref = db.collection("users").document(uid)
        do {
            let snapshot = try await ref.getDocument()
            // Check the user is still signed in as the same UID before writing back.
            guard await MainActor.run(body: { self.activeListeningUid == uid }) else { return }
            if let existing = snapshot.data()?["friendCode"] as? String, !existing.isEmpty {
                await MainActor.run { self.myFriendCode = existing }
                return
            }
            let newCode = Self.generateFriendCode()
            try await ref.setData([
                "friendCode": newCode,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            await MainActor.run {
                guard self.activeListeningUid == uid else { return }
                self.myFriendCode = newCode
            }
        } catch {
            await MainActor.run {
                guard self.activeListeningUid == uid else { return }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func sendFriendRequest(toCode rawCode: String, myUid: String, myName: String) async throws {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count >= 4 else {
            throw FriendsError.invalidCode
        }
        if let mine = myFriendCode, mine == code {
            throw FriendsError.cannotAddSelf
        }

        let snapshot = try await db.collection("users")
            .whereField("friendCode", isEqualTo: code)
            .limit(to: 1)
            .getDocuments(source: .server)

        guard let targetDoc = snapshot.documents.first else {
            throw FriendsError.userNotFound
        }
        let targetUid = targetDoc.documentID
        if targetUid == myUid {
            throw FriendsError.cannotAddSelf
        }

        // Bail early if already friends — gives a clear error instead of a
        // silent Firestore permission failure.
        if FirebaseMigrationFlags.useFriendshipsCollection {
            let pairId = FriendshipPairId.make(myUid, targetUid)
            let friendshipSnap = try await db.collection("friendships").document(pairId)
                .getDocument(source: .server)
            if friendshipSnap.exists {
                throw FriendsError.alreadyFriends
            }
        } else {
            let existingFriendSnap = try await db.collection("users")
                .document(myUid).collection("friends").document(targetUid)
                .getDocument(source: .server)
            if existingFriendSnap.exists {
                throw FriendsError.alreadyFriends
            }
        }

        // Honor the recipient's privacy flag. Defaults to `true` when the
        // field is missing (older clients), which matches the rule defaults.
        let targetData = targetDoc.data()
        let accepts = (targetData["acceptInvites"] as? Bool) ?? true
        guard accepts else {
            throw FriendsError.invitesDisabled
        }

        try await db.collection("users").document(targetUid)
            .collection("friendRequests").document(myUid)
            .setData([
                "fromUid": myUid,
                "fromName": myName,
                "sentAt": FieldValue.serverTimestamp()
            ])
    }

    func acceptRequest(fromUid: String, myUid: String) async throws {
        let batch = db.batch()
        let myFriendRef = db.collection("users").document(myUid).collection("friends").document(fromUid)
        let theirFriendRef = db.collection("users").document(fromUid).collection("friends").document(myUid)
        let requestRef = db.collection("users").document(myUid).collection("friendRequests").document(fromUid)
        let theirOutgoingRef = db.collection("users").document(fromUid)
            .collection("friendRequests").document(myUid)

        batch.setData(["friendUid": fromUid, "addedAt": FieldValue.serverTimestamp()], forDocument: myFriendRef)
        batch.setData(["friendUid": myUid, "addedAt": FieldValue.serverTimestamp()], forDocument: theirFriendRef)
        batch.deleteDocument(requestRef)
        batch.deleteDocument(theirOutgoingRef)

        if FirebaseMigrationFlags.useFriendshipsCollection {
            let pairId = FriendshipPairId.make(myUid, fromUid)
            let sorted = [myUid, fromUid].sorted()
            let friendshipRef = db.collection("friendships").document(pairId)
            batch.setData([
                "userA": sorted[0],
                "userB": sorted[1],
                "createdAt": FieldValue.serverTimestamp(),
                "createdBy": myUid
            ], forDocument: friendshipRef)
        }

        try await batch.commit()
    }

    func declineRequest(fromUid: String, myUid: String) async throws {
        try await db.collection("users").document(myUid)
            .collection("friendRequests").document(fromUid)
            .delete()
    }

    /// Removes a friend link from both users' friend lists and clears any
    /// stale incoming friend-request on this user's account.
    func removeFriend(friendUid: String, myUid: String) async throws {
        let batch = db.batch()
        batch.deleteDocument(db.collection("users").document(myUid).collection("friends").document(friendUid))
        batch.deleteDocument(db.collection("users").document(friendUid).collection("friends").document(myUid))
        batch.deleteDocument(db.collection("users").document(myUid).collection("friendRequests").document(friendUid))
        batch.deleteDocument(db.collection("users").document(friendUid).collection("friendRequests").document(myUid))

        if FirebaseMigrationFlags.useFriendshipsCollection {
            let pairId = FriendshipPairId.make(myUid, friendUid)
            batch.deleteDocument(db.collection("friendships").document(pairId))
        }

        try await batch.commit()
    }

    /// One-shot server fetch for a friend profile — used when the friends
    /// list listener hasn't populated yet (e.g. profile opened from activity).
    func fetchProfileDirectly(uid: String) async {
        let usePublic = FirebaseMigrationFlags.usePublicProfilesForFriends
        do {
            let collectionPath = usePublic ? "publicProfiles" : "users"
            let snapshot = try await db.collection(collectionPath).document(uid)
                .getDocument(source: .server)
            if usePublic {
                mergePublicProfile(uid: uid, data: snapshot.data())
            } else {
                mergeProfile(uid: uid, data: snapshot.data())
            }
        } catch {
            errorMessage = "Couldn't load this profile. Pull to refresh and try again."
        }
    }

    // MARK: - Private

    private func startRefreshTimer() {
        stopRefreshTimer()
        // Poll every 10 s so friend stats stay fresh even when the Firestore
        // WebSocket listener misses a push (common in simulators / VPNs).
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshFriendProfiles()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func startLoadingTimeout() {
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.isLoading {
                self.clearLoadingState()
                if self.errorMessage == nil {
                    self.errorMessage = "Friends took too long to load. Pull to refresh."
                }
            }
        }
    }

    private func resubscribeProfiles(friendUids ids: [String]) {
        let current = Set(profileListeners.keys)
        let wanted = Set(ids)

        for removed in current.subtracting(wanted) {
            if let key = profileListenerKeys[removed] {
                FirebaseListenerRegistry.shared.remove(key: key)
            }
            profileListeners[removed]?.remove()
            profileListeners.removeValue(forKey: removed)
            profileListenerKeys.removeValue(forKey: removed)
            if let wKey = weeklyStatsListenerKeys[removed] {
                FirebaseListenerRegistry.shared.remove(key: wKey)
            }
            weeklyStatsListeners[removed]?.remove()
            weeklyStatsListeners.removeValue(forKey: removed)
            weeklyStatsListenerKeys.removeValue(forKey: removed)
            friendWeeklyStatsCache.removeValue(forKey: removed)
            friendAddedAtMap.removeValue(forKey: removed)
        }

        pendingProfileLoads = wanted

        for uid in wanted {
            if profileListeners[uid] == nil {
                subscribeProfileListener(friendUid: uid)
            } else {
                pendingProfileLoads.remove(uid)
            }
        }

        friends = friends.filter { wanted.contains($0.uid) }
        if wanted.isEmpty {
            friends = []
            evaluateLoadingState()
        }
    }

    private func subscribeProfileListener(friendUid uid: String) {
        let usePublic = FirebaseMigrationFlags.usePublicProfilesForFriends
        let collectionPath = usePublic ? "publicProfiles" : "users"

        let registration = db.collection(collectionPath).document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.profileListeners[uid] != nil else { return }
                    if let error {
                        FirestoreOperationLog.listenerError(
                            owner: .friendsService,
                            purpose: usePublic ? "publicProfile" : "userProfile",
                            uid: uid,
                            error: error
                        )
                        self.markProfileLoaded(uid: uid)
                        return
                    }
                    if usePublic {
                        self.mergePublicProfile(uid: uid, data: snapshot?.data())
                    } else {
                        self.mergeProfile(uid: uid, data: snapshot?.data())
                    }
                    self.markProfileLoaded(uid: uid)
                }
            }
        profileListeners[uid] = registration
        profileListenerKeys[uid] = FirebaseListenerRegistry.shared.register(
            owner: .friendsService,
            purpose: usePublic ? "publicProfile" : "userProfile",
            uid: uid,
            registration: registration
        )

        if usePublic {
            let weeklyReg = db.collection("publicProfiles").document(uid)
                .collection("stats").document("currentWeek")
                .addSnapshotListener { [weak self] snapshot, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.friendWeeklyStatsCache[uid] = snapshot?.data()
                        self.mergePublicProfile(uid: uid, data: self.publicProfileRawCache[uid])
                    }
                }
            weeklyStatsListeners[uid] = weeklyReg
            weeklyStatsListenerKeys[uid] = FirebaseListenerRegistry.shared.register(
                owner: .friendsService,
                purpose: "publicProfile.weeklyStats",
                uid: uid,
                registration: weeklyReg
            )
        }
    }

    private var publicProfileRawCache: [String: [String: Any]] = [:]

    /// One-shot refresh of every subscribed friend profile — use after Activity
    /// or when Firestore snapshot data may lag behind activity events.
    func refreshFriendProfiles() async {
        let uids = Array(profileListeners.keys)
        guard !uids.isEmpty else { return }
        let usePublic = FirebaseMigrationFlags.usePublicProfilesForFriends
        await withTaskGroup(of: Void.self) { group in
            for uid in uids {
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        let collectionPath = usePublic ? "publicProfiles" : "users"
                        let snapshot = try await self.db.collection(collectionPath).document(uid)
                            .getDocument(source: .server)
                        await MainActor.run {
                            if usePublic {
                                self.mergePublicProfile(uid: uid, data: snapshot.data())
                            } else {
                                self.mergeProfile(uid: uid, data: snapshot.data())
                            }
                        }
                    } catch {
                        // Server fetch failed — fall back to cache silently.
                    }
                }
            }
        }
    }

    private func mergePublicProfile(uid: String, data: [String: Any]?) {
        guard let data else {
            publicProfileRawCache.removeValue(forKey: uid)
            friends.removeAll { $0.uid == uid }
            return
        }
        publicProfileRawCache[uid] = data
        var merged = data
        if let weekly = friendWeeklyStatsCache[uid] {
            merged["weeklyHours"] = weekly["hours"]
            merged["weeklyShiftsLogged"] = weekly["shifts"]
            merged["weeklyDaysLogged"] = weekly["daysWorked"]
            merged["currentStreak"] = weekly["currentStreak"]
        }
        mergeProfile(uid: uid, data: merged)
    }

    private func mergeProfile(uid: String, data: [String: Any]?) {
        guard let data else {
            friends.removeAll { $0.uid == uid }
            return
        }
        let privacy = SocialPrivacyFlags.from(firestore: data["privacy"] as? [String: Any])
        let prestige = firestoreInt(data, key: "prestige", default: 0)
        let snapshots = firestoreIntArray(data, key: "prestigeXPSnapshots")
        let storedLevel = firestoreInt(data, key: "level", default: 1)
        let totalXP = firestoreOptionalInt(data, key: "totalXP")
        // `adminLevel` is a Firestore-only floor never written by the client.
        // Use whichever is higher — the override or the XP-calculated value —
        // so natural progression still advances past the override once XP catches up.
        let adminLevel = firestoreOptionalInt(data, key: "adminLevel")
        let xpLevel = GamificationLevelCalculator.displayLevel(
            totalXP: totalXP,
            storedLevel: storedLevel,
            prestige: prestige,
            snapshots: snapshots
        )
        let level = max(adminLevel ?? 0, xpLevel)
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        let unlockedBadgeSummaries: [SharedBadgeSummary] = {
            guard let arr = data["unlockedBadgeSummaries"] as? [[String: Any]] else { return [] }
            return arr.compactMap { dict in
                guard let name = dict["name"] as? String,
                      let icon = dict["icon"] as? String else { return nil }
                let detail = dict["detail"] as? String ?? ""
                let isLegend = dict["isLegend"] as? Bool ?? false
                let order: Int = {
                    if let v = dict["order"] as? Int { return v }
                    if let v = dict["order"] as? Int64 { return Int(v) }
                    if let v = dict["order"] as? NSNumber { return v.intValue }
                    return 0
                }()
                return SharedBadgeSummary(
                    icon: icon,
                    name: name,
                    detail: detail,
                    isLegend: isLegend,
                    order: order
                )
            }
            .sorted { $0.order < $1.order }
        }()
        let chequeDailySummary: [FriendDailyEntry] = {
            guard let arr = data["chequeDailySummary"] as? [[String: Any]] else { return [] }
            return arr.compactMap { dict in
                guard let date = dict["date"] as? String else { return nil }
                let hours: Double = {
                    if let v = dict["hours"] as? Double { return v }
                    if let v = dict["hours"] as? Int { return Double(v) }
                    if let v = dict["hours"] as? NSNumber { return v.doubleValue }
                    return 0
                }()
                let shifts: Int = {
                    if let v = dict["shifts"] as? Int { return v }
                    if let v = dict["shifts"] as? Int64 { return Int(v) }
                    if let v = dict["shifts"] as? NSNumber { return v.intValue }
                    return hours > 0 ? 1 : 0
                }()
                return FriendDailyEntry(date: date, hours: hours, shifts: shifts)
            }
        }()
        let profile = FriendProfile(
            uid: uid,
            displayName: data["displayName"] as? String ?? "Friend",
            level: level,
            prestige: prestige,
            currentStreak: firestoreInt(data, key: "currentStreak", default: 0),
            bestStreak: firestoreInt(data, key: "bestStreak", default: 0),
            totalHours: firestoreDouble(data, key: "totalHours"),
            chequeHours: firestoreDouble(data, key: "chequeHours"),
            weeklyHours: firestoreDouble(data, key: "weeklyHours"),
            weeklyShiftsLogged: firestoreInt(data, key: "weeklyShiftsLogged", default: 0),
            weeklyDaysLogged: firestoreInt(data, key: "weeklyDaysLogged", default: 0),
            badgeCount: firestoreInt(data, key: "badgeCount", default: 0),
            unlockedBadgeSummaries: unlockedBadgeSummaries,
            equippedTitle: {
                let admin = (data["adminEquippedTitle"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !admin.isEmpty { return admin }
                return data["equippedTitle"] as? String ?? ""
            }(),
            profilePhotoURL: data["profilePhotoURL"] as? String,
            companyName: data["companyName"] as? String ?? "",
            companyOccupation: data["companyOccupation"] as? String ?? "",
            companyStartDate: (data["companyStartDate"] as? Timestamp)?.dateValue(),
            companyHoursLogged: firestoreDouble(data, key: "companyHoursLogged"),
            companyDaysWorked: firestoreInt(data, key: "companyDaysWorked", default: 0),
            updatedAt: updatedAt,
            friendsSince: friendAddedAtMap[uid],
            chequeDailySummary: chequeDailySummary,
            chequeWindowStart: data["chequeWindowStart"] as? String ?? "",
            chequeWindowCutoff: data["chequeWindowCutoff"] as? String ?? "",
            privacy: privacy
        )
        if let idx = friends.firstIndex(where: { $0.uid == uid }) {
            friends[idx] = profile
        } else {
            friends.append(profile)
        }
        // Sort most-recently-active first; fall back to name for stable ordering.
        friends.sort {
            switch ($0.updatedAt, $1.updatedAt) {
            case let (l?, r?): return l > r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none):
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    private func firestoreDouble(_ data: [String: Any], key: String) -> Double {
        if let value = data[key] as? Double { return value }
        if let value = data[key] as? Int { return Double(value) }
        if let value = data[key] as? Int64 { return Double(value) }
        if let value = data[key] as? NSNumber { return value.doubleValue }
        return 0
    }

    private func firestoreInt(_ data: [String: Any], key: String, default defaultValue: Int) -> Int {
        if let value = data[key] as? Int { return value }
        if let value = data[key] as? Int64 { return Int(value) }
        if let value = data[key] as? Double { return Int(value) }
        if let value = data[key] as? NSNumber { return value.intValue }
        return defaultValue
    }

    private func firestoreOptionalInt(_ data: [String: Any], key: String) -> Int? {
        if data[key] == nil { return nil }
        if let value = data[key] as? Int { return value }
        if let value = data[key] as? Int64 { return Int(value) }
        if let value = data[key] as? Double { return Int(value) }
        if let value = data[key] as? NSNumber { return value.intValue }
        return nil
    }

    /// Firestore often returns integer arrays as `[Int64]` or `[NSNumber]`, not `[Int]`.
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
}

enum FriendsError: LocalizedError {
    case invalidCode
    case userNotFound
    case cannotAddSelf
    case invitesDisabled
    case alreadyFriends

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "Enter a valid friend code."
        case .userNotFound: return "No one found with that code. Double-check it and try again."
        case .cannotAddSelf: return "You can't add yourself as a friend."
        case .invitesDisabled: return "This user isn't accepting friend invites right now."
        case .alreadyFriends: return "You're already friends with this person."
        }
    }
}
