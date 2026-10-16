import SwiftUI

// MARK: - Home overlays
//
// The prompts and celebrations Home (and RootView) lay over the app, plus the
// Prestige info sheet. Moved out of RootView for the owl redesign: each one
// leads with an owl pose instead of an emoji, sits on a quiet card (hairline
// stroke, no glow), and keeps its original timing, haptics and callbacks.

// MARK: - Prompt card

/// Scrim + centered card with the owl peeking over its top edge. Shared by the
/// announcement and country-flag prompts (custom rather than `.alert`, which
/// left-aligns its text on iOS 26).
struct HomePromptCard<Actions: View>: View {
    let pose: OwlPose
    let title: String
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ZStack {
            AppColors.overlay
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.md) {
                OnboardingTitle(title: title, subline: message)
                actions()
            }
            .padding(AppSpacing.lg)
            .padding(.top, AppSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(AppColors.stroke, lineWidth: 1)
                    )
            )
            .owlPeek(pose, size: .companion, alignment: .center)
            .padding(.horizontal, AppSpacing.xxl)
        }
        .transition(.opacity)
    }
}

struct AnnouncementPromptOverlay: View {
    let announcement: Announcement
    /// true = primary button (update / got it), false = "Not Now".
    var onFinish: (Bool) -> Void

    var body: some View {
        HomePromptCard(
            pose: announcement.isUpdatePrompt ? .point : .bell,
            title: announcement.title,
            message: announcement.message
        ) {
            Button(announcement.buttonTitle) {
                Haptics.lightTap()
                onFinish(true)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, AppSpacing.xxs)

            Button("Not Now") {
                Haptics.lightTap()
                onFinish(false)
            }
            .font(AppTypography.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.subtext)
        }
    }
}

/// Picking a country is required, so there is one button and no way to
/// dismiss around it.
struct CountryFlagPromptOverlay: View {
    let onChoose: () -> Void

    var body: some View {
        HomePromptCard(
            pose: .pin,
            title: "Add a country flag",
            message: "Pick your country so your flag shows beside your name on the global leaderboard."
        ) {
            Button("Choose country") {
                Haptics.lightTap()
                onChoose()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, AppSpacing.xxs)
        }
    }
}

// MARK: - Floating XP gain

struct FloatingXPGainView: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.7

    var body: some View {
        Text(text)
            .font(AppTypography.metricValue.weight(.black))
            .foregroundStyle(AppColors.gold)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(AppColors.card)
                    .overlay(Capsule().stroke(AppColors.gold.opacity(0.4), lineWidth: 1))
            )
            .appShadowRaised()
            .scaleEffect(scale)
            .offset(y: offsetY)
            .opacity(opacity)
            .onAppear {
                if reduceMotion {
                    // Fade only — no pop, no float.
                    opacity = 1
                    scale = 1.0
                    withAnimation(.easeIn(duration: 0.45).delay(2.0)) {
                        opacity = 0
                    }
                    return
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    opacity = 1
                    scale = 1.0
                }
                withAnimation(.easeOut(duration: 1.8).delay(0.1)) {
                    offsetY = -30
                }
                withAnimation(.easeIn(duration: 0.45).delay(2.0)) {
                    opacity = 0
                }
            }
    }
}

// MARK: - Personal best banner

struct PersonalBestBanner: View {
    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            OwlView(pose: .trophy, size: OwlView.Size(height: 36), bobs: false)
            Text("New personal best month!")
                .appText(.headline)
                .foregroundStyle(AppColors.text)
        }
        .padding(.leading, AppSpacing.sm)
        .padding(.trailing, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xs)
        .background(
            Capsule()
                .fill(AppColors.card)
                .overlay(Capsule().stroke(AppColors.gold.opacity(0.45), lineWidth: 1))
        )
        .appShadowRaised()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Streak milestone burst

struct StreakBurstView: View {
    let streakCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles: [BurstParticle] = []

    struct BurstParticle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var targetX: CGFloat
        var targetY: CGFloat
        var color: Color
        var size: CGFloat
        var opacity: Double
    }

    var body: some View {
        ZStack {
            AppColors.overlay.ignoresSafeArea()

            VStack(spacing: AppSpacing.sm) {
                ZStack {
                    ForEach(particles) { p in
                        Circle()
                            .fill(p.color)
                            .frame(width: p.size, height: p.size)
                            .opacity(p.opacity)
                            .offset(x: p.x, y: p.y)
                    }
                    OwlView(pose: .streak, size: .hero)
                }
                .frame(height: OwlView.Size.hero.height + AppSpacing.md)

                VStack(spacing: AppSpacing.xxs) {
                    Text("\(streakCount) day streak")
                        .font(AppTypography.title.weight(.black))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.text)
                    Text("You're on fire. Keep it up!")
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .fill(AppColors.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                .stroke(AppColors.streak.opacity(0.4), lineWidth: 1)
                        )
                )
            }
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !reduceMotion else { return } // owl + text only, no burst
            spawnParticles()
        }
    }

    private func spawnParticles() {
        let colors: [Color] = [AppColors.streak, AppColors.gold, AppColors.goldDeep, AppColors.warning]
        particles = (0..<24).map { _ in
            let angle = CGFloat.random(in: 0 ..< .pi * 2)
            let dist = CGFloat.random(in: 70...150)
            return BurstParticle(
                x: 0, y: 0,
                targetX: cos(angle) * dist,
                targetY: sin(angle) * dist,
                color: colors.randomElement()!,
                size: CGFloat.random(in: 6...12),
                opacity: 1.0
            )
        }
        withAnimation(.easeOut(duration: 0.8)) {
            for i in particles.indices {
                particles[i].x = particles[i].targetX
                particles[i].y = particles[i].targetY
            }
        }
        withAnimation(.easeIn(duration: 0.6).delay(1.2)) {
            for i in particles.indices {
                particles[i].opacity = 0
            }
        }
    }
}

