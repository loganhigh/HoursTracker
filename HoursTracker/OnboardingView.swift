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
// Five paged screens: Welcome → Leaderboard → Display name → Pay cycle →
// Sign in. Setup comes before the account, so the last thing a new user does
// is authenticate; the moment Firebase confirms the session, onboarding ends
// and they land on Home. (Company details still live in Settings.)
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
    @EnvironmentObject private var store: HoursStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    /// Single-fire guard for the post-auth advance (set on the main actor).
    @State private var hasAdvanced = false

    @State private var nameDraft = ""
    @State private var nameValidationMessage: String?
    @FocusState private var nameFieldFocused: Bool

    @State private var payPeriodDraft: PayPeriodType = .biWeekly
    @State private var paydayDraft = OnboardingView.defaultPayday()
    @State private var usesCutoffDraft = false
    @State private var cutoffDraft = OnboardingView.defaultPayday()

    /// The scroll view's own height, used as the content's minimum so short
    /// content centers and tall content still scrolls.
    @State private var signInPageMinHeight: CGFloat = 0

    // Setup first, sign-in last: the account is the final step, so the pager
    // ends on it and auth completion ends onboarding.
    private let pageCount = 5
    private let namePageIndex = 2
    private let payPageIndex = 3
    private let signInPageIndex = 4

    /// Seeds the payday picker with the next Friday — the most common payday,
    /// and a date the user is more likely to adjust than to type from scratch.
    private static func defaultPayday() -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.nextDate(
            after: today,
            matching: DateComponents(weekday: 6), // 1 = Sunday, so 6 = Friday
            matchingPolicy: .nextTime
        ) ?? today
    }

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
        .onChange(of: page) { _, newPage in
            Haptics.lightTap()
            if newPage == namePageIndex {
                prefillNameDraft()
            }
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
            guard let demo = ProcessInfo.processInfo.environment["ONBOARDING_DEMO"] else { return }
            let lastPage: Int
            switch demo {
            case "name": lastPage = namePageIndex
            case "pay":  lastPage = payPageIndex
            default:     lastPage = signInPageIndex
            }
            while page < lastPage {
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

            namePage
                .tag(namePageIndex)

            payPage
                .tag(payPageIndex)

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
            if page < namePageIndex {
                Button("Skip") {
                    Haptics.lightTap()
                    withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
                        page = namePageIndex
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

            if page < namePageIndex {
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
        // Centered like the name and pay pages. Still a ScrollView, because
        // this page's content is tall enough to need scrolling on small
        // devices and with the keyboard up — the minHeight frame is what
        // centers it when there is room to spare.
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                Spacer(minLength: 0)

                // No logo here. The welcome page already opens on it, and at
                // any size that read as a logo it pushed the form into the
                // page indicator — the form is the whole point of this page.
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

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.xl)
            .frame(maxWidth: .infinity, minHeight: signInPageMinHeight)
        }
        .scrollDismissesKeyboard(.interactively)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            signInPageMinHeight = height
        }
    }

    // MARK: - Screen 4 — display name

    private var namePage: some View {
        // Vertically centered like the hero pages — a short form pinned to the
        // top left the lower two-thirds of the screen empty.
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(AppColors.accent)

                VStack(spacing: AppSpacing.sm) {
                    Text("What should we call you?")
                        .appText(.title)
                        .foregroundStyle(AppColors.text)
                        .multilineTextAlignment(.center)

                    Text("Your name appears on your profile, to friends, and on the leaderboards. You can change it any time.")
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("Your name", text: $nameDraft)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($nameFieldFocused)
                    .onSubmit { saveNameAndFinish() }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                            .fill(AppColors.card2.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                    .stroke(AppColors.stroke.opacity(0.5), lineWidth: 1)
                            )
                    )

                if let nameValidationMessage {
                    Text(nameValidationMessage)
                        .appText(.caption)
                        .foregroundStyle(AppColors.negative)
                        .multilineTextAlignment(.center)
                }

                Button("Continue") {
                    saveNameAndFinish()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(trimmedNameDraft.isEmpty)
                .opacity(trimmedNameDraft.isEmpty ? 0.6 : 1)
            }
            .padding(.horizontal, AppSpacing.xl)

            Spacer(minLength: 0)
        }
        .onChange(of: nameDraft) { _, _ in nameValidationMessage = nil }
    }

    private var trimmedNameDraft: String {
        String(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }

    /// Seeds the field with whatever sign-in captured from the provider, so
    /// most users just confirm their own name. The "Worker" placeholder the
    /// auth path falls back to is not worth confirming — it seeds empty.
    private func prefillNameDraft() {
        guard nameDraft.isEmpty else { return }
        let stored = UserDefaults.standard.string(forKey: "profile_display_name") ?? ""
        nameDraft = stored == "Worker" ? "" : stored
    }

    private func saveNameAndFinish() {
        let name = trimmedNameDraft
        guard !name.isEmpty else { return }
        guard BroadContentFilter.shared.validate(name).isAllowed else {
            nameValidationMessage = BroadContentFilter.blockedNameMessage
            Haptics.error()
            return
        }
        // Stored locally only — there is no account yet at this point in the
        // flow. `finishOnboarding` reasserts it once auth completes.
        UserDefaults.standard.set(name, forKey: "profile_display_name")
        Haptics.success()
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            page = payPageIndex
        }
    }

    // MARK: - Screen 5 — pay cycle

    private var payPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(AppColors.accent)

                VStack(spacing: AppSpacing.sm) {
                    Text("When do you get paid?")
                        .appText(.title)
                        .foregroundStyle(AppColors.text)
                        .multilineTextAlignment(.center)

                    Text("This sets your pay period so your hours and cheque totals line up. You can change it any time in Settings.")
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Pay period", selection: $payPeriodDraft) {
                    ForEach(PayPeriodType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 0) {
                    DatePicker(
                        "Next payday",
                        selection: $paydayDraft,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 12)

                    Divider().overlay(AppColors.stroke)

                    Toggle(isOn: $usesCutoffDraft.animation(
                        AppMotion.animation(AppMotion.Spring.snappy, reduceMotion: reduceMotion)
                    )) {
                        Text("Hours cutoff")
                            .appText(.body)
                            .foregroundStyle(AppColors.text)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 6)

                    if usesCutoffDraft {
                        Divider().overlay(AppColors.stroke)

                        DatePicker(
                            "Cutoff date",
                            selection: $cutoffDraft,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, 12)
                    }
                }
                .tint(AppColors.accent)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .fill(AppColors.card2.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                .stroke(AppColors.stroke.opacity(0.5), lineWidth: 1)
                        )
                )

                Text(usesCutoffDraft
                     ? "Hours are counted up to the cutoff, then paid on payday."
                     : "Hours are counted right up to payday.")
                    .appText(.caption)
                    .foregroundStyle(AppColors.faint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Continue") {
                    savePayCycleAndFinish()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, AppSpacing.xl)

            Spacer(minLength: 0)
        }
    }

    private func savePayCycleAndFinish() {
        store.paySettings.payPeriodType = payPeriodDraft
        store.paySettings.nextPayday = Calendar.current.startOfDay(for: paydayDraft)
        store.paySettings.payPeriodUsesCutoff = usesCutoffDraft
        // Cleared rather than left stale when off — Settings does the same, so
        // toggling back on there starts from "Select date" instead of a date
        // the user never chose.
        store.paySettings.nextCutoff = usesCutoffDraft
            ? Calendar.current.startOfDay(for: cutoffDraft)
            : nil
        store.persist()
        Haptics.success()
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            page = signInPageIndex
        }
    }

    // MARK: - Auth auto-advance

    /// Level-triggered advance check. Runs on every relevant event; fires at
    /// most once (`hasAdvanced`), never while auth is in-flight, and never on
    /// failure/cancel (isSignedIn stays false — AuthSignInOptionsView already
    /// surfaces `lastError` quietly). Advances to the name page rather than
    /// completing — the name page owns completion.
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
        // Sign-in runs last, and the auth paths set `profile_display_name`
        // from the provider account — which would silently discard the name
        // the user chose two screens earlier. Reassert it here, and push it so
        // the first thing the server publishes is the chosen name.
        let chosen = String(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        if !chosen.isEmpty, BroadContentFilter.shared.validate(chosen).isAllowed {
            UserDefaults.standard.set(chosen, forKey: "profile_display_name")
            if let user = authService.user {
                Task {
                    try? await authService.upsertUserDocument(
                        uid: user.uid,
                        displayName: chosen,
                        email: user.email
                    )
                }
            }
        }
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
