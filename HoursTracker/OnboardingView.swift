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

// MARK: - OnboardingView (Phase 11)
//
// Four paged screens: Track → Progress → Friends → Sign in. Sign-in is the
// CTA on the last screen; after Firebase confirms the session we advance
// automatically — into a one-time company-profile step when those fields have
// never been filled, otherwise straight into the app.
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
    /// The company step only exists in the pager after auth confirms, so it
    /// can never be swiped into manually.
    @State private var showsCompanyStep = false

    // Company profile (same keys as the old page-6 form / Settings screen).
    @AppStorage("company_name") private var companyName: String = ""
    @AppStorage("company_occupation") private var occupation: String = ""
    @AppStorage("company_start_date_ts") private var companyStartDateTS: Double = 0
    @State private var companyStartDate: Date = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()

    private let signInPageIndex = 3
    private let companyPageIndex = 4

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()

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
    }

    // MARK: - Pager

    private var pager: some View {
        TabView(selection: $page) {
            OnboardingHeroPage(
                headline: "Track your hours",
                subline: "Log a shift in seconds. Your history organizes itself."
            ) {
                OnboardingShiftStackHero()
            }
            .tag(0)

            OnboardingHeroPage(
                headline: "Every shift builds progress",
                subline: "Earn XP, keep streaks alive, and climb toward Prestige."
            ) {
                OnboardingProgressHero()
            }
            .tag(1)

            OnboardingHeroPage(
                headline: "Compete with friends",
                subline: "Weekly standings and milestones keep you accountable."
            ) {
                OnboardingLeaderboardHero()
            }
            .tag(2)

            signInPage
                .tag(signInPageIndex)

            if showsCompanyStep {
                companyPage
                    .tag(companyPageIndex)
            }
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
            if page < companyPageIndex {
                OnboardingPageIndicator(count: 4, current: min(page, signInPageIndex))
            }

            if page < signInPageIndex {
                Button("Continue") {
                    Haptics.lightTap()
                    withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
                        page += 1
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: - Screen 4 — sign in

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

    // MARK: - Post-auth company step

    private var companyPage: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(AppColors.accent)
                    .padding(.top, AppSpacing.xs)

                VStack(spacing: AppSpacing.sm) {
                    Text("Your company")
                        .appText(.title)
                        .foregroundStyle(AppColors.text)
                        .multilineTextAlignment(.center)

                    Text("Add your company details to track tenure and unlock company stats.")
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: AppSpacing.md) {
                    companyField(title: "Company Name", text: $companyName, placeholder: "e.g. ABC Construction")
                    companyField(title: "Occupation", text: $occupation, placeholder: "e.g. Asphalt / Concrete / Foreman")

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Start Date")
                            .appText(.metricLabel)
                            .foregroundStyle(AppColors.subtext)
                        DatePicker("", selection: $companyStartDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(AppColors.accent)
                            .onChange(of: companyStartDate) { _, newDate in
                                companyStartDateTS = newDate.timeIntervalSince1970
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("You can update these later in Settings → Company Profile.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.faint)
                        .multilineTextAlignment(.center)
                }
                .padding(AppSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(AppColors.card2)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .stroke(AppColors.stroke, lineWidth: 1)
                        )
                )

                Button("Continue") {
                    Haptics.lightTap()
                    finishOnboarding()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.bottom, AppSpacing.sm)
            }
            .padding(.horizontal, AppSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func companyField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .appText(.metricLabel)
                .foregroundStyle(AppColors.subtext)
            TextField(placeholder, text: text)
                .appText(.body)
                .foregroundStyle(AppColors.text)
                .padding(AppSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .fill(AppColors.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                .stroke(AppColors.stroke, lineWidth: 1)
                        )
                )
                .tint(AppColors.accent)
        }
    }

    // MARK: - Auth auto-advance

    /// True until the user has ever filled any company-profile field (local
    /// check — the cheap signal that this is a brand-new profile).
    private var needsCompanySetup: Bool {
        companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && occupation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && companyStartDateTS <= 0
    }

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

        if needsCompanySetup {
            showsCompanyStep = true
            // Let the pager register the new page before selecting it.
            DispatchQueue.main.async {
                withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
                    page = companyPageIndex
                }
            }
        } else {
            finishOnboarding()
        }
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

// MARK: - Shared hero page layout (screens 1–3)

private struct OnboardingHeroPage<Hero: View>: View {
    let headline: String
    let subline: String
    @ViewBuilder let hero: () -> Hero

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            hero()
                .padding(.horizontal, AppSpacing.xl)

            Spacer(minLength: 0)

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
            .padding(.bottom, AppSpacing.lg)
        }
    }
}
