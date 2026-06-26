import SwiftUI

// MARK: - Tutorial persistence

enum AppTutorialStorage {
    static let completeKey = "app_tutorial_complete"

    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: completeKey)
    }

    static func markComplete() {
        UserDefaults.standard.set(true, forKey: completeKey)
    }
}

// MARK: - Page model

private struct AppTutorialPage: Identifiable {
    let id: Int
    let icon: String
    let iconColors: [Color]
    let title: String
    let message: String
    var isSignInStep: Bool = false
    var isCompanyStep: Bool = false
}

// MARK: - AppTutorialView

struct AppTutorialView: View {
    @Binding var isPresented: Bool
    var dismissesWhenComplete: Bool = true
    var onComplete: (() -> Void)? = nil

    @EnvironmentObject private var authService: AuthService

    @State private var stepIndex = 0
    @State private var glowPulse: CGFloat = 0.4
    @State private var iconScale: CGFloat = 0.82
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 18

    @AppStorage("company_name") private var companyName: String = ""
    @AppStorage("company_occupation") private var occupation: String = ""
    @AppStorage("company_start_date_ts") private var companyStartDateTS: Double = 0
    @State private var companyStartDate: Date = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State private var hasSetStartDate = false

    private let pages: [AppTutorialPage] = [
        AppTutorialPage(
            id: 0,
            icon: "clock.badge.checkmark.fill",
            iconColors: [AppTheme.Colors.accent, AppTheme.Colors.accentHighlight],
            title: "Welcome to Hour Tracker",
            message: "Track your shifts, hours, overtime, and earnings in one place."
        ),
        AppTutorialPage(
            id: 1,
            icon: "plus.circle.fill",
            iconColors: [Color(red: 0.35, green: 0.78, blue: 0.98), AppTheme.Colors.accent],
            title: "Log Your Shifts",
            message: "Add your start time, end time, breaks, job/location, and notes."
        ),
        AppTutorialPage(
            id: 2,
            icon: "dollarsign.circle.fill",
            iconColors: [Color(red: 0.98, green: 0.78, blue: 0.28), Color(red: 0.92, green: 0.55, blue: 0.18)],
            title: "Understand Your Pay",
            message: "Set your hourly wage, overtime rules, and pay cycle so estimates are more accurate."
        ),
        AppTutorialPage(
            id: 3,
            icon: "calendar.circle.fill",
            iconColors: [AppTheme.Colors.accent2, AppTheme.Colors.accent],
            title: "View Pay Periods",
            message: "See how many hours you worked in your current pay cycle, weekly view, and previous months."
        ),
        AppTutorialPage(
            id: 4,
            icon: "person.2.fill",
            iconColors: [Color(red: 0.72, green: 0.45, blue: 0.98), AppTheme.Colors.accentHighlight],
            title: "Compete With Friends",
            message: "Add friends, compare hours, streaks, badges, and leaderboard rankings."
        ),
        AppTutorialPage(
            id: 5,
            icon: "square.and.arrow.up.fill",
            iconColors: [Color(red: 0.42, green: 0.82, blue: 0.62), Color(red: 0.22, green: 0.62, blue: 0.48)],
            title: "Export & Share",
            message: "Export summaries as PDF/CSV and share your work history when needed."
        ),
        AppTutorialPage(
            id: 6,
            icon: "building.2.fill",
            iconColors: [Color(red: 0.98, green: 0.78, blue: 0.28), Color(red: 0.92, green: 0.55, blue: 0.18)],
            title: "Your Company",
            message: "Add your company details to track tenure, compare with coworkers, and unlock company stats.",
            isCompanyStep: true
        ),
        AppTutorialPage(
            id: 7,
            icon: "checkmark.seal.fill",
            iconColors: [AppTheme.Colors.accent, AppTheme.Colors.accentHighlight],
            title: "You're Ready",
            message: "Start by adding your first shift or setting up your pay rules."
        ),
        AppTutorialPage(
            id: 8,
            icon: "person.crop.circle.badge.checkmark",
            iconColors: [AppTheme.Colors.accent, AppTheme.Colors.accentHighlight],
            title: "Create your account",
            message: "Sign in with Apple, Google, or email to back up shifts, sync devices, and add friends.",
            isSignInStep: true
        )
    ]

    private var currentPage: AppTutorialPage { pages[stepIndex] }
    private var isLastStep: Bool { stepIndex >= pages.count - 1 }

