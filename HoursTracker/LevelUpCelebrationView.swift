import SwiftUI

// MARK: - Level-up celebration
//
// The full cinematic level-up moment, staged:
//
//   1. interruption — app dims and blurs behind, badge + old level fade in
//   2. energy build — glow, slight rotation, sparks, escalating haptics
//   3. cinematic    — the bundled Higgsfield emblem-transformation clip
//   4. reveal       — "LEVEL UP" + the new number lands with a haptic
//   5. rewards      — whatever the span actually unlocked (dynamic)
//   6. continue     — user dismisses when ready; nothing auto-dismisses
//
// A multi-level jump (24 → 27) plays the cinematic once, then ticks the
// counter through the intermediate levels with small haptics. Reduce Motion
// replaces the whole sequence with crossfades and a static badge, and skips
// the video. Text is always SwiftUI — the video carries no numbers, so one
// clip serves every level.

struct LevelUpCelebrationView: View {
    let celebration: LevelUpCoordinator.Celebration
    @ObservedObject var animationPlayer: LevelAnimationPlayer
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Stage {
        case interruption, energyBuild, cinematic, reveal, rewards, done
    }

    @State private var stage: Stage = .interruption
    @State private var backdropOpacity: Double = 0
    @State private var badgeVisible = false
    @State private var glow: Double = 0
    @State private var badgeRotation: Double = 0
    @State private var badgeScale: CGFloat = 1
    @State private var sparksActive = false
    @State private var displayedLevel: Int
    @State private var eyebrowText = "Level"
    @State private var levelUpHeaderVisible = false
    @State private var revealBurst: Double = 0
    @State private var rewardsVisible = false
    @State private var buttonVisible = false
    @State private var xpFraction: Double
    @State private var xpBarVisible = true
    @State private var dismissing = false
    /// Set when the cinematic stage started, so a stuck player can't strand
    /// the sequence — reveal fires at the timeout even if no end event came.
    @State private var cinematicWatchdog: Task<Void, Never>?

    private var tier: PrestigeTheme.Tier { celebration.tier }

    init(
        celebration: LevelUpCoordinator.Celebration,
        animationPlayer: LevelAnimationPlayer,
        onContinue: @escaping () -> Void
    ) {
        self.celebration = celebration
        self.animationPlayer = animationPlayer
        self.onContinue = onContinue
        _displayedLevel = State(initialValue: celebration.fromLevel)
        // The bar opens nearly full — the story of "this shift finished the
        // level" — then fills to 100% during the build.
        _xpFraction = State(initialValue: 0.82)
    }

    var body: some View {
        ZStack {
            // Dim + blur over the live app. The app stays visible underneath.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .opacity(backdropOpacity)
            Color.black
                .ignoresSafeArea()
                .opacity(backdropOpacity * 0.62)

            RadialGradient(
                colors: [tier.primary.opacity(0.20), Color.clear],
                center: .center,
                startRadius: 30,
                endRadius: 420
            )
            .ignoresSafeArea()
            .opacity(backdropOpacity * glow)

            if !reduceMotion {
                CelebrationSparkField(active: sparksActive, tint: tier.highlight)
                    .allowsHitTesting(false)
                    .opacity(backdropOpacity)
            }

            VStack(spacing: AppSpacing.lg) {
                Spacer(minLength: 0)

                // "LEVEL UP" header — appears at reveal.
                Text("LEVEL UP")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(tier.highlight)
                    .opacity(levelUpHeaderVisible ? 1 : 0)
                    .offset(y: levelUpHeaderVisible ? 0 : 10)

                // The badge. During the cinematic stage the video replaces it
                // in the same slot, so the transformation reads as happening
                // to this badge.
                ZStack {
                    if stage == .cinematic && animationPlayer.hasAsset {
                        CinematicVideoSurface(player: animationPlayer.player)
                            .frame(width: 300, height: 332)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
                            .transition(.opacity)
                    } else {
                        LevelBadgeView(tier: tier, width: 170, glow: glow) {
                            LevelBadgeNumber(
                                level: displayedLevel,
                                tier: tier,
                                eyebrow: eyebrowText
                            )
                        }
                        .scaleEffect(badgeScale)
                        .rotationEffect(.degrees(badgeRotation))
                        .background(
                            // Reveal burst: a ring that flashes out as the new
                            // level lands.
                            Circle()
                                .stroke(tier.highlight.opacity(0.8), lineWidth: 3)
                                .frame(width: 200, height: 200)
                                .scaleEffect(1 + revealBurst * 1.1)
                                .opacity((1 - revealBurst) * 0.9)
                        )
                        .transition(.opacity)
                    }
                }
                .frame(height: 340)
                .opacity(badgeVisible ? 1 : 0)

                // Rank title — appears with the reveal.
                Text(celebration.rankTitle)
                    .appText(.headline)
                    .foregroundStyle(AppColors.text)
                    .opacity(levelUpHeaderVisible ? 1 : 0)

                // XP bar — fills to full during the build, then shows the
                // real carried-over progress after the reveal.
                xpBar
                    .opacity(xpBarVisible ? 1 : 0)

                if rewardsVisible && !celebration.rewards.isEmpty {
                    LevelRewardView(rewards: celebration.rewards, tier: tier)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(tier.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .fill(tier.primary)
                        )
                }
                .buttonStyle(.plain)
                .opacity(buttonVisible ? 1 : 0)
                .offset(y: buttonVisible ? 0 : 16)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xxl)
                .disabled(!buttonVisible)
            }
            .padding(.horizontal, AppSpacing.lg)
            .scaleEffect(dismissing ? 0.96 : 1)
        }
        .opacity(dismissing ? 0 : 1)
        .onAppear { run() }
        .onChange(of: animationPlayer.didFinish) { _, finished in
            guard finished, stage == .cinematic else { return }
            advanceToReveal()
        }
        .onDisappear { cinematicWatchdog?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Level up. You reached level \(celebration.toLevel), \(celebration.rankTitle).")
    }

