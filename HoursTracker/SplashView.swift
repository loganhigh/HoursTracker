import SwiftUI

/// Lightweight splash shown while store loads. Otto has his coffee while the
/// data comes in (Welcome Back, right after, is where he waves).
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoVisible = false
    @State private var contentVisible = false

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            VStack(spacing: AppSpacing.md) {
                OwlView(pose: .coffee, size: .hero)

                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 150, maxHeight: 76)
                    .accessibilityLabel("Hour Tracker")
            }
            .scaleEffect(logoVisible ? 1 : (reduceMotion ? 1 : 0.94))
            .opacity(logoVisible ? 1 : 0)

            VStack(spacing: AppSpacing.sm) {
                LoadingDots()
                Text("Loading your data…")
                    .appText(.headline)
                    .foregroundStyle(AppColors.subtext)
            }
            .opacity(contentVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.bg.ignoresSafeArea())
        .onAppear {
            if reduceMotion {
                logoVisible = true
                contentVisible = true
            } else {
                withAnimation(AppMotion.Spring.smooth) {
                    logoVisible = true
                }
                withAnimation(AppMotion.Spring.smooth.delay(0.12)) {
                    contentVisible = true
                }
            }
        }
    }
}

/// Error state with Retry and Reset cache buttons.
struct StartupErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onResetCache: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            OwlView(pose: .oops, size: .emptyState)

            VStack(spacing: AppSpacing.sm) {
                Text("Something went wrong")
                    .appText(.title)
                    .foregroundStyle(AppColors.text)
                Text(message)
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AppSpacing.sm) {
                Button("Retry", action: onRetry)
                    .buttonStyle(PrimaryButtonStyle())
                Button("Reset cache", action: onResetCache)
                    .font(AppTypography.button)
                    .foregroundStyle(AppColors.negative)
                    .padding(.vertical, AppSpacing.xs)
            }

            Text("If this keeps happening, try updating the app or contact support.")
                .appText(.caption)
                .foregroundStyle(AppColors.faint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.bg.ignoresSafeArea())
        .gentleFadeIn()
    }
}
