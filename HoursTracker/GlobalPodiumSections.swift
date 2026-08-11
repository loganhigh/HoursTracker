import SwiftUI

// MARK: - Global leaderboard: podium + ranked rows
//
// The lower half of the global board. Header, hero card, and stats strip live
// in GlobalLeaderboardSections.swift. Presentation only — ranking and country
// resolution happen before these views are handed their data.

// MARK: - Podium

/// Top three, laid out 2–1–3 with the winner raised and framed in gold.
struct GlobalPodiumRow: View {
    let entries: [TopTracker]
    let currentUid: String?

    private var podium: [TopTracker] { Array(entries.prefix(3)) }

    var body: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.xs) {
            slot(index: 1)
            slot(index: 0)
            slot(index: 2)
        }
    }

    @ViewBuilder
    private func slot(index: Int) -> some View {
        if index < podium.count {
            let entry = podium[index]
            let isWinner = entry.rank == 1
            let isMe = entry.uid == currentUid
            let metal = LeaderboardRankStyle.color(entry.rank)
            let avatarSize: CGFloat = isWinner ? 84 : 66

            VStack(spacing: 6) {
                ProfileAvatarView(
                    name: entry.name,
                    size: avatarSize,
                    photoURL: entry.photoURL,
                    uid: entry.uid
                )
                .overlay(Circle().stroke(metal, lineWidth: isWinner ? 3 : 2))
                .padding(.top, isWinner ? 4 : 0)

                HStack(spacing: 4) {
                    Text(entry.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                    if let flag = flagEmoji(for: entry) {
                        Text(flag).font(.system(size: 13))
                    }
                    if isMe {
                        YouChip()
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Text(GlobalHoursFormat.hours(entry.hours))
                    .font(.system(size: isWinner ? 21 : 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(metal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if entry.streak > 0 {
                    HStack(spacing: 3) {
                        Text("🔥").font(.system(size: 10))
                        Text("\(entry.streak) day streak")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColors.subtext)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                } else {
                    // Holds the column's baseline so a streakless winner
                    // doesn't sit shorter than the runners-up.
                    Color.clear.frame(height: 13)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.top, isWinner ? AppSpacing.sm : AppSpacing.xs)
            .padding(.bottom, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card.opacity(isWinner ? 0.75 : 0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(
                                isWinner ? metal.opacity(0.85) : AppColors.stroke,
                                lineWidth: isWinner ? 1.5 : 0.5
                            )
                    )
            )
            .overlay(alignment: .topLeading) {
                rankBadge(entry.rank, metal: metal)
                    .offset(x: -4, y: isWinner ? -12 : -10)
            }
        } else {
            // Keeps the three columns evenly spaced with fewer than 3 trackers.
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
    }

    private func rankBadge(_ rank: Int, metal: Color) -> some View {
        Text("\(rank)")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(AppColors.textOnAccent)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                    .fill(metal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                    .stroke(AppColors.bg, lineWidth: 2)
            )
    }

    private func flagEmoji(for entry: TopTracker) -> String? {
        CountryFlag.emoji(
            for: CountryFlag.leaderboardCode(
                trackerUid: entry.uid,
                serverCode: entry.countryCode,
                currentUid: currentUid
            )
        )
    }
}

// MARK: - "YOU" chip

struct YouChip: View {
    var body: some View {
        Text("YOU")
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(AppColors.accent.opacity(0.14)))
            .fixedSize()
    }
}

// MARK: - Ranked list

/// Shared column geometry, so the caption row and the ranked rows below it
/// can't drift out of alignment.
enum GlobalLeaderboardMetrics {
    static let rankColumnWidth: CGFloat = 34
    static let avatarSize: CGFloat = 36
    /// Where the name column starts, measured from the row's leading edge —
    /// used to inset the dividers.
    static var nameColumnInset: CGFloat {
        AppSpacing.sm + rankColumnWidth + AppSpacing.sm + avatarSize + AppSpacing.sm
    }
}

/// Column captions above the ranked rows. Just "Rank" and "All time hours" —
/// the name column needs no caption of its own.
struct GlobalListHeader: View {
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("Rank")
                // A smaller, un-fixed size so it actually shrinks to fit the
                // rank column instead of overflowing into the next column —
                // fixedSize previously reported "RANK"'s full width past the
                // 34pt frame, which the frame doesn't clip, so it visually
                // ran straight into "Tracker".
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: GlobalLeaderboardMetrics.rankColumnWidth, alignment: .leading)
            Spacer(minLength: AppSpacing.xs)
            Text("All time hours")
                .lineLimit(1)
        }
        .appText(.eyebrow)
        .foregroundStyle(AppColors.faint)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, 6)
    }
}

struct GlobalTrackerRow: View {
    let tracker: TopTracker
    let currentUid: String?

    private var isMe: Bool { tracker.uid == currentUid }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("\(tracker.rank)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isMe ? AppColors.accent : AppColors.subtext)
                .frame(width: GlobalLeaderboardMetrics.rankColumnWidth, alignment: .leading)

            ProfileAvatarView(
                name: tracker.name,
                size: GlobalLeaderboardMetrics.avatarSize,
                photoURL: tracker.photoURL,
                uid: tracker.uid
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(tracker.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                    if let flag = CountryFlag.emoji(
                        for: CountryFlag.leaderboardCode(
                            trackerUid: tracker.uid,
                            serverCode: tracker.countryCode,
                            currentUid: currentUid
                        )
                    ) {
                        Text(flag).font(.system(size: 14))
                    }
                    if isMe { YouChip() }
                }

                if !tracker.levelLine.isEmpty {
                    Text(tracker.levelLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.faint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppSpacing.xs)

            Text(GlobalHoursFormat.hours(tracker.hours))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isMe ? AppColors.accent : AppColors.text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(isMe ? AppColors.accent.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
