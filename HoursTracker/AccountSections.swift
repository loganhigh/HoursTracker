import SwiftUI

// MARK: - Account sections (Phase 9 — You tab)
//
// Building blocks for AccountView: the XP progress bar under the identity hero
// and the quiet navigation/account rows. Tokens + DesignComponents only — flat
// fills, hairline strokes, zero glows. The XP fill is the one moving part, and
// only on change.

// MARK: - XP capsule

/// Slim XP progress bar for the You tab: caption above, track + fill below.
///
/// The fill animates on *change* only — `.animation(value:)` doesn't run on
/// first render, so opening the tab still never replays a fill from zero. That
/// keeps the original constraint (no cold-launch pop, helped by the
/// `XPStripCache` fallback below, which HomeXPStrip owns the writes for) while
/// letting real XP gains and the arrival of server stats move the bar visibly.
struct ProfileXPCapsule: View {
    @ObservedObject var store: HoursStore
    // Server stats drive displayedGamificationProfile(); observe so the bar
    // re-renders the moment they arrive.
    @ObservedObject private var statsListener = StatsListenerService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(XPStripCache.progressKey) private var cachedProgress: Double = 0

    private var profile: GamificationProfile { store.displayedGamificationProfile() }

    private var liveProgress: Double {
        let p = profile
        guard p.xpForNextLevel > 0 else { return 0 }
        return min(max(Double(p.xpIntoCurrentLevel) / Double(p.xpForNextLevel), 0), 1)
    }

    /// Falls back to the Home strip's persisted fill until server stats land,
    /// so a cold launch shows the last known value rather than an empty bar
    /// that pops full a moment later.
    private var displayedProgress: Double {
        profile.xpForNextLevel > 0 ? liveProgress : cachedProgress
    }

    private var xpCaption: String {
        "\(profile.xpIntoCurrentLevel.formatted()) / \(profile.xpForNextLevel.formatted()) XP"
    }

    private var percent: Int {
        Int((min(max(displayedProgress, 0), 1) * 100).rounded())
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(xpCaption)
                    .appText(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.text)
                Spacer(minLength: AppSpacing.xs)
                Text("\(percent)%")
                    .appText(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.accent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.stroke.opacity(0.6))

                    Capsule()
                        .fill(AppColors.accentGradient)
                        .frame(width: max(0, geo.size.width * displayedProgress))
                }
            }
            .frame(height: 10)
            // Only fires when the value actually changes — the fill is not
            // replayed from zero when the tab appears.
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.7),
                value: displayedProgress
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(profile.xpIntoCurrentLevel) of \(profile.xpForNextLevel) experience points, \(percent) percent"
        )
    }
}

// MARK: - Navigation / account row

/// One quiet row: SF icon in a small tinted square, title, optional subtitle,
/// optional trailing detail, optional chevron. Rows stack inside
/// `AccountRowsCard` separated by hairlines.
struct AccountNavRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var detail: String? = nil
    var tint: Color = AppColors.accent
    var titleTint: Color = AppColors.text
    var showsChevron: Bool = true
    var isBusy: Bool = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 30, height: 30)
                .overlay {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(tint)
                    } else {
                        Image(systemName: icon)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appText(.headline)
                    .foregroundStyle(titleTint)
                if let subtitle {
                    Text(subtitle)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: AppSpacing.xs)

            if let detail {
                Text(detail)
                    .appText(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.subtext)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.faint)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Rows card

/// Quiet card that stacks rows with hairline separators (inset past the icon
/// square so the hairline aligns with the text column).
struct AccountRowsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColors.stroke, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }
}

/// Hairline separator between `AccountNavRow`s.
struct AccountRowHairline: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.stroke)
            .frame(height: 0.5)
            .padding(.leading, AppSpacing.md + 30 + AppSpacing.sm)
    }
}
