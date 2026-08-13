import SwiftUI

// MARK: - Verified badge
//
// A SwiftUI port of the supplied VerifiedBadge component: a scalloped seal in
// the familiar verified blue with a white check, optionally sweeping a
// shimmer across itself.
//
// The web version masks a hand-authored SVG scallop path. `checkmark.seal.fill`
// is the same shape as a system symbol, so it stays crisp at any size, tracks
// Dynamic Type, and needs no path data to keep in sync — the shimmer is then
// masked by the symbol exactly as the original masks its SVG.

/// Lifetime-hours milestone that earns the badge.
enum VerifiedTracker {
    static let hoursThreshold: Double = 1000

    static func isVerified(hours: Double) -> Bool {
        hours >= hoursThreshold
    }
}

struct VerifiedBadgeView: View {
    enum Variant {
        /// Sweeps a highlight across the badge on a loop.
        case shimmer
        /// No animation. The right choice in dense lists, where a per-row
        /// timeline would mean one clock per visible row.
        case `static`
    }

    var variant: Variant = .shimmer
    var size: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// hsl(203, 89%, 57%) from the original, i.e. the standard verified blue.
    private static let badgeBlue = Color(red: 0.114, green: 0.631, blue: 0.949)

    /// One sweep, then a pause, matching the source's 0.5s sweep and 1.5s
    /// repeatDelay.
    private static let sweepDuration: Double = 0.5
    private static let cycleDuration: Double = 2.0

    private var seal: some View {
        Image(systemName: "checkmark.seal.fill")
            .resizable()
            .scaledToFit()
    }

    var body: some View {
        seal
            .foregroundStyle(Self.badgeBlue)
            .frame(width: size, height: size)
            .overlay { shimmer }
            .accessibilityLabel("Verified")
    }

    @ViewBuilder
    private var shimmer: some View {
        if variant == .shimmer && !reduceMotion {
            TimelineView(.animation) { timeline in
                let cycle = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: Self.cycleDuration)
                // Parked off the leading edge for the rest of the cycle, so the
                // badge sits clean between sweeps.
                let progress = min(cycle / Self.sweepDuration, 1)
                let eased = progress * progress * (3 - 2 * progress) // smoothstep

                LinearGradient(
                    colors: [.clear, .white.opacity(0.55), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: size * 0.9)
                .offset(x: -size + (size * 2) * eased)
                .frame(width: size, height: size)
                // Clipped to the seal itself, the same role the SVG mask plays
                // in the original.
                .mask { seal.frame(width: size, height: size) }
            }
            .allowsHitTesting(false)
        }
    }
}
