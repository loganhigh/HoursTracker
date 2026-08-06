import SwiftUI

// MARK: - Friends leaderboard building blocks (Phase 7)
//
// Row model + quiet podium/rank components shared by FriendsLeaderboardView
// (and rank metals reused by GlobalLeaderboardView). Pure presentation — no
// data logic lives here.

// MARK: Row model

/// View-model row consumed by the podium, the you-row, and the standings list.
struct FriendsLeaderboardRowModel: Identifiable, Equatable {
    let id: String
    let displayName: String
    let isMe: Bool
    let levelDisplayLine: String
    let primaryValue: Double
    let primaryDisplay: String
    let subtitle: String
    let profilePhotoURL: String?
}

// MARK: Rank metals

enum LeaderboardRankStyle {
    static func color(_ rank: Int) -> Color {
        switch rank {
        case 1:  return AppColors.rankGold
        case 2:  return AppColors.rankSilver
        case 3:  return AppColors.rankBronze
        default: return AppColors.subtext
        }
    }
}

// MARK: Rank pip

struct LeaderboardRankPip: View {
    let rank: Int
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .fill(LeaderboardRankStyle.color(rank).opacity(0.18))
                .frame(width: size, height: size)
            Text("\(rank)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(LeaderboardRankStyle.color(rank))
        }
    }
}

// MARK: Relative bar

/// Thin capsule showing a row's value relative to the leader —
/// same recipe as the Friends segment rows.
struct LeaderboardRelativeBar: View {
    let fraction: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(AppColors.stroke.opacity(0.65))
            Capsule()
                .fill(AppColors.accent)
                .frame(width: max(4, 64 * fraction))
        }
        .frame(width: 64, height: 4)
        .accessibilityHidden(true)
    }
}

// MARK: Podium column

/// One quiet podium step: avatar (crown on #1, no glow), name, level line,
/// hours, then a flat stepped platform with a metal rank pip.
struct LeaderboardPodiumColumn: View {
    let row: FriendsLeaderboardRowModel?
    let height: CGFloat
    let rank: Int

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            ProfileAvatarView(
                name: row?.displayName ?? "—",
                size: rank == 1 ? 56 : 48,
                photoURL: row?.profilePhotoURL,
                uid: row?.id,
                showsAccentRing: rank == 1
            )
            .overlay(alignment: .top) {
                if rank == 1 {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColors.rankGold)
                        .offset(y: -19)
                }
            }
            Text(row?.displayName ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
            if let levelLine = row?.levelDisplayLine {
                Text(levelLine)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(row?.primaryDisplay ?? "—")
                .font(.system(size: rank == 1 ? 17 : 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            platform
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Flat stepped platform: quiet card fill, hairline stroke, metal rank pip.
    private var platform: some View {
        RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
            .fill(AppColors.card2)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .stroke(AppColors.stroke, lineWidth: 0.5)
            )
            .frame(height: height)
            .overlay(alignment: .top) {
                LeaderboardRankPip(rank: rank)
                    .padding(.top, AppSpacing.sm)
            }
    }
}
