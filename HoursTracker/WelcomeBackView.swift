import SwiftUI

// MARK: - Welcome Back screen
//
// Shown once per cold launch, right after the startup splash and before Home
// appears: a full-screen "Welcome back, {name}!" that auto-dismisses into the
// app. Not shown on background/foreground resumes or sign-out/sign-in resets
// within the same process — only on an actual fresh start. Quiet, flat, one
// accent — no glow, no confetti, matches the rest of the app.

struct WelcomeBackView: View {
    @AppStorage("profile_display_name") private var storedDisplayName: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called once the greeting has finished its beat on screen.
    var onFinished: () -> Void

    @State private var isVisible = false

    private var name: String {
        let trimmed = storedDisplayName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "" : trimmed
    }

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()

            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "hourglass")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(AppColors.accent)
                    .padding(.bottom, AppSpacing.xs)

                Text(greeting)
                    .appText(.title)
                    .foregroundStyle(AppColors.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, AppSpacing.xl)
            }
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.97)
        }
        .onAppear { play() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(greeting)
    }

    private var greeting: String {
        name.isEmpty ? "Welcome back!" : "Welcome back, \(name)!"
    }

    private func play() {
        if reduceMotion {
            isVisible = true
        } else {
            withAnimation(AppMotion.Spring.smooth) { isVisible = true }
        }

        // One quiet beat on screen, then hand off to the app. Long enough to
        // read the name, short enough to never feel like a blocking step.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            if reduceMotion {
                onFinished()
            } else {
                withAnimation(AppMotion.Spring.smooth) { isVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onFinished() }
            }
        }
    }
}
