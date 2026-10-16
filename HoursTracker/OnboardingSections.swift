import SwiftUI

// MARK: - Onboarding sections
//
// Hero illustrations, Otto's per-page header, the shared page layouts and the
// page indicator. Tokens + DesignComponents only — semantic colors, Reduce
// Motion honored on every animation. One Otto per page.

// MARK: - Page indicator

/// Quiet dots; the active dot elongates into a capsule.
struct OnboardingPageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AppColors.accent : AppColors.stroke)
                    .frame(width: index == current ? 24 : 8, height: 8)
            }
        }
        .animation(AppMotion.Spring.snappy, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

// MARK: - Shared hero page layout (screens 1–2)
//
// Hero and copy sit together as one vertically-centered group — the copy
// reads as a caption on the illustration rather than as a separate block
// stranded above the button.

struct OnboardingHeroPage<Hero: View>: View {
    let headline: String
    let subline: String
    @ViewBuilder let hero: () -> Hero

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer(minLength: 0)

            hero()
                .padding(.horizontal, AppSpacing.xl)

            OnboardingTitle(title: headline, subline: subline)
                .padding(.horizontal, AppSpacing.xxl)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Page header (setup screens)

/// Centered title + one explanatory line, shared by every page.
struct OnboardingTitle: View {
    let title: String
    let subline: String

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Text(title)
                .appText(.title)
                .foregroundStyle(AppColors.text)
                .multilineTextAlignment(.center)

            Text(subline)
                .appText(.subheadline)
                .foregroundStyle(AppColors.subtext)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Otto above the page title. Pass `.peek` while the keyboard is up so the
/// field and button stay on screen.
struct OnboardingHeader: View {
    let pose: OwlPose
    let title: String
    let subline: String
    var owlSize: OwlView.Size = .form

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            OwlView(pose: pose, size: owlSize)
            OnboardingTitle(title: title, subline: subline)
        }
        .animation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion), value: owlSize)
    }
}

extension View {
    /// The quiet grouped-field card used by the setup forms.
    func onboardingFormCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(AppColors.card2.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .stroke(AppColors.stroke.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

extension OwlView.Size {
    /// Otto on top of the onboarding leaderboard. Taller than companion size
    /// because the raised trophy takes a third of the pose's height.
    static let onboardingTrophy = OwlView.Size(height: 96)
}

// MARK: - Screen 1 hero — meet Otto

/// The owl waving hello. (The mascot is never named in the UI.)
struct OnboardingOttoHero: View {
    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            OwlSpeechBubble(text: "Hey there!", tail: .bottom)
            OwlView(pose: .wave, size: OwlView.Size(height: 190))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("An owl waving hello")
    }
}

// MARK: - Screen 4 — Otto peeking over the avatar

/// Otto peeking up from behind `content` (the avatar circle), his wing tips
/// resting on its top edge.
struct OttoPeekingBehind<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            OwlView(pose: .peek, size: OwlView.Size(height: 58), bobs: false)
                .offset(y: -38)
            content()
        }
    }
}

// MARK: - Screen 2 hero — climbing the leaderboard

/// A four-row leaderboard where "You" climbs from 4th to 2nd. Plays once.
///
/// Rows are absolutely positioned by rank and animate their offset, rather
/// than being reordered inside a stack — a ForEach reorder animates
/// inconsistently, while an explicit offset per rank always slides cleanly.
struct OnboardingLeaderboardHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var climbed = false

    private struct Racer: Identifiable {
        let id: String
        let name: String
        let isYou: Bool
        /// Rank before and after the climb (0-indexed).
        let startRank: Int
        let endRank: Int
        /// Hours before and after. Only "You" changes — the climb has to be
        /// earned by the number going up, not just the row sliding.
        let startHours: String
        let endHours: String
    }

    /// Distance between row origins; `rowVisibleHeight` is the row's own
    /// height, so the gap between rows is the difference.
    private let rowHeight: CGFloat = 58
    private let rowVisibleHeight: CGFloat = 50

    private let racers: [Racer] = [
        Racer(id: "marcus", name: "Marcus", isYou: false,
              startRank: 0, endRank: 0, startHours: "41.5h", endHours: "41.5h"),
        Racer(id: "you", name: "You", isYou: true,
              startRank: 3, endRank: 1, startHours: "30.0h", endHours: "38.0h"),
        Racer(id: "dana", name: "Dana", isYou: false,
              startRank: 1, endRank: 2, startHours: "36.2h", endHours: "36.2h"),
        Racer(id: "priya", name: "Priya", isYou: false,
              startRank: 2, endRank: 3, startHours: "32.8h", endHours: "32.8h")
    ]

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(racers) { racer in
                let rank = climbed ? racer.endRank : racer.startRank
                row(racer, rank: rank)
                    .offset(y: CGFloat(rank) * rowHeight)
            }
        }
        // Offsets don't contribute to intrinsic height, so the stack would
        // otherwise measure one row tall and center — pushing the lower rows
        // out over the copy below. Reserve the full span and pin to the top.
        .frame(height: rowHeight * CGFloat(racers.count - 1) + rowVisibleHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .animation(
            reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.72),
            value: climbed
        )
        .onAppear {
            guard !reduceMotion else {
                climbed = true
                return
            }
            // Plays once. The short delay lets the screen settle first so the
            // climb reads as a change rather than the initial state.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                climbed = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration of climbing a friends leaderboard")
    }

    private func row(_ racer: Racer, rank: Int) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Text("\(rank + 1)")
                .appText(.headline)
                .monospacedDigit()
                .foregroundStyle(rankColor(rank))
                .frame(width: 20)

            Circle()
                .fill(racer.isYou ? AppColors.accent.opacity(0.22) : AppColors.card2)
                .frame(width: 34, height: 34)
                .overlay(
                    Circle().stroke(
                        racer.isYou ? AppColors.accent.opacity(0.55) : AppColors.stroke,
                        lineWidth: 1
                    )
                )
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(racer.isYou ? AppColors.accent : AppColors.subtext)
                )

            Text(racer.name)
                .appText(.headline)
                .foregroundStyle(racer.isYou ? AppColors.text : AppColors.subtext)

            Spacer(minLength: AppSpacing.xs)

            if racer.isYou && climbed {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.positive)
                    .transition(.opacity)
            }

            Text(climbed ? racer.endHours : racer.startHours)
                .appText(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(racer.isYou ? AppColors.text : AppColors.subtext)
        }
        .padding(.horizontal, AppSpacing.sm)
        .frame(height: rowVisibleHeight)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(racer.isYou ? AppColors.accent.opacity(0.14) : AppColors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(
                            racer.isYou ? AppColors.accent.opacity(0.45) : AppColors.stroke,
                            lineWidth: 1
                        )
                )
        )
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 0: return AppColors.rankGold
        case 1: return AppColors.rankSilver
        case 2: return AppColors.rankBronze
        default: return AppColors.faint
        }
    }
}