// MARK: - Payday confetti

struct PaydayConfettiOverlay: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false
    @State private var visible = true
    @State private var badgeScale: CGFloat = 0.4
    @State private var badgeOpacity: Double = 0

    var body: some View {
        ZStack {
            AppColors.overlay
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            ConfettiLayer(active: burst)
                .allowsHitTesting(false)

            VStack(spacing: AppSpacing.md) {
                OwlView(pose: .cheer, size: .hero)

                VStack(spacing: AppSpacing.xs) {
                    Text("Payday!")
                        .font(AppTypography.heroNumber)
                        .foregroundStyle(AppColors.gold)

                    Text("You earned it. Go get it.")
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Let's go!")
                        .font(AppTypography.button)
                        .foregroundStyle(AppColors.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .fill(AppColors.gold)
                        )
                }
                .buttonStyle(InteractiveButtonStyle())
                .padding(.top, AppSpacing.xxs)
            }
            .padding(AppSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .fill(AppColors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                            .stroke(AppColors.gold.opacity(0.35), lineWidth: 1)
                    )
            )
            .padding(.horizontal, AppSpacing.xxl)
            .scaleEffect(badgeScale)
            .opacity(badgeOpacity)
        }
        .opacity(visible ? 1 : 0)
        .onAppear {
            if reduceMotion {
                // Static card: no pop-in spring. (ConfettiLayer already renders
                // nothing under Reduce Motion, and the owl doesn't bob.)
                burst = true
                badgeScale = 1.0
                badgeOpacity = 1.0
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                    burst = true
                    badgeScale = 1.0
                    badgeOpacity = 1.0
                }
            }
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                dismiss()
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            visible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onDismiss()
        }
    }
}

// MARK: - Prestige info sheet

struct PrestigeInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentPrestige: Int

    private var tiers: [(level: Int, icon: String, title: String, color: Color)] {
        PrestigeTheme.tiers.map { tier in
            (
                level: tier.prestige,
                icon: tier.icon,
                title: tier.name,
                color: tier.prestige == 0 ? AppColors.faint : tier.primary
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    VStack(spacing: AppSpacing.sm) {
                        OwlView(pose: .crown, size: .form)
                        OnboardingTitle(
                            title: "What is Prestige?",
                            subline: "Hit Level 25 to Prestige. Your level resets, your rank goes up."
                        )
                        .padding(.horizontal, AppSpacing.md)
                    }
                    .padding(.top, AppSpacing.xs)

                    VStack(spacing: 6) {
                        SectionEyebrow("How it works")

                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            infoRow(icon: "arrow.up.circle.fill", text: "Reach Level 25 to Prestige")
                            infoRow(icon: "arrow.counterclockwise.circle.fill", text: "Level resets to 1, rank goes up")
                            infoRow(icon: "crown.fill", text: "\(GamificationLevelCalculator.maxPrestige) ranks — past Prestige Master comes Legend Status, up to \(PrestigeTheme.tier(for: GamificationLevelCalculator.maxPrestige).name)")
                        }
                        .padding(AppSpacing.md)
                        .background(quietCard)
                    }

                    VStack(spacing: 6) {
                        SectionEyebrow("Prestige ranks")

                        VStack(spacing: 0) {
                            ForEach(tiers, id: \.level) { tier in
                                tierRow(tier)

                                if tier.level == 10 {
                                    // Section break into the Legend family (P11+).
                                    HStack(spacing: AppSpacing.xs) {
                                        Rectangle().fill(AppColors.stroke).frame(height: 0.5)
                                        Text("Legend status")
                                            .appText(.eyebrow)
                                            .foregroundStyle(AppColors.subtext)
                                            .fixedSize()
                                        Rectangle().fill(AppColors.stroke).frame(height: 0.5)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, AppSpacing.xs)
                                } else if tier.level < GamificationLevelCalculator.maxPrestige {
                                    Divider().overlay(AppColors.stroke.opacity(0.5))
                                }
                            }
                        }
                        .background(quietCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xxl)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Prestige")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var quietCard: some View {
        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            .fill(AppColors.card2)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColors.stroke, lineWidth: 0.5)
            )
    }

    private func tierRow(_ tier: (level: Int, icon: String, title: String, color: Color)) -> some View {
        let isCurrent = tier.level == currentPrestige
        return HStack(spacing: AppSpacing.sm) {
            Image(systemName: tier.icon)
                .font(.system(.callout, weight: .bold))
                .foregroundStyle(tier.color)
                .legendShimmer(PrestigeTheme.tier(for: tier.level))
                .frame(width: 24)

            Text("P\(tier.level)")
                .font(.system(.footnote, design: .rounded, weight: .black))
                .foregroundStyle(tier.color)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 36, alignment: .leading)

            Text(tier.title)
                .font(AppTypography.subheadline.weight(.semibold))
                .foregroundStyle(isCurrent ? AppColors.text : AppColors.subtext)

            Spacer()

            if isCurrent {
                // Quiet tinted pill, not a saturated fill.
                Text("You")
                    .appText(.eyebrow)
                    .foregroundStyle(tier.color)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(tier.color.opacity(0.14))
                            .overlay(Capsule().stroke(tier.color.opacity(0.4), lineWidth: 1))
                    )
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            isCurrent
                ? RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tier.color.opacity(0.1))
                : nil
        )
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 22)
            Text(text)
                .appText(.subheadline)
                .foregroundStyle(AppColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
