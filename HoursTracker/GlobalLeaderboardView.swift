import SwiftUI

// MARK: - Global leaderboard (full list)
//
// Composes the board: a custom header (the system nav bar is hidden so the
// title can carry the screen), a hero rank card with the viewer's standing, a
// global stats strip, a 2–1–3 podium for the top three, and the ranked list
// below it. Section views live in GlobalLeaderboardSections.swift and
// GlobalPodiumSections.swift. All data comes from TopTrackersService.

struct GlobalLeaderboardView: View {
    @ObservedObject private var topTrackers = TopTrackersService.shared
    @ObservedObject private var presence = PresenceService.shared
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var verified = VerifiedStatusService.shared

    @State private var showingProofSheet = false

    /// Own row's vertical position in screen space — nil while unknown. Drives
    /// the "you moved" banner only when the row can't currently be seen.
    @State private var ownRowY: CGFloat?
    @State private var movementBanner: String?

    /// Temporary display order for the missed-climb replay: the board renders
    /// with the viewer's row back at its last-seen position, then springs to
    /// the real order so they get to watch themselves move up. nil = live
    /// order.
    @State private var replayTrackers: [TopTracker]?
    @State private var didAttemptReplay = false

    private var myUid: String? { authService.user?.uid }

    private var myTracker: TopTracker? {
        topTrackers.tracker(for: myUid)
    }

    private var displayTrackers: [TopTracker] {
        replayTrackers ?? topTrackers.allTrackers
    }

    /// The podium only earns its space with a full top three; below that every
    /// tracker stays in the list.
    private var showsPodium: Bool { displayTrackers.count >= 3 }

    private var listTrackers: [TopTracker] {
        showsPodium ? Array(displayTrackers.dropFirst(3)) : displayTrackers
    }

    private var lastSeenRankKey: String? {
        myUid.map { "global_last_seen_rank_\($0)" }
    }

    private var totalRankedHours: Double {
        topTrackers.allTrackers.reduce(0) { $0 + $1.hours }
    }

