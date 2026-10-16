import SwiftUI

// MARK: - OwlView
//
// Draws Otto in one pose. The scarf layer is multiplied with the prestige
// accent (or a screen-scoped override such as a friend's tier) so the scarf
// follows the user's rank while the rest of the owl keeps its fixed palette.
// Purely decorative: hidden from VoiceOver, and the idle bob stops under
// Reduce Motion. One owl per screen.

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
    var bobs: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bobUp = false

    var body: some View {
        ZStack {
            layers(for: pose)
                .id(pose)
                .transition(.opacity)
        }
        .frame(height: size.height)
        .offset(y: bobUp && bobs && !reduceMotion ? -OwlView.bobDistance : 0)
        .animation(AppMotion.animation(.easeInOut(duration: AppMotion.Duration.standard), reduceMotion: reduceMotion), value: pose)
        .accessibilityHidden(true)
        .onAppear {
            guard bobs, !reduceMotion, !bobUp else { return }
            withAnimation(.easeInOut(duration: OwlView.bobPeriod).repeatForever(autoreverses: true)) {
                bobUp = true
            }
        }
    }

    private func layers(for pose: OwlPose) -> some View {
        ZStack {
            Image(pose.assetName)
                .resizable()
                .scaledToFit()
            Image(pose.scarfAssetName)
                .resizable()
                .scaledToFit()
                .colorMultiply(scarfTint ?? AppColors.accent)
        }
    }

    private static let bobDistance: CGFloat = 2
    private static let bobPeriod: Double = 1.8
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