    // MARK: XP bar

    private var xpBar: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: tier.gradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * xpFraction))
                }
            }
            .frame(height: 8)

            Text(xpCaption)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.subtext)
        }
        .frame(maxWidth: 260)
    }

    private var xpCaption: String {
        if stage == .rewards || stage == .done {
            return "\(celebration.xpIntoLevel.formatted()) / \(celebration.xpForNextLevel.formatted()) XP"
        }
        return "Level \(celebration.fromLevel) complete"
    }

    // MARK: Sequence

    private func run() {
        if reduceMotion {
            runReduced()
            return
        }

        // Stage 1 — interruption (~0.5s)
        Haptics.lightTap()
        withAnimation(.easeOut(duration: 0.3)) {
            backdropOpacity = 1
        }
        withAnimation(AppMotion.Spring.smooth.delay(0.15)) {
            badgeVisible = true
        }

        // Stage 2 — energy build (~0.9s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard !dismissing else { return }
            stage = .energyBuild
            sparksActive = true
            Haptics.mediumTap()
            withAnimation(.easeIn(duration: 0.85)) {
                glow = 1
                xpFraction = 1
            }
            // A slow lean plus a tightening pulse — "something is coming".
            withAnimation(.easeInOut(duration: 0.85)) {
                badgeRotation = 4
                badgeScale = 1.06
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard !dismissing else { return }
                Haptics.heavyTap()
            }
        }

        // Stage 3 — cinematic
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            guard !dismissing else { return }
            startCinematic()
        }
    }

    private func startCinematic() {
        guard animationPlayer.hasAsset else {
            advanceToReveal()
            return
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            stage = .cinematic
            xpBarVisible = false
        }
        animationPlayer.play()
        CelebrationAudio.shared.play(.levelUp)

        // Watchdog: the clip runs ~2s at its playback rate; if no end event
        // arrives well past that (slow decode, broken asset), reveal anyway.
        cinematicWatchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled, stage == .cinematic else { return }
            advanceToReveal()
        }
    }

    // MARK: Stage 4 — reveal

    private func advanceToReveal() {
        cinematicWatchdog?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            stage = .reveal
            xpBarVisible = true
        }
        glow = 0.65
        badgeRotation = 0
        eyebrowText = "Level"

        let levels = celebration.levelsGained
        if levels == 1 {
            landFinalLevel()
        } else {
            // Multi-level: tick through intermediates quickly, then land.
            tickLevel(next: celebration.fromLevel + 1)
        }
    }

    private func tickLevel(next: Int) {
        guard !dismissing else { return }
        withAnimation(AppMotion.Spring.snappy) {
            displayedLevel = next
        }
        if next >= celebration.toLevel {
            // The counter reached the final level — land it properly.
            landEffects()
            showRewards()
        } else {
            Haptics.lightTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                tickLevel(next: next + 1)
            }
        }
    }

    private func landFinalLevel() {
        displayedLevel = celebration.toLevel
        // scale 0.7 → 1.08 → 1.0 as the number lands.
        badgeScale = 0.7
        withAnimation(AppMotion.Spring.celebratory) {
            badgeScale = 1.08
        }
        withAnimation(AppMotion.Spring.smooth.delay(0.18)) {
            badgeScale = 1.0
        }
        landEffects()
        showRewards()
    }

    /// The shared "new level landed" moment: strong haptic, burst, header.
    private func landEffects() {
        Haptics.success()
        revealBurst = 0
        withAnimation(.easeOut(duration: 0.6)) {
            revealBurst = 1
        }
        withAnimation(AppMotion.Spring.smooth) {
            levelUpHeaderVisible = true
        }
        // Real carried-over XP after the rollover — from the existing system.
        let fraction = celebration.xpForNextLevel > 0
            ? Double(celebration.xpIntoLevel) / Double(celebration.xpForNextLevel)
            : 0
        withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
            xpFraction = min(max(fraction, 0), 1)
        }
    }

    // MARK: Stages 5–6 — rewards, continue

    private func showRewards() {
        withAnimation(AppMotion.Spring.smooth.delay(0.45)) {
            stage = .rewards
            rewardsVisible = true
        }
        withAnimation(AppMotion.Spring.smooth.delay(0.7)) {
            buttonVisible = true
        }
        // Sparks stay active on the final screen — they rain down and vanish
        // behind the Continue button until dismissal.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            stage = .done
        }
    }

    // MARK: Reduce Motion path

    private func runReduced() {
        stage = .reveal
        displayedLevel = celebration.toLevel
        withAnimation(.easeOut(duration: 0.3)) {
            backdropOpacity = 1
            badgeVisible = true
            levelUpHeaderVisible = true
            rewardsVisible = true
            buttonVisible = true
        }
        let fraction = celebration.xpForNextLevel > 0
            ? Double(celebration.xpIntoLevel) / Double(celebration.xpForNextLevel)
            : 0
        xpFraction = min(max(fraction, 0), 1)
        stage = .rewards
        Haptics.success()
        CelebrationAudio.shared.play(.levelUp)
    }

    private func dismiss() {
        guard !dismissing else { return }
        dismissing = true
        Haptics.lightTap()
        withAnimation(.easeInOut(duration: 0.3)) {
            backdropOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            onContinue()
        }
    }
}

