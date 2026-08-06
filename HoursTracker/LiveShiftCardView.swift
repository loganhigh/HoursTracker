import SwiftUI

// MARK: - Live Shift Card (Hour Tracker Pro — clock in/out/break)
//
// Sits above `TodayHeroCard` on Home. Three states:
//   - idle: a "Clock In" button (Pro-gated on tap — non-Pro sees the paywall)
//   - active: live elapsed timer + Take Break/Clock Out (or Resume/Clock Out
//     while on break)
//   - stale (>16h): a quiet inline warning row layered above the active card
//
// No new glow here — the hero card below owns this screen's one glow.

struct LiveShiftCardView: View {
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var liveShift: LiveShiftManager
    @EnvironmentObject private var premium: PremiumManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingPaywall = false
    @State private var showingDiscardConfirm = false
    @State private var clockOutMessage: String?

    private static let startedTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        Group {
            if let shift = liveShift.activeShift {
                activeCard(shift)
                    .transition(.opacity)
            } else {
                idleRow
                    .transition(.opacity)
            }
        }
        .animation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion), value: liveShift.activeShift != nil)
        .sheet(isPresented: $showingPaywall) {
            // NOTE: PremiumUpgradeView.swift does not currently compile — it
            // calls `PremiumManager.purchase()` with the old (no-argument)
            // RevenueCat-era signature while PremiumManager.swift has already
            // moved to `purchase(_ product: Product)` (native StoreKit,
            // in-flight elsewhere). Falling back to a minimal placeholder so
            // this feature isn't blocked on that unrelated migration; swap
            // back to `PremiumUpgradeView()` once it compiles again.
            LiveShiftPaywallPlaceholder()
        }
        .alert("Discard this shift?", isPresented: $showingDiscardConfirm) {
            Button("Discard", role: .destructive) {
                liveShift.discard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clocked-in time won't be saved.")
        }
    }

    // MARK: Idle

    private var idleRow: some View {
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
    }

    // MARK: Active

    private func activeCard(_ shift: LiveShift) -> some View {
        VStack(spacing: AppSpacing.md) {
            if shift.isStale {
                staleRow
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                VStack(spacing: AppSpacing.xs) {
                    Text(Self.formatElapsed(shift.elapsedWorked(at: now)))
                        .font(AppTypography.heroNumber)
                        .monospacedDigit()
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    if shift.isOnBreak {
                        Text("On break · \(shift.totalBreakMinutes(at: now))m")
                            .appText(.caption)
                            .foregroundStyle(AppColors.warning)
                    } else {
                        Text("Started \(Self.startedTimeFormatter.string(from: shift.startDate))")
                            .appText(.caption)
                            .foregroundStyle(AppColors.subtext)
                    }
                }
            }

            if let clockOutMessage {
                Text(clockOutMessage)
                    .appText(.caption)
                    .foregroundStyle(AppColors.negative)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                if shift.isOnBreak {
                    Button("Resume") {
                        Haptics.lightTap()
                        liveShift.endBreak()
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Clock Out") { performClockOut() }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Take Break") {
                        Haptics.lightTap()
                        liveShift.startBreak()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Clock Out") { performClockOut() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(AppColors.card2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .stroke(AppColors.stroke, lineWidth: 1)
        )
    }

    private var staleRow: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.warning)

            Text("Still clocked in since yesterday?")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            Button("Clock out now") {
                performClockOut()
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AppColors.accent)

            Button("Discard") {
                Haptics.lightTap()
                showingDiscardConfirm = true
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AppColors.negative)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(AppColors.warning.opacity(0.10))
        )
    }

    // MARK: Actions

    private func performClockOut() {
        guard let entry = liveShift.clockOut(at: Date(), into: store) else {
            Haptics.error()
            clockOutMessage = "Shift too short to save yet — keep going, or discard it."
            return
        }
        _ = entry
        Haptics.success()
        clockOutMessage = nil
    }

    // MARK: Formatting

    private static func formatElapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }
}

// MARK: - Paywall placeholder
//
// Temporary stand-in while `PremiumUpgradeView` is mid-migration elsewhere
// and doesn't compile (see the comment above). Swap the `.sheet` content
// back to `PremiumUpgradeView()` once that lands.

private struct LiveShiftPaywallPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.md) {
                Spacer()
                Image(systemName: "crown.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                Text("Hour Tracker Pro")
                    .appText(.title)
                    .foregroundStyle(AppColors.text)
                Text("Live clock in/out tracking is a Pro feature.")
                    .appText(.body)
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Hour Tracker Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
