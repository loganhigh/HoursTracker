import SwiftUI

// MARK: - Friends leaderboard: header + pay-period podium
//
// The upper half of the Friends hub. Data types live in
// FriendsLeaderboardModel.swift; the ranked rows in
// FriendsLeaderboardSections.swift.

// MARK: - Header

struct FriendsHeroHeader: View {
    let onAddFriend: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Text("Friends")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColors.text)

            Spacer(minLength: AppSpacing.xs)

            Button {
                Haptics.lightTap()
                onAddFriend()
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textOnAccent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppColors.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a friend")
        }
    }
}

// MARK: - Podium

struct PayPeriodPodiumCard: View {
    let entries: [LeaderboardEntry]

    private var podium: [LeaderboardEntry] { Array(entries.prefix(3)) }
    private var me: LeaderboardEntry? { entries.first(where: \.isMe) }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.xs) {
                podiumSlot(index: 1)
                podiumSlot(index: 0)
                podiumSlot(index: 2)
            }

            // `gapRow` is a @ViewBuilder that renders nothing when there is no
            // gap to show, so it needs no conditional here.
            gapRow
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                        .stroke(AppColors.accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func tint(forRank rank: Int) -> Color {
        switch rank {
        case 1: return AppColors.rankGold
        case 2: return AppColors.accent
        default: return AppColors.streak
        }
    }

    @ViewBuilder
    private func podiumSlot(index: Int) -> some View {
        if index < podium.count {
            let entry = podium[index]
            let isWinner = entry.rank == 1
            let size: CGFloat = isWinner ? 92 : 68
            let color = tint(forRank: entry.rank)

            VStack(spacing: 6) {
                // Reserve the crown's height on every slot so the three
                // avatars stay on one baseline instead of the winner shoving
                // its column down.
                Text(isWinner ? "👑" : " ")
                    .font(.system(size: 20))

                ZStack(alignment: .bottom) {
                    ProfileAvatarView(
                        name: entry.name,
                        size: size,
                        photoURL: entry.photoURL,
                        uid: entry.id
                    )
                    .overlay(Circle().stroke(color, lineWidth: isWinner ? 3 : 2))

                    Text("\(entry.rank)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColors.textOnAccent)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(color))
                        .overlay(Circle().stroke(AppColors.bg, lineWidth: 2))
                        .offset(y: 10)
                }
                .padding(.bottom, 10)

                HStack(spacing: 4) {
                    Text(entry.isMe ? "You" : entry.firstName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                    if VerifiedTracker.isVerified(reviewed: entry.hasReviewedApp) {
                        // Three at most on the podium — shimmer is affordable.
                        VerifiedBadgeView(variant: .shimmer, size: 13)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                Text(AppTheme.Format.hours(entry.payPeriodHours))
                    .font(.system(size: isWinner ? 22 : 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if entry.streak > 0 {
                    HStack(spacing: 3) {
                        Text("🔥").font(.system(size: 10))
                        Text("\(entry.streak) day streak")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColors.subtext)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            // Keeps the three columns evenly spaced with fewer than 3 people.
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
    }

    @ViewBuilder
    private var gapRow: some View {
        if let me, let text = gapText(for: me) {
            HStack(spacing: AppSpacing.sm) {
                Text(text.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppColors.stroke.opacity(0.6))
                            .frame(height: 5)
                        Capsule()
                            .fill(AppColors.accentGradient)
                            .frame(width: max(5, geo.size.width * text.progress), height: 5)
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 9, height: 9)
                            .offset(x: max(0, geo.size.width * text.progress - 4.5))
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 12)

                Image(systemName: "flag.checkered")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.faint)
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.card2.opacity(0.7))
            )
        }
    }

    private func gapText(for me: LeaderboardEntry) -> (label: String, progress: Double)? {
        let mine = me.payPeriodHours
        guard me.rank > 1 else {
            // Leading: show the cushion over second place instead of a gap.
            guard let second = entries.first(where: { $0.rank == 2 }) else { return nil }
            let lead = mine - second.payPeriodHours
            guard lead > 0 else { return ("You're in the lead", 1) }
            return ("You're \(AppTheme.Format.hours(lead)) ahead", 1)
        }
        guard let above = entries.first(where: { $0.rank == me.rank - 1 }) else { return nil }
        let theirs = above.payPeriodHours
        let gap = theirs - mine
        guard gap > 0, theirs > 0 else { return nil }
        return ("You're \(AppTheme.Format.hours(gap)) behind \(above.firstName)",
                min(max(mine / theirs, 0), 1))
    }
}
