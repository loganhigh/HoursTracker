import SwiftUI
// The podium's reset countdown uses Timer.publish(...).autoconnect(), which is
// Combine's, not SwiftUI's.
import Combine

// MARK: - Friends leaderboard: header, podium, metric switcher
//
// The upper half of the Friends hub. Data types live in
// FriendsLeaderboardModel.swift; the ranked rows in
// FriendsLeaderboardSections.swift.

// MARK: - Header

struct FriendsHeroHeader: View {
    let onSearch: () -> Void
    let onAddFriend: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Friends")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.text)
                HStack(spacing: 0) {
                    Text("Work hard. Track time. ")
                        .foregroundStyle(AppColors.subtext)
                    Text("Beat your crew.")
                        .foregroundStyle(AppColors.streak)
                }
                .font(.system(size: 14, weight: .semibold))
            }

            Spacer(minLength: AppSpacing.xs)

            circleButton(icon: "magnifyingglass", filled: false, action: onSearch)
                .accessibilityLabel("Search friends")
            circleButton(icon: "person.badge.plus", filled: true, action: onAddFriend)
                .accessibilityLabel("Add a friend")
        }
    }

    private func circleButton(icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.lightTap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? AppColors.textOnAccent : AppColors.text)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(filled ? AppColors.accent : AppColors.card.opacity(0.8))
                )
                .overlay(
                    Circle().stroke(filled ? Color.clear : AppColors.stroke, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Podium

struct WeeklyPodiumCard: View {
    let entries: [LeaderboardEntry]
    let metric: LeaderboardMetric
    let resetsAt: Date?

    /// Ticks the countdown. Driven by a timer rather than recomputed on render
    /// so the value does not sit frozen while the screen is open.
    @State private var now = Date()
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var podium: [LeaderboardEntry] { Array(entries.prefix(3)) }
    private var me: LeaderboardEntry? { entries.first(where: \.isMe) }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            header

            HStack(alignment: .top, spacing: AppSpacing.xs) {
                podiumSlot(index: 1)
                podiumSlot(index: 0)
                podiumSlot(index: 2)
            }

            if let gapRow { gapRow }
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
        .onReceive(ticker) { now = $0 }
    }

    private var header: some View {
        HStack(alignment: .top) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("WEEKLY PODIUM")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.text)
                    .tracking(0.8)
                Text("Mon → Sun")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.faint)
            }
            Spacer(minLength: AppSpacing.xs)
            if let countdown {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Resets in")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.faint)
                    Text(countdown)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.accent)
                        .monospacedDigit()
                }
            }
        }
    }

    private var countdown: String? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        return days > 0 ? "\(days)d \(hours)h \(minutes)m" : "\(hours)h \(minutes)m"
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

                Text(entry.isMe ? "You" : entry.firstName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)

                Text(metric.display(entry))
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
        let mine = metric.value(me)
        guard me.rank > 1 else {
            // Leading: show the cushion over second place instead of a gap.
            guard let second = entries.first(where: { $0.rank == 2 }) else { return nil }
            let lead = mine - metric.value(second)
            guard lead > 0 else { return ("You're in the lead", 1) }
            return ("You're \(metric.gapPhrase(lead)) ahead", 1)
        }
        guard let above = entries.first(where: { $0.rank == me.rank - 1 }) else { return nil }
        let theirs = metric.value(above)
        let gap = theirs - mine
        guard gap > 0, theirs > 0 else { return nil }
        return ("You're \(metric.gapPhrase(gap)) behind \(above.isMe ? "you" : above.firstName)",
                min(max(mine / theirs, 0), 1))
    }
}

// MARK: - Metric picker

struct LeaderboardMetricPicker: View {
    @Binding var selection: LeaderboardMetric

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LeaderboardMetric.allCases) { metric in
                let isSelected = metric == selection
                Button {
                    Haptics.lightTap()
                    selection = metric
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: metric.icon)
                            .font(.system(size: 12, weight: .bold))
                        Text(metric.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(isSelected ? AppColors.textOnAccent : AppColors.subtext)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Capsule().fill(isSelected ? AppColors.accent : Color.clear)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(AppColors.card.opacity(0.55))
                .overlay(Capsule().stroke(AppColors.stroke, lineWidth: 0.5))
        )
        .accessibilityElement(children: .contain)
    }
}
