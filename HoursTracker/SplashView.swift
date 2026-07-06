import SwiftUI

/// Lightweight splash shown while store loads.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoVisible = false
    @State private var contentVisible = false

    var body: some View {
        VStack(spacing: 28) {
            Image("SplashLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 120)
                .scaleEffect(logoVisible ? 1 : (reduceMotion ? 1 : 0.94))
                .opacity(logoVisible ? 1 : 0)

            ProgressView()
                .scaleEffect(1.2)
                .tint(AppTheme.Colors.accent)
                .opacity(contentVisible ? 1 : 0)

            Text("Loading your data…")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.subtext)
                .opacity(contentVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
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
        VStack(spacing: 20) {
            Image("SplashLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 180, maxHeight: 90)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.Colors.warning)
            Text("Something went wrong")
                .font(AppTheme.Typography.title3)
                .foregroundStyle(AppTheme.Colors.text)
            Text(message)
                .font(AppTheme.Typography.callout)
                .foregroundStyle(AppTheme.Colors.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            VStack(spacing: 12) {
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.Colors.accent)
                Button("Reset cache", action: onResetCache)
                    .foregroundStyle(AppTheme.Colors.danger)
            }
            Text("If this keeps happening, try updating the app or contact support.")
                .font(.footnote)
                .foregroundStyle(AppTheme.Colors.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .gentleFadeIn()
    }
}
