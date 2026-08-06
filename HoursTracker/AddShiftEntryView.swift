import SwiftUI

// MARK: - Add Shift entry point (Hour Tracker Pro — router)
//
// The single way a shift gets into the log, live-tracked or manual. Home's
// "Add Shift" button (and every other add-shift affordance) presents this
// instead of jumping straight to the wizard:
//
//   - An already-running live shift takes over immediately — this sheet
//     shows the timer/break/clock-out interface (`LiveShiftTrackingView`),
//     skipping the chooser entirely.
//   - Otherwise a quiet chooser offers "Clock In" (Pro-gated — non-Pro taps
//     see the paywall) or "Enter shift manually" (the existing two-screen
//     wizard, unchanged).
//   - Choosing Clock In while Pro starts the live shift right here; this
//     same sheet transitions into the tracking view without closing and
//     reopening, because it observes `LiveShiftManager.activeShift`.
//
// No new glow here — the hero card on Home owns this screen's one glow.

struct AddShiftEntryView: View {
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var liveShift: LiveShiftManager
    @EnvironmentObject private var premium: PremiumManager
    @Environment(\.dismiss) private var dismiss

    @State private var showManualWizard = false
    @State private var showingPaywall = false

    var body: some View {
        Group {
            if liveShift.activeShift != nil {
                LiveShiftTrackingView(store: store)
            } else if showManualWizard {
                AddShiftWizardView(store: store)
            } else {
                chooser
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PremiumUpgradeView()
        }
    }

    // MARK: Chooser

    private var chooser: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)

            Spacer()

            VStack(spacing: AppSpacing.md) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppColors.accent)

                VStack(spacing: 4) {
                    Text("Add a shift")
                        .appText(.title)
                        .foregroundStyle(AppColors.text)
                    Text("Track it live, or enter the times yourself.")
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, AppSpacing.lg)

            Spacer()

            VStack(spacing: AppSpacing.sm) {
                Button {
                    Haptics.lightTap()
                    if premium.isPremium {
                        liveShift.clockIn()
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(.callout, weight: .bold))
                        Text("Clock In")
                            .font(.system(.callout, design: .rounded, weight: .bold))
                        if !premium.isPremium {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .opacity(0.85)
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    Haptics.lightTap()
                    showManualWizard = true
                } label: {
                    Text("Enter shift manually")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(AppColors.subtext)
                }
                .buttonStyle(.plain)
                .padding(.top, AppSpacing.xxs)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.bg.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                Haptics.lightTap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.subtext)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(AppColors.card)
                            .overlay(Circle().stroke(AppColors.stroke, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Text("Add Shift")
                .appText(.title)
                .foregroundStyle(AppColors.text)

            Spacer()
        }
    }
}
