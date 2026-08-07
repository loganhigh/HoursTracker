import SwiftUI

// MARK: - Onboarding sections
//
// Hero illustrations for the three onboarding screens plus the shared page
// indicator. Tokens + DesignComponents only — semantic colors, Reduce Motion
// honored on every animation.

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

// MARK: - Screen 1 hero — the app logo

/// The Hour Tracker mark on a light tile so the chrome lettering keeps its
/// contrast against the dark app background, with soft depth layers behind
/// and a gentle idle float.
struct OnboardingLogoHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 168, height: 168)
            .padding(AppSpacing.lg)
            .background(
                ZStack {
                    depthLayer(offset: 26, scale: 0.88, opacity: 0.16)
                    depthLayer(offset: 13, scale: 0.94, opacity: 0.34)
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .fill(Color.white)
                }
            )
            .offset(y: floating ? -5 : 5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                    floating = true
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hour Tracker")
    }

    private func depthLayer(offset: CGFloat, scale: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 44, style: .continuous)
            .fill(AppColors.card2)
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(y: offset)
    }
}

// MARK: - Screen 2 hero — feature cards

/// Stacked feature cards, each revealing in sequence.
struct OnboardingFeatureCards: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
    }

    private let features: [Feature] = [
        Feature(
            icon: "clock.fill",
            title: "Log shifts in seconds",
            subtitle: "Enter times by hand or track live."
        ),
        Feature(
            icon: "calendar",
            title: "Every cheque, organized",
            subtitle: "Pay periods and overtime, handled for you."
        ),
        Feature(
            icon: "rosette",
            title: "Earn XP and badges",
            subtitle: "Level up and climb toward Prestige."
        ),
        Feature(
            icon: "person.2.fill",
            title: "Compete with friends",
            subtitle: "Weekly standings keep you accountable."
        )
    ]

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                card(feature)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 14)
                    .animation(
                        reduceMotion ? nil : AppMotion.Spring.smooth.delay(Double(index) * 0.08),
                        value: revealed
                    )
            }
        }
        .onAppear { revealed = true }
    }

    private func card(_ feature: Feature) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: feature.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .fill(AppColors.accent.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .appText(.headline)
                    .foregroundStyle(AppColors.text)
                Text(feature.subtitle)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
        )
    }
}
