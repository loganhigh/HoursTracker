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
    /// Uids with a fresh presence stamp — podium names get the online dot.
    var onlineUids: Set<String> = []
    /// Live rank deltas from the latest reorder — podium slots show the same
    /// transient chip the list rows do.
    var movements: [String: Int] = [:]

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
                .avatarOnlineDot(
                    entry.uid != currentUid && onlineUids.contains(entry.uid),
                    avatarSize: avatarSize
                )
                .padding(.top, isWinner ? 4 : 0)

                HStack(spacing: 4) {
                    Text(entry.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                    if VerifiedTracker.isVerified(reviewed: entry.hasReviewedApp) {
                        // Only three of these on screen, so they can shimmer.
                        VerifiedBadgeView(variant: .shimmer, size: 14)
                    }
                    if let flag = flagEmoji(for: entry) {
                        Text(flag).font(.system(size: 13))
                    }
                    if isMe {
                        YouChip()
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                HStack(spacing: 5) {
                    Text(GlobalHoursFormat.hours(entry.hours))
                        .font(.system(size: isWinner ? 21 : 18, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(AppMotion.Spring.snappy, value: entry.hours)
                        .foregroundStyle(metal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let move = movements[entry.uid] {
                        RankMovementChip(delta: move)
                    }
                }

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

// The ranked list carries no column captions — rank, name, and hours all read
// for themselves, and the screen's own subtitle already says the board is
// ranked on all-time hours.

struct GlobalTrackerRow: View {
    let tracker: TopTracker
    let currentUid: String?
    /// Tracker is on the app right now (their presence stamp is fresh).
    var isOnline: Bool = false
    /// Places just gained (+) or lost (−) in the latest live reorder; nil when
    /// this row didn't move. Drives the transient chip and highlight.
    var movement: Int? = nil

    private var isMe: Bool { tracker.uid == currentUid }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("\(tracker.rank)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                // Rolls the digits when the rank changes instead of swapping
                // the whole glyph — no flicker.
                .contentTransition(.numericText())
                .animation(AppMotion.Spring.snappy, value: tracker.rank)
                .foregroundStyle(isMe ? AppColors.accent : AppColors.subtext)
                .frame(width: GlobalLeaderboardMetrics.rankColumnWidth, alignment: .leading)

            ProfileAvatarView(
                name: tracker.name,
                size: GlobalLeaderboardMetrics.avatarSize,
                photoURL: tracker.photoURL,
                uid: tracker.uid
            )
            .avatarOnlineDot(isOnline, avatarSize: GlobalLeaderboardMetrics.avatarSize)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(tracker.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                    if VerifiedTracker.isVerified(reviewed: tracker.hasReviewedApp) {
                        // Static in the list: the board scrolls hundreds of
                        // rows, and a shimmer each would be one clock per row.
                        VerifiedBadgeView(variant: .static, size: 13)
                    }
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

            if let movement {
                RankMovementChip(delta: movement)
            }

            Text(GlobalHoursFormat.hours(tracker.hours))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(AppMotion.Spring.snappy, value: tracker.hours)
                .foregroundStyle(isMe ? AppColors.accent : AppColors.text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
    }

    /// While a movement chip is up, the row carries a whisper of green (up) or
    /// red (down) under the usual treatment; it fades out with the chip when
    /// the service clears movements. Own-row accent still wins visually.
    private var rowFill: Color {
        if let movement {
            let tint = movement > 0 ? Color.green : Color.red
            return isMe
                ? AppColors.accent.opacity(0.12)
                : tint.opacity(movement > 0 ? 0.08 : 0.05)
        }
        return isMe ? AppColors.accent.opacity(0.12) : Color.clear
    }
}

// MARK: - Transient movement chip

/// "↑ 2" / "↓ 1" beside the hours while a live reorder is fresh. Appears with
/// a small spring, and disappears when TopTrackersService clears its movement
/// batch (~2.6s) — nothing on the board carries a permanent arrow.
struct RankMovementChip: View {
    let delta: Int

    private var up: Bool { delta > 0 }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: up ? "arrow.up" : "arrow.down")
                .font(.system(size: 9, weight: .heavy))
            Text("\(abs(delta))")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(up ? Color.green : Color.red)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill((up ? Color.green : Color.red).opacity(0.14))
        )
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .accessibilityLabel(up ? "Moved up \(delta) places" : "Moved down \(abs(delta)) places")
    }
}
