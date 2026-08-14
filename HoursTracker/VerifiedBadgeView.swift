import SwiftUI
import FirebaseFirestore
import Combine

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
/// Reviewing the app — but granted by hand, not by the client. Apple exposes no
/// way to confirm a review was actually submitted (`AppStore.requestReview`
/// returns nothing, and App Store Connect's reviews carry nicknames that don't
/// map to accounts), so anything the app could detect on its own would verify
/// intent at best. Instead the user emails a screenshot of their review, and
/// the mark is granted on `users/{uid}.hasReviewedApp`, which the recompute
/// publishes to `publicProfiles`.
///
/// The client deliberately never *writes* that field: its `false` would
/// overwrite each grant on the very next profile sync.
enum VerifiedTracker {
    /// For rows built from a published profile.
    static func isVerified(reviewed: Bool) -> Bool { reviewed }

    /// Where proof of a review is sent.
    static let proofRecipient = "trackedhours@gmail.com"
}

/// Watches the signed-in user's own published profile for the verified flag.
///
/// Their own rows read the same document everyone else does, so what they see
/// is exactly what other users see — no local mirror to drift out of sync with
/// a hand-granted mark.
@MainActor
final class VerifiedStatusService: ObservableObject {
    static let shared = VerifiedStatusService()

    @Published private(set) var isVerified = false

    private var listener: ListenerRegistration?
    private var activeUid: String?

    private init() {}

    func startListening(uid: String) {
        guard activeUid != uid else { return }
        stopListening()
        activeUid = uid
        listener = Firestore.firestore().collection("publicProfiles").document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.activeUid == uid else { return }
                    if let error {
                        FirestoreOperationLog.listenerError(
                            owner: .cloudSync,
                            purpose: "publicProfiles.verified",
                            uid: uid,
                            error: error
                        )
                        return
                    }
                    self.isVerified = snapshot?.data()?["hasReviewedApp"] as? Bool ?? false
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        activeUid = nil
        isVerified = false
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
    static let badgeBlue = Color(red: 0.114, green: 0.631, blue: 0.949)

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
