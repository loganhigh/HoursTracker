import SwiftUI
import AVFoundation

/// Full-screen prestige unlock moment — tier-themed visuals, staged reveal, and confetti.
struct PrestigeCelebrationView: View {
    let prestige: Int
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var backdropOpacity: Double = 0
    @State private var headerVisible = false
    @State private var emblemScale: CGFloat = 0.35
    @State private var emblemOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0
    @State private var detailsVisible = false
    @State private var confettiActive = false
    @State private var buttonVisible = false
    @State private var dismissing = false
    @State private var player: AVAudioPlayer?

    private var tier: PrestigeTheme.Tier { PrestigeTheme.tier(for: prestige) }
    private var previousTier: PrestigeTheme.Tier { PrestigeTheme.tier(for: max(0, prestige - 1)) }

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    tier.primary.opacity(0.28),
                    tier.accent2.opacity(0.12),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()
            .opacity(backdropOpacity)

            if !reduceMotion {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [tier.highlight, tier.primary.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 220 + CGFloat(index * 36), height: 220 + CGFloat(index * 36))
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity * (1 - Double(index) * 0.22))
                }
            }

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                VStack(spacing: 10) {
                    Text("PRESTIGE UNLOCKED")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(3.5)
                        .foregroundStyle(tier.highlight)
                        .opacity(headerVisible ? 1 : 0)
                        .offset(y: headerVisible ? 0 : 12)

                    prestigeEmblem
                        .scaleEffect(emblemScale)
                        .opacity(emblemOpacity)

                    VStack(spacing: 8) {
                        Text(tier.name)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text(rankTransitionLabel)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))

                        Text(Self.tagline(for: prestige))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .padding(.top, 4)
                    }
                    .opacity(detailsVisible ? 1 : 0)
                    .offset(y: detailsVisible ? 0 : 16)

                    HStack(spacing: 8) {
                        perkChip(icon: "paintpalette.fill", label: "New theme")
                        perkChip(icon: "medal.fill", label: "P\(prestige) badge")
                        perkChip(icon: "arrow.triangle.2.circlepath", label: "Fresh grind")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .opacity(detailsVisible ? 1 : 0)
                    .offset(y: detailsVisible ? 0 : 20)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .background(celebrationCardBackground)
                .padding(.horizontal, 20)
                .scaleEffect(dismissing ? 0.92 : 1)
                .opacity(dismissing ? 0 : 1)

                Spacer(minLength: 24)

                Button {
                    dismissCelebration()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Claim Your Rank")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [tier.highlight, tier.primary, tier.accent2],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: tier.primary.opacity(0.45), radius: 14, y: 6)
                }
                .buttonStyle(InteractiveButtonStyle())
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .opacity(buttonVisible ? 1 : 0)
                .offset(y: buttonVisible ? 0 : 24)
            }

            if !reduceMotion {
                ConfettiLayer(active: confettiActive, palette: tier.confettiColors, pieceCount: 64)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            playCelebrationSound()
            runCelebrationSequence()
        }
    }

    private var prestigeEmblem: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tier.highlight.opacity(0.45), tier.primary.opacity(0.05)],
                        center: .center,
                        startRadius: 8,
                        endRadius: 58
                    )
                )
                .frame(width: 132, height: 132)

            Circle()
                .stroke(
                    LinearGradient(colors: tier.gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 3.5
                )
                .frame(width: 112, height: 112)

            VStack(spacing: 4) {
                Image(systemName: tier.icon)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: tier.gradient, startPoint: .top, endPoint: .bottom)
                    )

                Text("P\(prestige)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .shadow(color: tier.primary.opacity(0.5), radius: 10)
        }
    }

    private var celebrationCardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.55))
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [tier.highlight.opacity(0.55), tier.primary.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .shadow(color: tier.primary.opacity(0.35), radius: 28, y: 10)
    }

    private var rankTransitionLabel: String {
        if prestige <= 1 {
            return "Welcome to \(tier.name)"
        }
        return "\(previousTier.name) → \(tier.name)"
    }

    private func perkChip(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tier.highlight)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tier.primary.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tier.primary.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func runCelebrationSequence() {
        if reduceMotion {
            backdropOpacity = 0.82
            headerVisible = true
            emblemScale = 1
            emblemOpacity = 1
            detailsVisible = true
            buttonVisible = true
            confettiActive = true
            Haptics.success()
            return
        }

        Haptics.success()

        withAnimation(.easeOut(duration: 0.25)) {
            backdropOpacity = 0.82
        }

        withAnimation(AppMotion.Spring.celebratory.delay(0.12)) {
            headerVisible = true
            emblemScale = 1.08
            emblemOpacity = 1
        }

        withAnimation(AppMotion.Spring.smooth.delay(0.28)) {
            emblemScale = 1
        }

        withAnimation(.easeOut(duration: 1.0).delay(0.18)) {
            ringScale = 2.4
            ringOpacity = 0.85
        }

        withAnimation(.easeIn(duration: 0.45).delay(0.85)) {
            ringOpacity = 0
        }

        withAnimation(AppMotion.Spring.smooth.delay(0.42)) {
            detailsVisible = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            Haptics.mediumTap()
        }

        withAnimation(AppMotion.Spring.celebratory.delay(0.58)) {
            confettiActive = true
        }

        withAnimation(AppMotion.Spring.smooth.delay(0.82)) {
            buttonVisible = true
        }
    }

    private func dismissCelebration() {
        guard !dismissing else { return }
        dismissing = true
        Haptics.lightTap()
        withAnimation(.easeInOut(duration: 0.28)) {
            backdropOpacity = 0
            buttonVisible = false
            confettiActive = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }

    private func playCelebrationSound() {
        guard let url = Bundle.main.url(forResource: "level_up", withExtension: "caf") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 1.0
        player?.play()
    }

    private static func tagline(for prestige: Int) -> String {
        switch prestige {
        case 1: return "The grind never stops — it evolves."
        case 2: return "Silver earned. Keep stacking hours."
        case 3: return "Gold status. You're built different."
        case 4: return "Platinum tier. Elite dedication."
        case 5: return "Diamond rank. Pure consistency."
        case 6: return "Master status unlocked."
        case 7: return "Grandmaster. Legends are watching."
        case 8: return "Champion. Top of the board."
        case 9: return "Legendary. Almost at the summit."
        case 10: return "Prestige Master. The ultimate rank."
        default: return "Your journey continues."
        }
    }
}

private extension PrestigeTheme.Tier {
    var confettiColors: [Color] {
        gradient + [highlight, primary, accent2]
    }
}
