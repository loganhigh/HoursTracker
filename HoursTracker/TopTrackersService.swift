import Foundation
import FirebaseFirestore
import Combine
import SwiftUI
import os

/// A single ranked entry on the global hour trackers leaderboard.
/// Only a first name, lifetime hours, country flag, and the progression figures
/// the profile already publishes (photo, level, prestige, streak) are exposed.
struct TopTracker: Identifiable, Equatable {
    let uid: String
    let name: String
    let hours: Double
    let countryCode: String
    let rank: Int
    /// Defaulted so older profile docs — written before these fields existed —
    /// still rank rather than dropping off the board.
    var photoURL: String? = nil
    var level: Int = 0
    var prestige: Int = 0
    var streak: Int = 0
    /// Earns the verified badge. Defaulted false for profiles published
    /// before the flag existed.
    var hasReviewedApp: Bool = false

    var id: String { uid }

    /// "Level 16" / "Level 14 • P1". Empty when the profile predates levels,
    /// so the row collapses to just a name instead of reading "Level 0".
    var levelLine: String {
        guard level > 0 else { return "" }
        return prestige > 0 ? "Level \(level) • P\(prestige)" : "Level \(level)"
    }
}

/// Converts an ISO 3166-1 alpha-2 country code (e.g. "US") to its flag emoji,
/// and reads the device's own region for sharing in the user's own profile.
enum CountryFlag {
    static let storageKey = "profile_country_code"

    static var storedCode: String {
        get { UserDefaults.standard.string(forKey: storageKey) ?? "" }
        set { UserDefaults.standard.set(newValue.uppercased(), forKey: storageKey) }
    }

