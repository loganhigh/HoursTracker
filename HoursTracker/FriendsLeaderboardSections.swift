import SwiftUI

// MARK: - Friends leaderboard: ranked rows
//
// The lower half of the Friends hub. Data types live in
// FriendsLeaderboardModel.swift; the podium in FriendsPodiumSections.swift.

// MARK: - Ranked row

struct LeaderboardRankRow: View {
    let entry: LeaderboardEntry
    /// Friend is on the app right now (their presence stamp is fresh).
    var isOnline: Bool = false
    let onOpen: () -> Void
    let onNudge: (() -> Void)?

    private var rankTint: Color {
        switch entry.rank {
        case 1: return AppColors.rankGold
        case 2: return AppColors.accent
        case 3: return AppColors.streak
        default: return AppColors.faint
        }
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("\(entry.rank)")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(rankTint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Wide enough for two digits at this size — without a
                // lineLimit, a rank ≥10 wrapped onto two lines ("1" over "0")
                // instead of sitting on one.
                .frame(width: 28)

            ProfileAvatarView(
                name: entry.name,
                size: 42,
                photoURL: entry.photoURL,
                uid: entry.id
            )
            .avatarOnlineDot(isOnline, avatarSize: 42)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.isMe ? "You" : entry.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.isMe ? AppColors.accent : AppColors.text)
                        .lineLimit(1)
                    if VerifiedTracker.isVerified(reviewed: entry.hasReviewedApp) {
                        VerifiedBadgeView(variant: .static, size: 13)
                    }
                }
                Text(entry.levelLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.subtext)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            movementBadge

            Text(entry.hoursHidden ? "—" : AppTheme.Format.hours(entry.payPeriodHours))
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColors.text)
                .monospacedDigit()
                .lineLimit(1)

            if entry.streak > 0 {
                HStack(spacing: 3) {
                    Text("🔥").font(.system(size: 10))
                    Text("\(entry.streak)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.subtext)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().stroke(AppColors.stroke, lineWidth: 1))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.faint)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 10)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(entry.isMe ? AppColors.accent.opacity(0.14) : AppColors.card.opacity(0.55))
                // Podium rows get a colored edge so the top three read as a
                // group without needing three different card fills.
                if entry.rank <= 3 {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(rankTint)
                        .frame(width: 4)
                        .padding(.vertical, 8)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(entry.isMe ? AppColors.accent.opacity(0.5) : AppColors.stroke,
                        lineWidth: entry.isMe ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.lightTap()
            onOpen()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.isMe ? "You" : entry.name), rank \(entry.rank), \(AppTheme.Format.hours(entry.payPeriodHours))")
        .accessibilityAction(named: "Nudge") { onNudge?() }
    }

    @ViewBuilder
    private var movementBadge: some View {
        if let movement = entry.movement {
            if movement == 0 {
                Text("—")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.faint)
            } else {
                HStack(spacing: 1) {
                    Image(systemName: movement > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(abs(movement))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(movement > 0 ? AppColors.positive : AppColors.negative)
            }
        }
    }
}