    var body: some View {
        VStack(spacing: 0) {
            GlobalLeaderboardHeader(onBack: { dismiss() })
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)

            content
        }
        .background(AppColors.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingProofSheet) {
            VerifiedReviewProofSheet(
                isVerified: verified.isVerified,
                accountName: UserDefaults.standard.string(forKey: "profile_display_name") ?? "",
                accountUid: myUid
            )
        }
        .task {
            await topTrackers.ensureFullLeaderboardLoaded()
        }
        .task {
            // Refresh the Active Users count and the online dots while this
            // screen is up. .task cancels on disappear, so the loop dies
            // with the screen.
            while !Task.isCancelled {
                await presence.refreshActiveCount()
                await presence.refreshOnlineUids()
                try? await Task.sleep(nanoseconds: 45_000_000_000)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if topTrackers.isLoadingFull && topTrackers.allTrackers.isEmpty {
            AppLoadingState(message: "Loading rankings…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if topTrackers.allTrackers.isEmpty {
            AppEmptyState(
                icon: "chart.bar.xaxis",
                title: "No rankings yet"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    GlobalRankHeroCard(rank: myTracker?.rank)
                        .cardAppear(index: 0, group: "globalBoard")

                    VerifiedReviewNote(isVerified: verified.isVerified) {
                        showingProofSheet = true
                    }
                    .cardAppear(index: 1, group: "globalBoard")

                    GlobalStatsStrip(
                        trackerCount: topTrackers.allTrackers.count,
                        totalHours: totalRankedHours,
                        activeNow: presence.activeNowCount
                    )
                    .cardAppear(index: 2, group: "globalBoard")

                    if showsPodium {
                        GlobalPodiumRow(
                            entries: displayTrackers,
                            currentUid: myUid,
                            onlineUids: presence.onlineUids,
                            movements: topTrackers.movements
                        )
                        .padding(.top, AppSpacing.xs)
                    }

                    if !listTrackers.isEmpty {
                        rankedList
                            .cardAppear(index: 4, group: "globalBoard")
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.lg)
            }
            // A movement batch just landed. Haptics only for MY row — the
            // board animating other people's moves should stay silent — and
            // only here, while the board is actually on screen.
            .task(id: topTrackers.allTrackers.isEmpty) {
                await maybeReplayMissedClimb(proxy: proxy)
            }
            .onDisappear {
                rememberCurrentRank()
            }
            .onChange(of: topTrackers.movementToken) { _, _ in
                guard let myUid, let delta = topTrackers.movements[myUid] else { return }
                rememberCurrentRank()
                if delta > 0 { Haptics.success() } else { Haptics.mediumTap() }
                if let rank = topTrackers.tracker(for: myUid)?.rank, ownRowOffscreen {
                    withAnimation(AppMotion.Spring.snappy) {
                        movementBanner = delta > 0 ? "↑ You moved to #\(rank)" : "↓ You're now #\(rank)"
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        withAnimation(.easeOut(duration: 0.4)) { movementBanner = nil }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let movementBanner {
                    Button {
                        Haptics.lightTap()
                        if let myUid {
                            withAnimation(AppMotion.Spring.smooth) {
                                proxy.scrollTo(myUid, anchor: .center)
                            }
                        }
                        withAnimation(.easeOut(duration: 0.3)) { self.movementBanner = nil }
                    } label: {
                        Text(movementBanner)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textOnAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule(style: .continuous).fill(AppColors.accent))
                            .appShadowCard()
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, AppSpacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            }
        }
    }

    /// Replays a climb the user missed: if their rank improved since the last
    /// time they had this board open, render their row back at the old
    /// position for a beat, scroll it into view, then spring it up to the
    /// real position through the normal movement pipeline. Runs at most once
    /// per board open, and only for climbs — sliding someone DOWN as a
    /// welcome-back would just be mean.
    private func maybeReplayMissedClimb(proxy: ScrollViewProxy) async {
        guard !didAttemptReplay,
              let uid = myUid,
              let key = lastSeenRankKey,
              let my = myTracker else { return }
        didAttemptReplay = true
        let lastSeen = UserDefaults.standard.integer(forKey: key)
        defer { rememberCurrentRank() }
        guard lastSeen > 0, lastSeen > my.rank else { return }

        var reordered = topTrackers.allTrackers
        guard let idx = reordered.firstIndex(where: { $0.uid == uid }) else { return }
        let item = reordered.remove(at: idx)
        let oldIndex = min(max(lastSeen - 1, 0), reordered.count)
        reordered.insert(item, at: oldIndex)

        replayTrackers = reordered
        // Let the list build, then show the old spot so the move is watchable.
        try? await Task.sleep(nanoseconds: 350_000_000)
        proxy.scrollTo(uid, anchor: .center)
        try? await Task.sleep(nanoseconds: 900_000_000)
        withAnimation(AppMotion.Spring.podium) {
            replayTrackers = nil
        }
        topTrackers.injectReplayMovement(uid: uid, delta: lastSeen - my.rank)
    }

    /// The stored rank is "the position the user last SAW", so it updates
    /// whenever they're looking at the board — on replay, on live movement,
    /// and on leaving.
    private func rememberCurrentRank() {
        guard let key = lastSeenRankKey, let rank = myTracker?.rank else { return }
        UserDefaults.standard.set(rank, forKey: key)
    }

    /// Best-effort visibility: the row publishes its screen-space Y; if that
    /// sits outside the screen (or was never seen because LazyVStack hasn't
    /// built it), the row isn't visible.
    private var ownRowOffscreen: Bool {
        guard let ownRowY else { return true }
        return ownRowY < 0 || ownRowY > UIScreen.main.bounds.height
    }

    private var rankedList: some View {
        VStack(spacing: 0) {
            ForEach(listTrackers) { tracker in
                // Rows are display-only: nobody's profile opens from the
                // public board.
                GlobalTrackerRow(
                    tracker: tracker,
                    currentUid: myUid,
                    // Own row skips the dot — you're by definition here.
                    isOnline: tracker.uid != myUid && presence.onlineUids.contains(tracker.uid),
                    movement: topTrackers.movements[tracker.uid]
                )
                .id(tracker.uid)
                .modifier(OwnRowGeometryReporter(
                    isOwnRow: tracker.uid == myUid,
                    y: $ownRowY
                ))
                if tracker.id != listTrackers.last?.id {
                    Divider()
                        .overlay(AppColors.stroke)
                        .opacity(0.5)
                        .padding(.leading, GlobalLeaderboardMetrics.nameColumnInset)
                }
            }
        }
        .padding(AppSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 0.5)
                )
        )
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
                            .foregroundStyle(AppColors.text)
                        Spacer()
                        if region.code == selectedCode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search countries")
        .scrollContentBackground(.hidden)
        .background(AppColors.bg.ignoresSafeArea())
        .navigationTitle("Country flag")
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// Publishes the current user's row position in screen space, so the view can
/// tell whether their movement happened outside the visible viewport.
private struct OwnRowGeometryReporter: ViewModifier {
    let isOwnRow: Bool
    @Binding var y: CGFloat?

    func body(content: Content) -> some View {
        if isOwnRow {
            content.onGeometryChange(for: CGFloat.self) {
                $0.frame(in: .global).midY
            } action: { midY in
                y = midY
            }
        } else {
            content
        }
    }
}
