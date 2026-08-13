import SwiftUI

// MARK: - Onboarding persistence
//
// Same key + semantics as the retired AppTutorialView so AppRootView's
// `@AppStorage(AppTutorialStorage.completeKey)` gate and RESET_ONBOARDING.md
// keep working unchanged.

enum AppTutorialStorage {
    static let completeKey = "app_tutorial_complete"

    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: completeKey)
    }

    static func markComplete() {
        UserDefaults.standard.set(true, forKey: completeKey)
    }
}

// MARK: - OnboardingView
//
// Three paged screens: Welcome → Features → Sign in. The moment Firebase
// confirms the session the user lands on Home — there is no post-auth setup
// step (company details live in Settings → Company Profile).
//
// Auto-advance is LEVEL-triggered, not edge-triggered. The old
// AppTutorialView only listened for the isSignedIn false→true edge and
// dropped it unless the sign-in page was frontmost — a Keychain-restored
// Firebase session (which survives reinstalls and the RESET_ONBOARDING flow)
// flips isSignedIn on page 0, so the only edge was consumed early and the
// user had to press Next manually. Here `advanceIfReady()` re-evaluates the
// full condition on every relevant event: auth confirmed, auth no longer
// in-flight, or arrival on the sign-in page.

struct OnboardingView: View {
    @Binding var isPresented: Bool
    var dismissesWhenComplete: Bool = true
    var onComplete: (() -> Void)? = nil

    @EnvironmentObject private var authService: AuthService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    /// Single-fire guard for the post-auth advance (set on the main actor).
    @State private var hasAdvanced = false

    private let pageCount = 3
    private let signInPageIndex = 2

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()
            topWash

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.sm)

                pager

                bottomArea
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.xxl)
            }
        }
        .onChange(of: page) { _, _ in
            Haptics.lightTap()
            advanceIfReady()
        }
        .onChange(of: authService.isSignedIn) { _, _ in advanceIfReady() }
        .onChange(of: authService.isSigningIn) { _, _ in advanceIfReady() }
        .onAppear { advanceIfReady() }
        .task {
            // Dev-only rehearsal, same pattern as LEVELUP_DEMO: auto-walks the
            // pager so onboarding can be reviewed in the Simulator without
            // touch input. Inert unless the launch environment carries the
            // variable, which production never does.
            guard ProcessInfo.processInfo.environment["ONBOARDING_DEMO"] != nil else { return }
            while page < signInPageIndex {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(AppMotion.Spring.smooth) { page += 1 }
            }
        }
    }

    /// Accent bloom behind the hero, fading out well before the copy starts.
    private var topWash: some View {
        LinearGradient(
            colors: [
                AppColors.accent.opacity(0.30),
                AppColors.accent.opacity(0.07),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 460)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Pager

    private var pager: some View {
        TabView(selection: $page) {
            OnboardingHeroPage(
                headline: "Welcome to Hour Tracker",
                subline: "Every shift you work, tracked and organized in one place."
            ) {
                OnboardingLogoHero()
            }
            .tag(0)

            OnboardingHeroPage(
                headline: "Climb the leaderboard",
                subline: "Every shift moves you up. See how you stack up against your friends."
            ) {
                OnboardingLeaderboardHero()
            }
            .tag(1)

            signInPage
                .tag(signInPageIndex)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion), value: page)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Spacer()
            if page < signInPageIndex {
                Button("Skip") {
                    Haptics.lightTap()
                    withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
                        page = signInPageIndex
                    }
                }
                .appText(.subheadline)
                .foregroundStyle(AppColors.subtext)
                .padding(.horizontal, AppSpacing.xxs)
                .padding(.vertical, AppSpacing.xs)
            }
        }
        .frame(height: 36)
    }

    private var bottomArea: some View {
        VStack(spacing: AppSpacing.md) {
            OnboardingPageIndicator(count: pageCount, current: page)

            if page < signInPageIndex {
                Button(page == 0 ? "Get Started" : "Continue") {
                    Haptics.lightTap()
                    withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
                        page += 1
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: - Screen 3 — sign in

    private var signInPage: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "hourglass")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(AppColors.accent)
                    .padding(.top, AppSpacing.xs)

                VStack(spacing: AppSpacing.sm) {
                    Text("Start tracking")
                        .appText(.title)
                        .foregroundStyle(AppColors.text)
                        .multilineTextAlignment(.center)

                    Text("Sign in to sync your hours and progress everywhere.")
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                AuthSignInOptionsView()

                if authService.isSigningIn {
                    HStack(spacing: AppSpacing.xs) {
                        ProgressView()
                            .scaleEffect(0.85)
                            .tint(AppColors.accent)
                        Text("Signing you in…")
                            .appText(.caption)
                            .foregroundStyle(AppColors.subtext)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text("Your hours stay private until you share them.")
                        .appText(.caption)
                }
                .foregroundStyle(AppColors.faint)
                .padding(.bottom, AppSpacing.sm)
            }
            .padding(.horizontal, AppSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Auth auto-advance

    /// Level-triggered completion check. Runs on every relevant event; fires
    /// at most once (`hasAdvanced`), never while auth is in-flight, and never
    /// on failure/cancel (isSignedIn stays false — AuthSignInOptionsView
    /// already surfaces `lastError` quietly).
    @MainActor
    private func advanceIfReady() {
        guard !hasAdvanced else { return }
        guard page >= signInPageIndex else { return }
        guard authService.isSignedIn, !authService.isSigningIn else { return }
        hasAdvanced = true
        Haptics.success()
        finishOnboarding()
    }

    // MARK: - Completion (same semantics as the old finishTutorial)

    private func finishOnboarding() {
        AppTutorialStorage.markComplete()
        onComplete?()
        guard dismissesWhenComplete else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            isPresented = false
        }
    }
}

// MARK: - Shared hero page layout (screens 1–2)
//
// Hero and copy sit together as one vertically-centered group — the copy
// reads as a caption on the illustration rather than as a separate block
// stranded above the button.

private struct OnboardingHeroPage<Hero: View>: View {
    let headline: String
    let subline: String
    @ViewBuilder let hero: () -> Hero

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer(minLength: 0)

            hero()
                .padding(.horizontal, AppSpacing.xl)

            VStack(spacing: AppSpacing.sm) {
                Text(headline)
                    .appText(.title)
                    .foregroundStyle(AppColors.text)
                    .multilineTextAlignment(.center)

                Text(subline)
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer(minLength: 0)
        }
    }
}
