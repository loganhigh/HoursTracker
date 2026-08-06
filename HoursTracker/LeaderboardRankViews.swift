import SwiftUI

// MARK: - Leaderboard rank components
//
// Rank metals + the numbered pip used by GlobalLeaderboardView. Pure
// presentation — no data logic lives here.

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
