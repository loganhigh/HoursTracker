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
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    private var myUid: String? { authService.user?.uid }

    private var myTracker: TopTracker? {
        topTrackers.tracker(for: myUid)
    }

    /// The podium only earns its space with a full top three; below that every
    /// tracker stays in the list.
    private var showsPodium: Bool { topTrackers.allTrackers.count >= 3 }

    private var listTrackers: [TopTracker] {
        showsPodium ? Array(topTrackers.allTrackers.dropFirst(3)) : topTrackers.allTrackers
    }

    private var totalRankedHours: Double {
        topTrackers.allTrackers.reduce(0) { $0 + $1.hours }
    }

    /// The viewer's standing as a percentile, rounded up so rank 1 reads
    /// "Top 1%" rather than "Top 0%".
    private var myPercentile: Int? {
        guard let myTracker, !topTrackers.allTrackers.isEmpty else { return nil }
        let fraction = Double(myTracker.rank) / Double(topTrackers.allTrackers.count)
        return max(1, Int(ceil(fraction * 100)))
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
        .task {
            await topTrackers.ensureFullLeaderboardLoaded()
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
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    GlobalRankHeroCard(rank: myTracker?.rank)

                    GlobalStatsStrip(
                        trackerCount: topTrackers.allTrackers.count,
                        totalHours: totalRankedHours,
                        percentile: myPercentile
                    )

                    if showsPodium {
                        GlobalPodiumRow(
                            entries: topTrackers.allTrackers,
                            currentUid: myUid
                        )
                        .padding(.top, AppSpacing.xs)
                    }

                    if !listTrackers.isEmpty {
                        rankedList
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.lg)
            }
        }
    }

    private var rankedList: some View {
        VStack(spacing: 0) {
            GlobalListHeader()

            ForEach(listTrackers) { tracker in
                GlobalTrackerRow(tracker: tracker, currentUid: myUid)
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
