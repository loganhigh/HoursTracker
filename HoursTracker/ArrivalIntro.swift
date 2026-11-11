import SwiftUI

// MARK: - Introducing "Arrive at work"
//
// The feature lives in Settings, where nobody finds it. New users meet it in
// onboarding; existing users meet it at the top of Add Shift, the screen they
// open every time they'd have benefited from it.

/// Add Shift, first step: shown until the user adds a work location or
/// dismisses it. No owl — Add Shift is a utility sheet.
struct ArrivalAddShiftCard: View {
    @ObservedObject var store: HoursStore
    @ObservedObject private var monitor = ArrivalMonitor.shared
    @AppStorage("arrival_addshift_card_dismissed_v1") private var dismissed = false
    @State private var settingUp = false

    var body: some View {
        if !dismissed && monitor.sites.isEmpty {
            AddShiftPanel(tint: AppColors.accent) {
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(AppColors.accent.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start shifts when you get to work")
                            .appText(.headline)
                            .foregroundStyle(AppColors.text)
                        Text("Add your work location and get a tap to start your live shift when you arrive, and to clock out when you leave.")
                            .appText(.subheadline)
                            .foregroundStyle(AppColors.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            Haptics.lightTap()
                            settingUp = true
                        } label: {
                            Text("Add work location")
                                .appText(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColors.accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColors.subtext)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }
            .sheet(isPresented: $settingUp) {
                ArrivalSiteEditor(store: store, site: nil)
            }
        }
    }
}

/// Onboarding page between "Where do you work?" and sign-in.
struct OnboardingArrivalPage: View {
    @ObservedObject var store: HoursStore
    let minHeight: CGFloat
    let onContinue: () -> Void
    @ObservedObject private var monitor = ArrivalMonitor.shared
    @State private var settingUp = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: AppSpacing.lg) {
                    OnboardingHeader(
                        pose: .pin,
                        title: "Start your shift when you get to work",
                        subline: "Add where you work and Hour Tracker taps you to start your live shift when you arrive, and to clock out when you leave."
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        bullet("bell.badge.fill", "One tap from the notification starts the clock.")
                        bullet("figure.walk.departure", "Leaving? Clock out at the time you actually left.")
                        bullet("lock.fill", "Location is only used for the places you add. Your route isn't tracked.")
                    }
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onboardingFormCard()

                    if let site = monitor.sites.first {
                        Label("\(site.name) added", systemImage: "checkmark.circle.fill")
                            .appText(.subheadline)
                            .foregroundStyle(AppColors.positive)
                        Button("Continue", action: onContinue)
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Add my work location") {
                            Haptics.lightTap()
                            settingUp = true
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button("Maybe later", action: onContinue)
                            .appText(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.subtext)
                    }
                }
                .padding(.horizontal, AppSpacing.xl)

                Spacer(minLength: 0)
            }
            .frame(minHeight: minHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $settingUp) {
            ArrivalSiteEditor(store: store, site: nil) {
                // Give the sheet a moment to close, then move on.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onContinue() }
            }
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 22)
            Text(text)
                .appText(.subheadline)
                .foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
