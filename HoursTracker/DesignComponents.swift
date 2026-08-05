import SwiftUI

// MARK: - Design Components (Phase 1 consolidation)
//
// Shared building blocks expressed in the canonical tokens (DesignTokens.swift).
// All motion honors Reduce Motion via AppMotion helpers / reduce-motion checks.

// MARK: - MetricDisplay
//
// Consolidates CareerStatTile / PayStatTile / AccountStatTile /
// FriendCareerStatTile / WorkSummaryStatTile (formerly byte-identical copies).

struct MetricDisplay: View {
    let icon: String
    let label: String
    let value: String
    /// Icon tint. Defaults to the prestige-aware accent when nil.
    var tint: Color? = nil
    /// Numeral tint. Defaults to primary text when nil (e.g. friend profiles
    /// tint stat numerals with the friend's prestige-tier color).
    var valueTint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint ?? AppColors.accent)
                Text(label)
                    .appText(.metricLabel)
                    .foregroundStyle(AppColors.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(value)
                .appText(.metricValue)
                .foregroundStyle(valueTint ?? AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(AppColors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - AppProgressRing
//
// Consolidates ProgressRing (AchievementsView) + MonthProgressRing (MonthDetailView).

struct AppProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.stroke.opacity(0.65), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(
                    AppColors.accentGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - AppEmptyState
//
// The ONE empty-state design (quiet recipe: 36pt light icon, headline title,
// footnote message). Optional primary / secondary actions.

struct AppEmptyState: View {
    var icon: String = "tray"
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppColors.faint)
            Text(title)
                .appText(.headline)
                .foregroundStyle(AppColors.text)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .appText(.metricLabel)
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.sm)
            }
            if let actionTitle, let action {
                Button(actionTitle) {
                    Haptics.lightTap()
                    action()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, AppSpacing.xxs)
            }
            if let secondaryActionTitle, let secondaryAction {
                Button(secondaryActionTitle) {
                    Haptics.lightTap()
                    secondaryAction()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity)
        .gentleFadeIn()
    }
}

// MARK: - AppLoadingState
//
// One loading treatment for full-screen / section loading (inline button
// spinners stay as plain ProgressView). Reduce Motion handled by
// SoftLoadingIndicator.

struct AppLoadingState: View {
    var message: String = "Loading…"

    var body: some View {
        SoftLoadingIndicator(title: message)
    }
}

// MARK: - AppErrorState
//
// One error treatment (pattern extracted from FriendsBoardView.errorState).

struct AppErrorState: View {
    var title: String = "Something went wrong"
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppColors.negative)
            Text(title)
                .appText(.headline)
                .foregroundStyle(AppColors.text)
                .multilineTextAlignment(.center)
            Text(message)
                .appText(.metricLabel)
                .foregroundStyle(AppColors.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)
            if let retry {
                Button("Try again") {
                    Haptics.lightTap()
                    retry()
                }
                .buttonStyle(.bordered)
                .tint(AppColors.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gentleFadeIn()
    }
}

// MARK: - Button styles
//
// PrimaryButton look + PremiumPressStyle press behavior, reduce-motion aware.

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(AppColors.textOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                // Quiet primary: flat accent fill, no glow — cards own their
                // screens' single glow, buttons never do.
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.accent)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(AppMotion.Spring.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(AppColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.accent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(AppColors.accent.opacity(0.25), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(AppMotion.Spring.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - SectionEyebrow
//
// Centered small-caps section header (extracted from RootView.homeSection).

struct SectionEyebrow: View {
    let title: String
    var subtitle: String? = nil

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .appText(.eyebrow)
                .foregroundStyle(AppColors.subtext)
            if let subtitle {
                Text(subtitle)
                    .appText(.caption)
                    .foregroundStyle(AppColors.faint)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
