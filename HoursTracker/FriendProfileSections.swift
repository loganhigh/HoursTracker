import SwiftUI

// MARK: - Friend profile sections (Phase 6)
//
// Quiet building blocks for FriendProfileDetailView. Accents on that screen
// are tinted by the FRIEND's prestige tier (passed in as `tint`) — never by
// retinting the global theme.

// MARK: - Record row

/// Icon-in-circle row used by the company / personal-bests cards.
struct FriendRecordRow: View {
    let icon: String
    let title: String
    let value: String
    var detail: String? = nil
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.subtext)
                if let detail {
                    Text(detail)
                        .appText(.caption)
                        .foregroundStyle(AppColors.faint)
                }
            }
            Spacer()
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.text)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(AppColors.card2)
        )
    }
}

// MARK: - Badge tile

/// Earned badge on a friend's profile: flat fill with a tier-tinted ring —
/// no gradient fill, no glow. (Friend profiles only ever carry earned badges;
/// locked badges are not shared, so there is no locked variant here.)
struct FriendBadgeTile: View {
    let badge: SharedBadgeSummary
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .stroke(tint.opacity(0.55), lineWidth: 1.5)
                    )
                Image(systemName: badge.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(height: 60)

            VStack(spacing: 2) {
                Text(badge.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .frame(height: 28, alignment: .top)

                Text(badge.detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.subtext.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .frame(height: 24, alignment: .top)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Badges card

/// Earned + legend badge grid, privacy-gated by the caller. Shows nine tiles
/// with a quiet "See all" expander.
struct FriendBadgesCard: View {
    let friend: FriendProfile
    let accent: Color
    @Binding var showAllBadges: Bool

    var body: some View {
        let earned = friend.unlockedBadgeSummaries.filter { !$0.isLegend }
        let legend = friend.unlockedBadgeSummaries.filter(\.isLegend)
        let displayCount = earned.isEmpty ? friend.badgeCount : earned.count

        return SectionCard(
            title: "Badges",
            subtitle: "\(displayCount) badges unlocked",
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 16) {
                if friend.unlockedBadgeSummaries.isEmpty {
                    Text("Badge details haven't synced yet.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    if !earned.isEmpty {
                        let visible = showAllBadges ? earned : Array(earned.prefix(9))
                        badgesGrid(badges: visible)
                        if earned.count > 9 && !showAllBadges {
                            Button {
                                withAnimation(AppMotion.Spring.smooth) {
                                    showAllBadges = true
                                }
                            } label: {
                                Text("See all \(earned.count) badges")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                            .fill(accent.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !legend.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Legend")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.subtext)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            badgesGrid(badges: legend)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func badgesGrid(badges: [SharedBadgeSummary]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(badges) { badge in
                FriendBadgeTile(badge: badge, tint: accent)
            }
        }
    }
}

// MARK: - Hidden hours card

struct FriendHiddenHoursCard: View {
    var body: some View {
        SectionCard(
            title: "Hours hidden",
            subtitle: "This friend has chosen not to share work stats",
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 8) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppColors.subtext)
                Text("Rank and level are still visible, but hour totals stay private.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Expanded photo viewer

struct ExpandedPhotoView: View {
    let name: String
    let photoURL: String?
    let uid: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding()
                }
                Spacer()
                ProfileAvatarView(
                    name: name,
                    size: 280,
                    photoURL: photoURL,
                    uid: uid,
                    showsAccentRing: false
                )
                Text(name)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 16)
                Spacer()
            }
        }
    }
}

// MARK: - Formatting helpers

enum FriendProfileFormat {

    static func hoursDisplay(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value) + "h"
        }
        return AppTheme.Format.hours(value)
    }

    static func streakValueString(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    static func companyStartedString(from start: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM yyyy"
        return df.string(from: start)
    }

    static func yearsAtCompany(from start: Date) -> Double {
        max(0, Date().timeIntervalSince(start) / (60 * 60 * 24 * 365.25))
    }

    static func nextWorkAnniversary(from start: Date) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startParts = cal.dateComponents([.month, .day], from: start)
        guard let month = startParts.month, let day = startParts.day else { return nil }

        var thisYear = cal.dateComponents([.year], from: today)
        thisYear.month = month
        thisYear.day = day
        guard var anniversary = cal.date(from: thisYear) else { return nil }
        if cal.startOfDay(for: anniversary) < today {
            anniversary = cal.date(byAdding: .year, value: 1, to: anniversary) ?? anniversary
        }
        return anniversary
    }

    static func tenureAtCompanyString(from start: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: start, to: Date())
        let years = comps.year ?? 0
        let months = comps.month ?? 0
        if years == 0 && months == 0 { return "Less than a month" }
        if years == 0 { return months == 1 ? "1 month" : "\(months) months" }
        if months == 0 { return years == 1 ? "1 year" : "\(years) years" }
        let yearPart = years == 1 ? "1 year" : "\(years) years"
        let monthPart = months == 1 ? "1 month" : "\(months) months"
        return "\(yearPart), \(monthPart)"
    }

    static func anniversaryDateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: date)
    }

    static func anniversaryCountdownString(to date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "In \(days) days"
    }

    static func friendsSinceString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: date)
    }
}
