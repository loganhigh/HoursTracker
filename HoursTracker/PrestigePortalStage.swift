import SwiftUI

// MARK: - Prestige portal
//
// The opening act of the prestige celebration: the OLD emblem is presented on
// a central card, crushed in on itself to a point — a beat of dark — then
// detonates outward, and
// the parent's normal reveal takes over with the NEW badge. All geometry and
// timing live here; PrestigeCelebrationView just mounts it and waits for
// `onFinished`.
//
// Never shown under Reduce Motion — the parent skips straight to its
// standard reveal.

struct PrestigePortalStage: View {
    let oldTier: PrestigeTheme.Tier
    let oldPrestige: Int
    let newTier: PrestigeTheme.Tier
    var onFinished: () -> Void

    /// 0 → card presented, 1 → emblem fully absorbed.
    @State private var absorb: CGFloat = 0
    @State private var cardVisible = false
    /// The detonation ring + flash.
    @State private var burstScale: CGFloat = 0.1
    @State private var burstOpacity: Double = 0

    var body: some View {
        ZStack {
            // --- The old emblem, being taken -------------------------------
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(oldTier.primary.opacity(0.16))
                        .frame(width: 110, height: 110)
                    Circle()
                        .stroke(oldTier.primary.opacity(0.5), lineWidth: 2)
                        .frame(width: 110, height: 110)
                    Image(systemName: oldTier.icon)
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(oldTier.primary)
                }
                // Crushed into the singularity: shrink, spin, smear, vanish.
                .scaleEffect(max(0.02, 1 - absorb))
                .rotationEffect(.degrees(Double(absorb) * 540))
                .blur(radius: absorb * 8)
                .opacity(Double(1 - absorb * absorb))

                VStack(spacing: 4) {
                    Text(oldPrestige == 0 ? "CURRENT RANK" : "PRESTIGE \(oldPrestige)")
                        .font(.system(.footnote, design: .rounded, weight: .black))
                        .tracking(3)
                        .foregroundStyle(AppColors.textOnAccent.opacity(0.8))
                    Text(oldTier.name)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(AppColors.textOnAccent.opacity(0.55))
                }
                // The label sinks away as the emblem goes.
                .opacity(Double(1 - absorb))
                .offset(y: absorb * 18)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(AppColors.stroke, lineWidth: 0.5)
                    )
            )
            // The card itself is consumed at the end of the absorption.
            .scaleEffect(cardVisible ? (1 - absorb * 0.45) : 0.8)
            .opacity(cardVisible ? Double(1 - absorb * 0.9) : 0)

            // --- Detonation -------------------------------------------------
            ZStack {
                Circle()
                    .stroke(newTier.highlight, lineWidth: 3)
                    .frame(width: 130, height: 130)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.9), newTier.primary.opacity(0.4), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 120
                        )
                    )
                    .frame(width: 200, height: 200)
            }
            .scaleEffect(burstScale)
            .opacity(burstOpacity)
            .allowsHitTesting(false)
        }
        .onAppear(perform: run)
    }

    /// One fixed score, conducted with the same asyncAfter staging as the
    /// celebration it hands off to. ~3.1s end to end.
    private func run() {
        // Present the card holding the old rank.
        withAnimation(AppMotion.Spring.smooth) { cardVisible = true }
        Haptics.lightTap()

        // The implosion takes hold — the emblem is crushed in on itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            Haptics.mediumTap()
            // Slow grip, violent finish.
            withAnimation(.easeIn(duration: 1.15)) { absorb = 1 }
        }

        // A breath of black at full collapse before the bang.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) {
            Haptics.heavyTap()
        }

        // Detonate outward, then hand the reveal to the parent while the
        // flash is still washing out — the new badge lands inside it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.35) {
            Haptics.heavyTap()
            withAnimation(.easeOut(duration: 0.55)) {
                burstScale = 5
                burstOpacity = 1
            }
            withAnimation(.easeIn(duration: 0.35).delay(0.3)) {
                burstOpacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.75) {
            onFinished()
        }
    }
}
