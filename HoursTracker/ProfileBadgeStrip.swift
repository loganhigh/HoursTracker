import SwiftUI

// MARK: - Profile badges button

/// One compact "N badges ›" pill under a person's title — on your own
/// profile, a friend's profile and the public profile sheet. Tap it to open
/// the full list of what they've unlocked (name and what each is for).
/// Rarest / newest first.
struct ProfileBadgeStrip: View {
    let badges: [SharedBadgeSummary]
    var tint: Color = AppColors.accent
    /// Your own profile opens the full collection (locked badges and
    /// progress included) instead of the earned-only list.
    var onTap: (() -> Void)? = nil

    @State private var showingList = false

    private var ordered: [SharedBadgeSummary] {
        badges.sorted { a, b in
            a.isLegend != b.isLegend ? a.isLegend : a.order > b.order
        }
    }

    var body: some View {
        if !badges.isEmpty || onTap != nil {
            Button {
                Haptics.lightTap()
                if let onTap { onTap() } else { showingList = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rosette")
                        .font(.footnote.weight(.bold))
                    Text("\(badges.count) \(badges.count == 1 ? "badge" : "badges")")
                        .font(.subheadline.weight(.bold))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .opacity(0.7)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(tint.opacity(0.12)))
                .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(badges.count) badges")
            .accessibilityHint("Shows the badge list")
            .sheet(isPresented: $showingList) {
                ProfileBadgeListSheet(badges: ordered, tint: tint)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

/// The unlocked badges as a list: icon, name, what it's for.
private struct ProfileBadgeListSheet: View {
    let badges: [SharedBadgeSummary]
    let tint: Color

    private static let legendTint = Color(red: 0.98, green: 0.78, blue: 0.30)

    var body: some View {
        NavigationStack {
            List(badges) { badge in
                let color = badge.isLegend ? Self.legendTint : tint
                HStack(spacing: 12) {
                    Image(systemName: badge.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(color.opacity(0.14)))
                        .overlay(Circle().stroke(color.opacity(0.45), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppColors.text)
                        if !badge.detail.isEmpty {
                            Text(badge.detail)
                                .font(.caption)
                                .foregroundStyle(AppColors.subtext)
                        }
                    }
                }
                .padding(.vertical, 2)
                .listRowBackground(AppColors.card)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("\(badges.count) \(badges.count == 1 ? "Badge" : "Badges")")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
