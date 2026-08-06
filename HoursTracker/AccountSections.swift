import SwiftUI

// MARK: - Account sections (Phase 9 — You tab)
//
// Building blocks for AccountView: the XP capsule under the identity hero and
// the quiet navigation/account rows. Tokens + DesignComponents only — flat
// fills, hairline strokes, zero glows. Motion honors Reduce Motion.

// MARK: - XP capsule

/// Slim XP bar for the You tab: "LVL N" chip inside the track at the left,
/// "x,xxx / y,yyy XP" caption at the right. Fill animates on appear, seeded
/// read-only from the Home strip's persisted cache (`XPStripCache`) so a cold
/// launch starts at the last displayed fill — HomeXPStrip owns the writes.
struct ProfileXPCapsule: View {
    @ObservedObject var store: HoursStore
    // Server stats drive displayedGamificationProfile(); observe so the bar
    // re-renders the moment they arrive.
    @ObservedObject private var statsListener = StatsListenerService.shared

    @AppStorage(XPStripCache.progressKey) private var cachedProgress: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedProgress: Double = 0
    @State private var seeded = false

    private var profile: GamificationProfile { store.displayedGamificationProfile() }

    private var liveProgress: Double {
        let p = profile
        guard p.xpForNextLevel > 0 else { return 0 }
        return min(max(Double(p.xpIntoCurrentLevel) / Double(p.xpForNextLevel), 0), 1)
    }

    private var xpCaption: String {
        "\(profile.xpIntoCurrentLevel.formatted()) / \(profile.xpForNextLevel.formatted()) XP"
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(AppColors.stroke.opacity(0.5))

            // Fill + a slow sheen that travels across the filled portion only,
            // so an empty bar stays completely still. The sweep is driven by a
            // phase animator (not a repeatForever on state), which cannot get
            // stranded mid-travel and leave a static bright band on the bar.
            GeometryReader { geo in
                let fillWidth = max(0, geo.size.width * displayedProgress)
                if fillWidth > 0 {
                    Capsule()
                        .fill(AppColors.accent.opacity(0.3))
                        .frame(width: fillWidth, height: geo.size.height)
                        .overlay(alignment: .leading) { sheen(fillWidth: fillWidth) }
                        .clipShape(Capsule())
                }
            }

            Text(xpCaption)
                .appText(.caption)
                .monospacedDigit()
                .foregroundStyle(AppColors.text)
        }
        .frame(height: 34)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppColors.stroke, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(profile.xpIntoCurrentLevel) of \(profile.xpForNextLevel) experience points"
        )
        .onAppear { seedAndAnimate() }
        .onChange(of: liveProgress) { _, _ in animateToLive() }
    }

    /// Sweeps a soft highlight from just before the fill's leading edge to just
    /// past its trailing edge, then snaps back instantly (zero-duration return
    /// phase) so the travel only ever reads one way. Off under Reduce Motion.
    @ViewBuilder
    private func sheen(fillWidth: CGFloat) -> some View {
        if !reduceMotion {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.accent.opacity(0),
                            AppColors.accent.opacity(0.5),
                            AppColors.accent.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(24, fillWidth * 0.35))
                .phaseAnimator([0, 1]) { view, phase in
                    view.offset(x: phase == 0 ? -fillWidth * 0.4 : fillWidth)
                } animation: { phase in
                    phase == 0 ? .linear(duration: 0) : .linear(duration: 2.4)
                }
        }
    }

    private func seedAndAnimate() {
        if !seeded {
            seeded = true
            displayedProgress = cachedProgress
        }
        animateToLive()
    }

    private func animateToLive() {
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            displayedProgress = liveProgress
        }
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
