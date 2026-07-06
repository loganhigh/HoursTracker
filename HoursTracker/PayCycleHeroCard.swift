import SwiftUI

/// Home-screen pay cycle summary card — two rings side-by-side showing
/// days worked and hours logged for the active pay period.
struct PayCycleHeroCard: View {
    @ObservedObject var store: HoursStore
    @ObservedObject private var statsListener = StatsListenerService.shared

    @Environment(\.semanticColors) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowPulse: Double = 0.30
    @State private var animatedDaysFraction: Double = 0
    @State private var animatedHoursFraction: Double = 0

    private var prestigeTier: PrestigeTheme.Tier {
        PrestigeTheme.tier(for: store.gamificationProfile.prestige)
    }

    // MARK: - Cycle data

    private var cycle: PayCycle { store.currentPayCycle() }
    private var entries: [WorkEntry] { PayCycleEngine.entries(store.entries, in: cycle) }
    private var workEntries: [WorkEntry] { entries.filter { !$0.isOffDay } }

    private var periodHours: Double {
        if FirebaseMigrationFlags.useServerStats, let stats = statsListener.payPeriodStats {
            return stats.hours
        }
        return entries.reduce(0) { $0 + $1.paidHours }
    }

    private var periodPay: Double {
        entries.reduce(0) { $0 + store.payBreakdown(for: $1).pay }
    }

    private var daysWorked: Int {
        if FirebaseMigrationFlags.useServerStats, let stats = statsListener.payPeriodStats {
            return stats.daysWorked
        }
        let cal = Calendar.current
        return Set(workEntries.map { cal.startOfDay(for: $0.date) }).count
    }

    private var totalCycleDays: Int { max(1, cycle.spanDays) }

    private var daysFraction: Double {
        min(1, max(0, Double(daysWorked) / Double(totalCycleDays)))
    }

    private var hoursFraction: Double {
        let target = max(1, Double(totalCycleDays) * 8.0)
        return min(1, max(0, periodHours / target))
    }

    private var subtitleLine: String {
        cycle.chequeRangeText(settings: store.paySettings)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            Text(subtitleLine)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.subtext)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if store.paySettings.showPayCalculations {
                AnimatedMetricText(currency: periodPay, code: store.paySettings.currencyCode)
                    .font(AppDesignSystem.Typography.heroNumerals(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.text)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 18) {
                PayCycleStatRing(
                    progress: animatedDaysFraction,
                    value: "\(daysWorked)",
                    caption: daysWorked == 1 ? "day worked" : "days worked",
                    ringColors: prestigeTier.daysRingColors,
                    reduceMotion: reduceMotion
                )
                PayCycleStatRing(
                    progress: animatedHoursFraction,
                    value: AppTheme.Format.hours(periodHours),
                    caption: "this cheque",
                    ringColors: prestigeTier.hoursRingColors,
                    reduceMotion: reduceMotion
                )
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(AppDesignSystem.Spacing.md)
        .background(PayCycleCardStyle.cardBackground(theme: theme))
        .overlay(PayCycleCardStyle.cardBorder(theme: theme))
        .shadow(color: theme.accent.opacity(glowPulse), radius: 8, x: 0, y: 4)
        .id(store.gamificationProfile.prestige)
        .onAppear {
            animateRingProgress()
            guard !reduceMotion else {
                glowPulse = 0.16
                return
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                glowPulse = 0.16
            }
        }
        .onChange(of: daysFraction) { _, _ in animateRingProgress() }
        .onChange(of: hoursFraction) { _, _ in animateRingProgress() }
        .onChange(of: periodHours) { _, _ in animateRingProgress() }
        .onChange(of: store.gamificationProfile.prestige) { _, _ in
            animateRingProgress()
        }
    }

    private func animateRingProgress() {
        let anim = AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)
        withAnimation(anim) {
            animatedDaysFraction = daysFraction
            animatedHoursFraction = hoursFraction
        }
    }
}
