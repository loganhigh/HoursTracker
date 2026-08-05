import SwiftUI

// MARK: - Global leaderboard (full list)
//
// Phase 7 redesign: standard hero-card anatomy for the "YOUR RANK" summary
// (accent gradient overlay + stroke, zero shadow — Home owns the app's only
// glowing hero), metal rank pips for the top 3, and an accent-highlighted
// row for the signed-in user. All data comes from TopTrackersService.

struct GlobalLeaderboardView: View {
    @ObservedObject private var topTrackers = TopTrackersService.shared
    @EnvironmentObject private var authService: AuthService

    private var myTracker: TopTracker? {
        topTrackers.tracker(for: authService.user?.uid)
    }

    var body: some View {
        Group {
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
                        summaryHeader

                        VStack(spacing: 0) {
                            ForEach(topTrackers.allTrackers) { tracker in
                                leaderboardRow(tracker)
                                if tracker.id != topTrackers.allTrackers.last?.id {
                                    Divider()
                                        .overlay(AppColors.stroke)
                                        .opacity(0.5)
                                        .padding(.leading, 52)
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
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                }
            }
        }
        .background(AppColors.bg.ignoresSafeArea())
        .navigationTitle("Global leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await topTrackers.ensureFullLeaderboardLoaded()
        }
    }

    // MARK: Hero summary

    private var summaryHeader: some View {
        VStack(spacing: AppSpacing.sm) {
            Text("Your rank")
                .appText(.eyebrow)
                .foregroundStyle(AppColors.subtext)

            Text(myTracker.map { "#\($0.rank)" } ?? "—")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(
                myTracker.map { "\(hoursLabel($0.hours)) · of \(topTrackers.allTrackers.count) trackers ranked" }
                    ?? "\(topTrackers.allTrackers.count) trackers ranked"
            )
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(AppColors.subtext)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .fill(AppColors.card2)
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.accent.opacity(0.14),
                                Color.clear,
                                AppColors.accent.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            AppColors.accent.opacity(0.4),
                            AppColors.accent.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: Rows

    private func leaderboardRow(_ tracker: TopTracker) -> some View {
        let isMe = tracker.uid == authService.user?.uid
        return HStack(spacing: AppSpacing.sm) {
            rankPip(tracker.rank)

            HStack(spacing: 5) {
                Text(tracker.name)
                    .font(.system(size: 15, weight: tracker.rank <= 3 || isMe ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(AppColors.text)
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
                    Text("YOU")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppColors.accent.opacity(0.12))
                        )
                        .fixedSize()
                }
            }

            Spacer(minLength: AppSpacing.xs)

            Text(hoursLabel(tracker.hours))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isMe ? AppColors.text : AppColors.subtext)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(isMe ? AppColors.accent.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    /// Metal pip for the top 3; a plain rank number beyond.
    @ViewBuilder
    private func rankPip(_ rank: Int) -> some View {
        if rank <= 3 {
            LeaderboardRankPip(rank: rank, size: 28)
        } else {
            Text("\(rank)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.subtext)
                .frame(width: 28)
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