// MARK: - Rewards list

struct LevelRewardView: View {
    let rewards: [LevelUpCoordinator.Reward]
    let tier: PrestigeTheme.Tier

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text("Unlocked")
                .appText(.eyebrow)
                .foregroundStyle(AppColors.subtext)

            ForEach(rewards) { reward in
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: reward.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tier.highlight)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                                .fill(tier.primary.opacity(0.16))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(reward.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.text)
                        Text(reward.detail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.subtext)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .stroke(tier.primary.opacity(0.25), lineWidth: 0.5)
                        )
                )
            }
        }
        .frame(maxWidth: 320)
    }
}

// MARK: - Spark field

/// A restrained falling-spark layer — two dozen small tinted points raining
/// from above the badge down to the Continue button, no confetti, no
/// rainbows. The layer renders beneath the celebration's content stack, so a
/// spark reaching the button's band slips behind it; the terminal fade is for
/// the strays that fall beside the button rather than over it.
struct CelebrationSparkField: View {
    let active: Bool
    let tint: Color

    /// Fall band, as fractions of the field's height. The end sits just past
    /// the Continue button's top edge so sparks are covered by it mid-fade.
    private static let topY: Double = 0.10
    private static let endY: Double = 0.93

    private struct Spark {
        let x: Double       // 0…1 horizontal position
        let phase: Double   // 0…1 offset into the fall cycle
        let duration: Double
        let size: CGFloat
        let drift: Double   // horizontal wander over one fall, in points
    }

    private static let sparks: [Spark] = (0..<24).map { i in
        var generator = SeededRandom(seed: UInt64(i) &* 0x9E3779B97F4A7C15)
        return Spark(
            x: generator.next(in: 0.08...0.92),
            phase: generator.next(in: 0...1),
            duration: generator.next(in: 2.6...4.2),
            size: CGFloat(generator.next(in: 2...4.5)),
            drift: generator.next(in: -26...26)
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !active)) { timeline in
            Canvas { context, size in
                guard active else { return }
                let now = timeline.date.timeIntervalSinceReferenceDate
                for spark in Self.sparks {
                    // Continuous cycle: each spark is somewhere mid-fall at
                    // any moment, so the rain has no synchronized waves.
                    let cycle = (now / spark.duration + spark.phase)
                        .truncatingRemainder(dividingBy: 1)
                    // Slight ease-in so the drop reads as gravity.
                    let progress = pow(cycle, 1.35)

                    let y = size.height * (Self.topY + (Self.endY - Self.topY) * progress)
                    let x = size.width * spark.x + spark.drift * progress

                    // Fade in at release, fade out on arrival at the button.
                    let alpha: Double
                    switch cycle {
                    case ..<0.10: alpha = 0.85 * (cycle / 0.10)
                    case 0.90...: alpha = 0.85 * ((1 - cycle) / 0.10)
                    default:      alpha = 0.85
                    }

                    let rect = CGRect(
                        x: x - spark.size / 2,
                        y: y - spark.size / 2,
                        width: spark.size,
                        height: spark.size
                    )
                    context.fill(Circle().path(in: rect), with: .color(tint.opacity(alpha)))
                }
            }
        }
        // Soft ramp on activation, so mid-fall sparks don't pop in abruptly.
        .opacity(active ? 1 : 0)
        .animation(.easeIn(duration: 0.5), value: active)
    }

    /// Deterministic per-spark randomness — a seeded generator keeps the
    /// field identical across appearances.
    private struct SeededRandom {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
        mutating func next(in range: ClosedRange<Double>) -> Double {
            let unit = Double(next() % 10_000) / 10_000
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }
    }
}
