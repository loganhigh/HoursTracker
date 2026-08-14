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

/// What earns the badge.
///
/// Reviewing the app, not an hours milestone. Apple exposes no way to confirm
/// a review was actually submitted — `AppStore.requestReview` returns nothing,
/// and App Store Connect's reviews carry nicknames that don't map to accounts
/// — so this records that the user tapped through to the write-review page.
/// It verifies intent, not the review itself; that gap is the price of it
/// being automatic rather than granted by hand.
enum VerifiedTracker {
    /// Set when the user taps through to the App Store review page.
    static let reviewedKey = "has_reviewed_app_v1"

    static var hasReviewedApp: Bool {
        get { UserDefaults.standard.bool(forKey: reviewedKey) }
        set { UserDefaults.standard.set(newValue, forKey: reviewedKey) }
    }

    /// For rows built from a published profile. `isSelf` covers your own row:
    /// the server flag only lands on the next recompute, so without it your
    /// badge would lag your own tap by a shift.
    static func isVerified(reviewed: Bool, isSelf: Bool = false) -> Bool {
        reviewed || (isSelf && hasReviewedApp)
    }

    /// For the signed-in user's own rows, which read the local flag.
    static var isSelfVerified: Bool { hasReviewedApp }
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
