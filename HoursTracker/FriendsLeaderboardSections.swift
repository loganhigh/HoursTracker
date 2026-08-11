import SwiftUI

// MARK: - Friends leaderboard: ranked rows + crew summary
//
// The lower half of the Friends hub. Data types live in
// FriendsLeaderboardModel.swift; the podium in FriendsPodiumSections.swift.

// MARK: - Ranked row

struct LeaderboardRankRow: View {
    let entry: LeaderboardEntry
    let metric: LeaderboardMetric
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
                .frame(width: 22)
                .monospacedDigit()

            ProfileAvatarView(
                name: entry.name,
                size: 42,
                photoURL: entry.photoURL,
                uid: entry.id
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isMe ? "You" : entry.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.isMe ? AppColors.accent : AppColors.text)
                    .lineLimit(1)
                Text(entry.levelLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.subtext)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            movementBadge

            Text(entry.hoursHidden && metric == .thisWeek ? "—" : metric.display(entry))
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
        .accessibilityLabel("\(entry.isMe ? "You" : entry.name), rank \(entry.rank), \(metric.display(entry))")
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

// MARK: - Crew summary

struct CrewSummaryCard: View {
    let entries: [LeaderboardEntry]
    let onOpen: (() -> Void)?

    /// Everyone's shared weekly hours added together.
    private var crewHours: Double {
        entries.filter { !$0.hoursHidden }.reduce(0) { $0 + $1.weeklyHours }
    }

    /// The next 100-hour milestone above the crew's current total. Derived
    /// rather than configured — the app has no per-crew goal to read, and a
    /// made-up target would be a number the user could never change.
    private var goal: Double {
        max(100, (crewHours / 100).rounded(.down) * 100 + 100)
    }

    private var topPerformer: LeaderboardEntry? {
        entries.filter { !$0.hoursHidden }.max { $0.weeklyHours < $1.weeklyHours }
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(AppColors.accent.opacity(0.14)))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Crew Goal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.subtext)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(AppTheme.Format.hours(crewHours))
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColors.text)
                            .monospacedDigit()
                        Text("/ \(Int(goal))h")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.faint)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppColors.stroke.opacity(0.6)).frame(height: 5)
                            Capsule()
                                .fill(AppColors.accentGradient)
                                .frame(width: max(0, geo.size.width * min(crewHours / goal, 1)), height: 5)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(AppColors.stroke)
                .frame(width: 0.5, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("Top Performer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.subtext)
                if let topPerformer {
                    HStack(spacing: 4) {
                        Text(topPerformer.isMe ? "You" : topPerformer.firstName)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColors.text)
                            .lineLimit(1)
                        if topPerformer.streak > 0 { Text("🔥").font(.system(size: 12)) }
                    }
                    Text("\(AppTheme.Format.hours(topPerformer.weeklyHours)) this week")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.faint)
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColors.faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if onOpen != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.faint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(AppColors.card2))
            }
        }
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
    }
}
