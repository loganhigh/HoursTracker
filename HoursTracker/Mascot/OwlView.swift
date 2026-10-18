import SwiftUI

// MARK: - OwlView
//
// Draws Otto in one pose. The scarf layer is multiplied with the prestige
// accent (or a screen-scoped override such as a friend's tier) so the scarf
// follows the user's rank while the rest of the owl keeps its fixed palette.
// Purely decorative: hidden from VoiceOver. Each pose has its own idle
// motion (OwlMotion) that stops under Reduce Motion. One owl per screen.

struct OwlView: View {
    struct Size: Equatable {
        let height: CGFloat

        /// Onboarding, celebrations, paywall, tip jar, Welcome Back.
        static let hero = Size(height: 150)
        /// Inside AppEmptyState.
        static let emptyState = Size(height: 120)
        /// Above a short form (onboarding setup pages).
        static let form = Size(height: 88)
        /// Perched on a tab's hero card with a speech bubble.
        static let companion = Size(height: 76)
        /// Beside the title in a custom sheet header (add shift, wage prompt).
        static let header = Size(height: 56)
        /// Peeking over the first card on sheets and editors.
        static let peek = Size(height: 44)
    }

    let pose: OwlPose
    var size: Size = .companion
    /// Overrides the prestige accent for the scarf (friend profiles use the friend's tier).
    var scarfTint: Color? = nil
    /// False keeps the owl still (dense or repeated placements).
    var bobs: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var tapTime: Date?
    /// Desynchronises owls that appear together.
    @State private var seed = Double.random(in: 0..<10)

    private var animates: Bool { bobs && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate + seed
            let tap = tapTime.map { timeline.date.timeIntervalSince($0) } ?? .infinity
            let f = bodyFrame(t: t, sinceTap: tap)
            ZStack {
                layers(for: pose, t: t, sinceTap: tap)
                    .id(pose)
                    .transition(.opacity)
            }
            .scaleEffect(x: f.scaleX, y: f.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(f.angle), anchor: .bottom)
            .offset(y: f.dy)
        }
        .frame(height: size.height)
        .scaleEffect(appeared || !animates ? 1 : 0.85, anchor: .bottom)
        .opacity(appeared || !animates ? 1 : 0)
        .onAppear {
            guard animates, !appeared else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { appeared = true }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            guard animates else { return }
            Haptics.lightTap()
            tapTime = Date()
        })
        .animation(AppMotion.animation(.easeInOut(duration: AppMotion.Duration.standard), reduceMotion: reduceMotion), value: pose)
        .accessibilityHidden(true)
    }

    // MARK: Motion

    private var rig: OwlRig { OwlRig.forPose(pose) }

    private func bodyFrame(t: Double, sinceTap: Double) -> OwlMotion.Frame {
        guard animates else { return .init() }
        let body = OwlMotion.body(for: pose)
        var f = OwlMotion.bodyFrame(body, at: t, height: size.height)
        // A tap on a hopping pose adds an extra hop.
        if body == .hop, sinceTap < 0.45 {
            let u = sinceTap / 0.45
            f.dy -= 12 * (size.height / 150) * OwlMotion.bump(u, 0.1, 0.65)
            f.scaleY *= 1 - 0.1 * OwlMotion.bump(u, 0, 0.12) - 0.06 * OwlMotion.bump(u, 0.78, 0.22)
        }
        return f
    }

    private func blink(t: Double, sinceTap: Double) -> Double {
        guard animates else { return 0 }
        // A tap gets an immediate blink.
        return max(OwlMotion.blink(at: t), OwlMotion.bump(sinceTap, 0, 0.16))
    }

    private func wingAngle(t: Double, sinceTap: Double) -> Double {
        guard animates, let wing = OwlMotion.wing(for: pose) else { return 0 }
        // A tap plays the wing move straight away.
        // (Each wing cycle starts with its move, so time-since-tap replays it.)
        if sinceTap < 0.6 { return OwlMotion.wingAngle(wing, at: sinceTap) }
        return OwlMotion.wingAngle(wing, at: t)
    }

    // MARK: Layers

    private func layers(for pose: OwlPose, t: Double, sinceTap: Double) -> some View {
        let rig = self.rig
        return ZStack {
            Image(rig.wingPivot == nil ? pose.assetName : "\(pose.assetName)-base")
                .resizable()
                .scaledToFit()
                .overlay {
                    if !rig.eyes.isEmpty {
                        OwlEyelids(rig: rig, closed: blink(t: t, sinceTap: sinceTap))
                    }
                }
            Image(pose.scarfAssetName)
                .resizable()
                .scaledToFit()
                .colorMultiply(scarfTint ?? AppColors.accent)
            if let pivot = rig.wingPivot {
                Image("\(pose.assetName)-wing")
                    .resizable()
                    .scaledToFit()
                    .rotationEffect(.degrees(wingAngle(t: t, sinceTap: sinceTap)), anchor: pivot)
            }
        }
    }
}

#Preview("Otto poses") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: AppSpacing.lg) {
            ForEach(OwlPose.allCases, id: \.self) { pose in
                VStack(spacing: AppSpacing.xs) {
                    OwlView(pose: pose, size: .emptyState)
                    Text(pose.rawValue)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
            }
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.bg)
    .preferredColorScheme(.dark)
}
