import SwiftUI

// MARK: - Profile badge strip

/// A person's unlocked badges as one row of small icons right under their
/// title — on your own profile, a friend's profile and the public profile
/// sheet — so what someone has earned is visible at a glance instead of
/// further down the page. Rarest / newest first. Tap an icon to read its
/// name and what it's for underneath.
struct ProfileBadgeStrip: View {
    let badges: [SharedBadgeSummary]
    var tint: Color = AppColors.accent

    @State private var selected: SharedBadgeSummary?

    private static let legendTint = Color(red: 0.98, green: 0.78, blue: 0.30)

    private var ordered: [SharedBadgeSummary] {
        badges.sorted { a, b in
            a.isLegend != b.isLegend ? a.isLegend : a.order > b.order
        }
    }

    var body: some View {
        if !badges.isEmpty {
            VStack(spacing: 6) {
                // Centred when they fit, scrollable when they don't.
                ViewThatFits(in: .horizontal) {
                    row
                    ScrollView(.horizontal, showsIndicators: false) { row }
                }

                if let selected {
                    VStack(spacing: 1) {
                        Text(selected.name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColors.text)
                        if !selected.detail.isEmpty {
                            Text(selected.detail)
                                .font(.caption2)
                                .foregroundStyle(AppColors.subtext)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.snappy(duration: 0.2), value: selected)
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            ForEach(ordered) { badge in
                icon(badge)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private func icon(_ badge: SharedBadgeSummary) -> some View {
        let color = badge.isLegend ? Self.legendTint : tint
        let isSelected = selected == badge
        return Button {
            Haptics.lightTap()
            selected = isSelected ? nil : badge
        } label: {
            Image(systemName: badge.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(color.opacity(isSelected ? 0.28 : 0.12)))
                .overlay(Circle().stroke(color.opacity(isSelected ? 0.9 : 0.45), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge.name)
        .accessibilityHint(badge.detail)
    }
}
