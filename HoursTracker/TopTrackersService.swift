import Foundation
import FirebaseFirestore
import Combine
import SwiftUI
import os

/// A single ranked entry on the global hour trackers leaderboard.
/// Only a first name, lifetime hours, and country flag are ever exposed publicly.
struct TopTracker: Identifiable, Equatable {
    let uid: String
    let name: String
    let hours: Double
    let countryCode: String
    let rank: Int

    var id: String { uid }
}

/// Converts an ISO 3166-1 alpha-2 country code (e.g. "US") to its flag emoji,
/// and reads the device's own region for sharing in the user's own profile.
enum CountryFlag {
    static let storageKey = "profile_country_code"
    static let skippedPromptKey = "country_flag_prompt_skipped"

    static var storedCode: String {
        get { UserDefaults.standard.string(forKey: storageKey) ?? "" }
        set { UserDefaults.standard.set(newValue.uppercased(), forKey: storageKey) }
    }

    static var skippedPrompt: Bool {
        get { UserDefaults.standard.bool(forKey: skippedPromptKey) }
        set { UserDefaults.standard.set(newValue, forKey: skippedPromptKey) }
    }

    /// True when the user has never picked a country in the flag picker.
    static var hasChosenCountry: Bool {
        !storedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Show the home-screen nudge until they pick a country or tap Not now.
    static var needsCountryPrompt: Bool {
        !hasChosenCountry && !skippedPrompt
    }

    static func markPromptSkipped() {
        skippedPrompt = true
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
        allTrackers = Self.parsePublicProfileDocuments(documents)
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
            rank += 1
            let displayName = (data["displayName"] as? String) ?? ""
            let name = firstNameOnly(displayName)
            let countryCode = (data["countryCode"] as? String) ?? ""
            return TopTracker(
                uid: doc.documentID,
                name: name.isEmpty ? "Tracker" : name,
                hours: hours,
                countryCode: countryCode,
                rank: rank
            )
        }
    }

    private static func firstNameOnly(_ displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: " ").first else { return trimmed }
        return String(first)
    }

}

// MARK: - Global leaderboard (full list)

struct GlobalLeaderboardView: View {
    @ObservedObject private var topTrackers = TopTrackersService.shared
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    private var myTracker: TopTracker? {
        topTrackers.tracker(for: authService.user?.uid)
    }

    var body: some View {
        NavigationStack {
            Group {
                if topTrackers.isLoadingFull && topTrackers.allTrackers.isEmpty {
                    ProgressView("Loading rankings…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if topTrackers.allTrackers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.faint)
                        Text("No rankings yet")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.subtext)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            summaryHeader

                            VStack(spacing: 0) {
                                ForEach(topTrackers.allTrackers) { tracker in
                                    leaderboardRow(tracker)
                                    if tracker.id != topTrackers.allTrackers.last?.id {
                                        Divider()
                                            .overlay(AppTheme.Colors.stroke)
                                            .padding(.leading, 52)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(AppTheme.Colors.card.opacity(0.55))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("Global leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await topTrackers.ensureFullLeaderboardLoaded()
            }
        }
    }

    private var summaryHeader: some View {
        VStack(spacing: 12) {
            Text("YOUR RANK")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(AppTheme.Colors.subtext)

            Text(myTracker.map { "#\($0.rank)" } ?? "—")
                .font(AppDesignSystem.Typography.heroNumerals(size: 44, weight: .heavy))
                .foregroundStyle(AppTheme.Colors.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(
                myTracker.map { "\(hoursLabel($0.hours)) · of \(topTrackers.allTrackers.count) trackers ranked" }
                    ?? "\(topTrackers.allTrackers.count) trackers ranked"
            )
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.faint)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.Colors.card2)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.Colors.accent.opacity(0.14),
                                Color.clear,
                                AppTheme.Colors.accent.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            AppTheme.Colors.accent.opacity(0.4),
                            AppTheme.Colors.accent.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: AppTheme.Colors.accent.opacity(0.18), radius: 18, y: 8)
    }

    private func leaderboardRow(_ tracker: TopTracker) -> some View {
        let isMe = tracker.uid == authService.user?.uid
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rankColor(tracker.rank).opacity(tracker.rank <= 3 ? 0.22 : 0.12))
                    .frame(width: 28, height: 28)
                Text("\(tracker.rank)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(rankColor(tracker.rank))
            }

            HStack(spacing: 5) {
                Text(tracker.name)
                    .font(.system(size: 15, weight: tracker.rank <= 3 || isMe ? .semibold : .medium))
                    .foregroundStyle(AppTheme.Colors.text)
                    .lineLimit(1)
                if let flag = CountryFlag.emoji(
                    for: CountryFlag.leaderboardCode(
                        trackerUid: tracker.uid,
                        serverCode: tracker.countryCode,
                        currentUid: authService.user?.uid
                    )
                ) {
                    Text(flag)
                        .font(.system(size: 15))
                }
                if isMe {
                    Text("You")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppTheme.Colors.accent.opacity(0.14))
                        )
                }
            }

            Spacer()

            Text(hoursLabel(tracker.hours))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isMe ? AppTheme.Colors.text : AppTheme.Colors.subtext)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isMe ? AppTheme.Colors.accent.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 0.98, green: 0.79, blue: 0.28)
        case 2: return Color(red: 0.75, green: 0.79, blue: 0.85)
        case 3: return Color(red: 0.83, green: 0.55, blue: 0.35)
        default: return AppTheme.Colors.accent
        }
    }

    private func hoursLabel(_ hours: Double) -> String {
        if hours >= 1000 {
            return String(format: "%.0fh", hours)
        }
        return String(format: "%.1fh", hours)
    }
}

// MARK: - Country flag picker

struct CountryFlagPickerView: View {
    @ObservedObject var store: HoursStore
    var onSelected: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var selectedCode: String {
        CountryFlag.resolvedCode
    }

    private var filteredRegions: [(code: String, name: String)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return CountryFlag.selectableRegions }
        return CountryFlag.selectableRegions.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.code.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            ForEach(filteredRegions, id: \.code) { region in
                Button {
                    guard region.code != CountryFlag.storedCode else { return }
                    Haptics.lightTap()
                    CountryFlag.storedCode = region.code
                    store.syncProfileSnapshotToCloud()
                    onSelected?()
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        if let flag = CountryFlag.emoji(for: region.code) {
                            Text(flag)
                                .font(.system(size: 22))
                        }
                        Text(region.name)
                            .foregroundStyle(AppTheme.Colors.text)
                        Spacer()
                        if region.code == selectedCode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.accent)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search countries")
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Country flag")
        .navigationBarTitleDisplayMode(.inline)
    }
}