    /// True when the user has never picked a country in the flag picker.
    static var hasChosenCountry: Bool {
        !storedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Picking a country is required — the prompt shows until they do.
    /// (Previously it could also be dismissed with "Not now", which set
    /// `country_flag_prompt_skipped`; that key is no longer read, so users
    /// who skipped back then are prompted once more.)
    static var needsCountryPrompt: Bool {
        !hasChosenCountry
    }

    /// Country code used for cloud sync and the public leaderboard.
    static var resolvedCode: String {
        let stored = storedCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if emoji(for: stored) != nil { return stored }
        return currentDeviceCode
    }

    /// Country code shown on the global leaderboard for a row.
    static func leaderboardCode(trackerUid: String, serverCode: String, currentUid: String?) -> String {
        if trackerUid == currentUid, hasChosenCountry {
            return resolvedCode
        }
        return serverCode
    }

    static func emoji(for code: String) -> String? {
        let upper = code.uppercased()
        guard upper.count == 2, upper.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.uppercaseLetters.contains($0) }) else {
            return nil
        }
        let base: UInt32 = 127397 // regional indicator offset: 0x1F1E6 - "A"
        var scalarView = String.UnicodeScalarView()
        for scalar in upper.unicodeScalars {
            guard let flagScalar = Unicode.Scalar(base + scalar.value) else { return nil }
            scalarView.append(flagScalar)
        }
        return String(scalarView)
    }

    /// The device's current region as an ISO 3166-1 alpha-2 code, if available.
    static var currentDeviceCode: String {
        if let region = Locale.current.region?.identifier, region.count == 2 {
            return region.uppercased()
        }
        if let legacy = (Locale.current as NSLocale).object(forKey: .countryCode) as? String,
           legacy.count == 2 {
            return legacy.uppercased()
        }
        return ""
    }

    static var selectableRegions: [(code: String, name: String)] {
        Locale.Region.isoRegions.compactMap { region -> (code: String, name: String)? in
            let code = region.identifier.uppercased()
            guard code.count == 2, emoji(for: code) != nil else { return nil }
            let name = Locale.current.localizedString(forRegionCode: code) ?? code
            return (code, name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Publishes ranked hour trackers to every signed-in user by listening to the
/// top slice of `publicProfiles` ordered by lifetime hours. The query IS the
/// leaderboard: rank = position, so the board can never disagree with the
/// profiles that feed it. (The old server-materialized `leaderboards/global`
/// doc is still published for pre-2.3 builds but is no longer read here — it
/// required a delta patcher, a fence gate, and a 15-minute reconciler purely
/// to keep a copy in sync with this exact query.)
@MainActor
final class TopTrackersService: ObservableObject {
    static let shared = TopTrackersService()

    /// Broadcast slice mirrored from the retired board doc's rank cap.
    private static let liveRankLimit = 100

    @Published private(set) var topTrackers: [TopTracker] = []
    @Published private(set) var allTrackers: [TopTracker] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoadingFull = false

    /// Rank deltas from the most recent live snapshot (uid → places gained,
    /// negative = dropped). Only ever set from genuine reorderings of the
    /// authoritative query — the first snapshot is baseline, never movement —
    /// and cleared a beat later so the ↑/↓ chips are transient by design.
    @Published private(set) var movements: [String: Int] = [:]
    /// Bumped once per movement batch, so views can hook haptics/banners to
    /// "a new batch landed" without diffing the dictionary themselves.
    @Published private(set) var movementToken = 0

    private var movementClearTask: Task<Void, Never>?

    private let db = Firestore.firestore()
    private var listenerKey: String?
    private var isListening = false
    private var hasServerFullList = false
    private var isFetchingFull = false

    private init() {}

    func startListening() {
        guard !isListening else { return }
        isListening = true
        listenerKey = FirebaseListenerRegistry.shared.register(
            owner: .leaderboard,
            purpose: "publicProfiles.topByHours",
            uid: nil,
            registration: db.collection("publicProfiles")
                .order(by: "totalHours", descending: true)
                .limit(to: Self.liveRankLimit)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            FirestoreOperationLog.listenerError(
                                owner: .leaderboard,
                                purpose: "publicProfiles.topByHours",
                                uid: nil,
                                error: error
                            )
                            return
                        }
                        self.applyRankedProfiles(snapshot)
                        self.hasLoaded = true
                    }
                }
        )
    }

    /// Rank deltas between two orderings, keyed by uid. Pure so the initial-
    /// load and reorder behaviors are unit-testable. Entrants absent from
    /// `previous` produce no movement — appearing isn't the same as climbing.
    nonisolated static func rankMovements(previous: [TopTracker], current: [TopTracker]) -> [String: Int] {
        guard !previous.isEmpty else { return [:] }
        let oldRank = Dictionary(uniqueKeysWithValues: previous.map { ($0.uid, $0.rank) })
        var moves: [String: Int] = [:]
        for tracker in current {
            guard let was = oldRank[tracker.uid], was != tracker.rank else { continue }
            moves[tracker.uid] = was - tracker.rank // positive = climbed
        }
        return moves
    }

    /// Chips and highlights are transient: visible long enough to read
    /// (~2.6s), then gone, leaving the plain board. A newer batch restarts
    /// the clock rather than being cut short by the older batch's clear.
    private func scheduleMovementClear() {
        movementClearTask?.cancel()
        movementClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.5)) {
                    self?.movements = [:]
                }
            }
        }
    }

    func stopListening() {
        if let listenerKey { FirebaseListenerRegistry.shared.remove(key: listenerKey) }
        listenerKey = nil
        isListening = false
        topTrackers = []
        allTrackers = []
        hasLoaded = false
        hasServerFullList = false
        isFetchingFull = false
        isLoadingFull = false
        movementClearTask?.cancel()
        movements = [:]
    }

    /// Loads the full global rankings when the server doc has not been backfilled yet.
    func ensureFullLeaderboardLoaded() async {
        guard !hasServerFullList, !isFetchingFull else { return }
        isFetchingFull = true
        isLoadingFull = true
        defer {
            isFetchingFull = false
            isLoadingFull = false
        }

        do {
            let snap = try await db.collection("publicProfiles")
                .order(by: "totalHours", descending: true)
                .limit(to: 500)
                .getDocuments()
            allTrackers = Self.parsePublicProfileDocuments(snap.documents)
        } catch {
            FirestoreOperationLog.listenerError(
                owner: .leaderboard,
                purpose: "publicProfiles.globalLeaderboard",
                uid: nil,
                error: error
            )
        }
    }

    func tracker(for uid: String?) -> TopTracker? {
        guard let uid else { return nil }
        return allTrackers.first { $0.uid == uid }
    }

    private func applyRankedProfiles(_ snapshot: QuerySnapshot?) {
        let previousAllCount = allTrackers.count
        let documents = snapshot?.documents ?? []
        let parsed = Self.parsePublicProfileDocuments(documents)

        // Cache replays on listener attach look like fresh data but are just
        // the baseline coming back — movement only ever comes from a live,
        // server-confirmed reordering of an already-loaded board.
        let fromCache = snapshot?.metadata.isFromCache == true
        let moves = (hasLoaded && !fromCache)
            ? Self.rankMovements(previous: allTrackers, current: parsed)
            : [:]

        if moves.isEmpty {
            allTrackers = parsed
        } else {
            // One coordinated transaction: every affected row slides to its
            // new position together under the same spring.
            withAnimation(AppMotion.Spring.podium) {
                allTrackers = parsed
            }
            movements = moves
            movementToken &+= 1
            scheduleMovementClear()
        }
        topTrackers = Array(allTrackers.prefix(5))
        // Fewer raw documents than the query limit means the query exhausted
        // publicProfiles — the live slice already holds every ranked user, so
        // ensureFullLeaderboardLoaded() has nothing deeper to page in.
        hasServerFullList = documents.count < Self.liveRankLimit
        AppLogger.leaderboard.info("publicProfiles leaderboard snapshot: ranked \(previousAllCount, privacy: .public) -> \(self.allTrackers.count, privacy: .public), leader hours \(String(format: "%.2f", self.topTrackers.first?.hours ?? 0), privacy: .public) (fromCache: \(snapshot?.metadata.isFromCache == true, privacy: .public))")
    }

    private static func parsePublicProfileDocuments(_ documents: [QueryDocumentSnapshot]) -> [TopTracker] {
        var rank = 0
        return documents.compactMap { doc in
            let data = doc.data()
            let hours: Double = {
                if let v = data["totalHours"] as? Double { return v }
                if let v = data["totalHours"] as? Int { return Double(v) }
                if let v = data["totalHours"] as? NSNumber { return v.doubleValue }
                return 0
            }()
            guard hours > 0 else { return nil }
            // Mirrors the server's rebuild filter. This paged query is the
            // fallback for rankings deeper than the broadcast doc carries, so
            // without it an opted-out user would be absent from the visible
            // board but reappear once the list paged past the cutoff. Absent
            // means true, matching profiles written before the flag existed.
            guard data["showOnGlobalLeaderboard"] as? Bool ?? true else { return nil }
            rank += 1
            let displayName = (data["displayName"] as? String) ?? ""
            let name = firstNameOnly(displayName)
            let countryCode = (data["countryCode"] as? String) ?? ""
            let photo = (data["profilePhotoURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return TopTracker(
                uid: doc.documentID,
                name: name.isEmpty ? "Tracker" : name,
                hours: hours,
                countryCode: countryCode,
                rank: rank,
                photoURL: (photo?.isEmpty ?? true) ? nil : photo,
                level: intValue(data["level"]),
                prestige: intValue(data["prestige"]),
                streak: intValue(data["currentStreak"]),
                hasReviewedApp: data["hasReviewedApp"] as? Bool ?? false
            )
        }
    }

    /// Firestore hands numbers back as Int, Double, or NSNumber depending on how
    /// they were written; normalize rather than guessing one type.
    private static func intValue(_ raw: Any?) -> Int {
        if let v = raw as? Int { return v }
        if let v = raw as? Double { return Int(v) }
        if let v = raw as? NSNumber { return v.intValue }
        return 0
    }

    private static func firstNameOnly(_ displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: " ").first else { return trimmed }
        return String(first)
    }

}