    var body: some View {
        ZStack {
            AppTheme.Colors.bg.ignoresSafeArea()

            ambientGlow

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                stepDots
                    .padding(.top, 28)
                    .padding(.bottom, 12)

                if currentPage.isSignInStep {
                    signInPageContent
                        .padding(.horizontal, 28)
                } else if currentPage.isCompanyStep {
                    companyPageContent
                        .padding(.horizontal, 28)
                } else {
                    Spacer(minLength: 0)

                    pageContent
                        .padding(.horizontal, 28)

                    Spacer(minLength: 0)
                }

                bottomButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
            }
        }
        .onAppear {
            glowPulse = 1.0
            animateContentIn()
        }
    }

    // MARK: - Subviews

    private var ambientGlow: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.accent.opacity(0.12))
                .frame(width: 340, height: 340)
                .blur(radius: 80)
                .offset(x: -90, y: -220)
                .scaleEffect(glowPulse)
            Circle()
                .fill(AppTheme.Colors.accentHighlight.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 110, y: 180)
                .scaleEffect(glowPulse)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true), value: glowPulse)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button("Skip") {
                Haptics.lightTap()
                finishTutorial()
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.subtext)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(pages) { page in
                Capsule()
                    .fill(
                        page.id == stepIndex
                            ? LinearGradient(
                                colors: [AppTheme.Colors.accent, AppTheme.Colors.accentHighlight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(
                                colors: [AppTheme.Colors.stroke, AppTheme.Colors.stroke],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .frame(width: page.id == stepIndex ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: stepIndex)
            }
        }
    }

    private var signInPageContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 14) {
                    Text(currentPage.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(currentPage.message)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(textOpacity)
                .offset(y: textOffset)

                AuthSignInOptionsView()
                    .opacity(textOpacity)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .id(stepIndex)
    }

    private var pageContent: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: currentPage.iconColors.map { $0.opacity(0.22) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 2)

                Circle()
                    .fill(AppTheme.Colors.card2)
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: currentPage.iconColors.map { $0.opacity(0.55) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )

                Image(systemName: currentPage.icon)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: currentPage.iconColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)

            VStack(spacing: 14) {
                Text(currentPage.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(currentPage.message)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(textOpacity)
            .offset(y: textOffset)
        }
        .frame(maxWidth: .infinity)
        .id(stepIndex)
    }

    private var companyPageContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 14) {
                    Text(currentPage.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.text)
                        .multilineTextAlignment(.center)

                    Text(currentPage.message)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .opacity(textOpacity)
                .offset(y: textOffset)

                VStack(spacing: 16) {
                    companyField(title: "Company Name", text: $companyName, placeholder: "e.g. Amrize Construction")
                    companyField(title: "Occupation", text: $occupation, placeholder: "e.g. Asphalt / Concrete / Foreman")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start Date")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.subtext)
                        DatePicker("", selection: $companyStartDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(AppTheme.Colors.accent)
                            .onChange(of: companyStartDate) { _, newDate in
                                companyStartDateTS = newDate.timeIntervalSince1970
                                hasSetStartDate = true
                            }
                    }

                    Text("You can update these later in Settings → Company Profile.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.Colors.card2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                        )
                )
                .opacity(textOpacity)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .id(stepIndex)
    }

    private func companyField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.subtext)
            TextField(placeholder, text: text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.Colors.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                        )
                )
        }
    }

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            PrimaryButton(primaryButtonTitle, systemImage: isLastStep ? "arrow.right" : "chevron.right") {
                advance()
            }

            if stepIndex > 0 {
                Button {
                    Haptics.lightTap()
                    goBack()
                } label: {
                    Text("Back")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Navigation

    private var primaryButtonTitle: String {
        if isLastStep {
            return authService.isSignedIn ? "Get Started" : "Skip for now"
        }
        return "Continue"
    }

    private func advance() {
        Haptics.lightTap()
        if isLastStep {
            Haptics.success()
            finishTutorial()
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                iconOpacity = 0
                textOpacity = 0
                textOffset = 12
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                stepIndex += 1
                animateContentIn()
            }
        }
    }

    private func goBack() {
        withAnimation(.easeOut(duration: 0.15)) {
            iconOpacity = 0
            textOpacity = 0
            textOffset = -12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            stepIndex -= 1
            animateContentIn()
        }
    }

    private func animateContentIn() {
        iconScale = 0.82
        iconOpacity = 0
        textOpacity = 0
        textOffset = 18

        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
            textOpacity = 1.0
            textOffset = 0
        }
    }

    private func finishTutorial() {
        AppTutorialStorage.markComplete()
        onComplete?()
        guard dismissesWhenComplete else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            isPresented = false
        }
    }
}
