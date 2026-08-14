import SwiftUI

// MARK: - Home Sections (Phase 3 — Hero Ledger home)
//
// Small, explicit-dependency section views extracted from HoursHomeView so
// its `body` stays a short list the type-checker resolves quickly.
// Companion file: HomeListsSections.swift (recent shifts / yearly / friends).

// MARK: - Today Hero (the ONE hero card on Home)

struct TodayHeroCard: View {
    @ObservedObject var store: HoursStore
    let onPrestigeTap: () -> Void

    private static let todayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private var cycle: PayCycle { store.currentPayCycle() }

    private var cycleEntries: [WorkEntry] {
        PayCycleEngine.entries(store.entries, in: cycle)
    }

    private var chequeHours: Double {
        cycleEntries.reduce(0) { $0 + $1.paidHours }
    }

    private var chequePay: Double {
        cycleEntries.reduce(0) { $0 + store.payBreakdown(for: $1).pay }
    }

    var body: some View {
        NavigationLink {
            PayCycleDetailView(store: store, initialCycle: cycle)
        } label: {
            VStack(spacing: AppSpacing.md) {
                SectionEyebrow("Today", subtitle: Self.todayFormatter.string(from: Date()))

                // The cheque line carries the card now (the old today-hours
                // hero numeral spent most days reading "0h"), with the
                // learned pay projection beneath it once cheque totals exist.
                VStack(spacing: AppSpacing.xs) {
                    chequeLine

                    if let projection = store.currentChequeProjection() {
                        HStack(spacing: 4) {
                            Text("Projected pay")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.subtext)
                            Text("~")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.accent)
                            AnimatedMetricText(currency: projection.amount, code: store.paySettings.currencyCode)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(AppColors.accent)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                }

                // Rank is earned chrome — an "Unranked" shield is just noise.
                if store.displayedGamificationProfile().prestige > 0 {
                    prestigeRow
                }
            }
            .padding(AppSpacing.lg)
            .background(heroBackground)
            .overlay(heroStroke)
            .appShadowHero()
        }
        .buttonStyle(PremiumPressStyle())
        .id(cycle)
    }

    // One compact secondary line: "10h this cheque · Aug 2 – Aug 15", with
    // the pay amount appended when pay display is on ("· $350").
    private var chequeLine: some View {
        HStack(spacing: 4) {
            AnimatedMetricText(value: chequeHours) { AppTheme.Format.hours($0) }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.text)
            Text("this cheque · \(cycle.workRangeText())")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.subtext)
            if store.paySettings.showPayCalculations {
                Text("·")
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
                AnimatedMetricText(currency: chequePay, code: store.paySettings.currencyCode)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }

    private var prestigeRow: some View {
        let profile = store.displayedGamificationProfile()
        let tier = PrestigeTheme.tier(for: profile.prestige)
        return Button(action: onPrestigeTap) {
            Label(
                profile.prestige == 0 ? "Unranked" : "Prestige \(profile.prestige) (\(tier.name))",
                systemImage: tier.icon
            )
            .appText(.caption)
            .foregroundStyle(profile.prestige == 0 ? AppColors.subtext : tier.primary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var heroBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(AppColors.card2)
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.accent.opacity(0.14),
                            Color.clear,
                            AppColors.accent.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var heroStroke: some View {
        RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        AppColors.accent.opacity(0.4),
                        AppColors.accent.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

// MARK: - XP Strip (animated fill, cold-launch seeded from cache)

/// Persisted XP-bar cache keys. `HomeXPStrip` owns the writes; the You tab's
/// `ProfileXPCapsule` reads the same keys (read-only) so both bars cold-launch
/// seeded at the same fill instead of visibly refilling from zero.
enum XPStripCache {
    static let progressKey = "xp_strip_cached_progress_v1"
    static let levelKey = "xp_strip_cached_level_v1"
}

struct HomeXPStrip: View {
    @ObservedObject var store: HoursStore
    // Server stats drive displayedGamificationProfile(); observe so the strip
    // re-renders the moment they arrive.
    @ObservedObject private var statsListener = StatsListenerService.shared

    // Last displayed progress + level, persisted so a cold launch seeds the
    // bar at its previous fill instead of visibly refilling from zero while
    // server stats are still in flight.
    @AppStorage(XPStripCache.progressKey) private var cachedProgress: Double = 0
    @AppStorage(XPStripCache.levelKey) private var cachedLevel: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedProgress: Double = 0
    @State private var seeded = false

    private var profile: GamificationProfile { store.displayedGamificationProfile() }

    private var liveProgress: Double {
        let p = profile
        guard p.xpForNextLevel > 0 else { return 0 }
        return min(max(Double(p.xpIntoCurrentLevel) / Double(p.xpForNextLevel), 0), 1)
    }

    private var emblemColor: Color {
        profile.prestige == 0 ? AppColors.accent : PrestigeTheme.color(for: profile.prestige)
    }

    var body: some View {
        NavigationLink {
            LevelView(store: store)
        } label: {
            HStack(spacing: AppSpacing.sm) {
                emblem

                Text("LVL \(profile.level)")
                    .font(AppTypography.headline.monospacedDigit())
                    .foregroundStyle(AppColors.text)
                    .layoutPriority(1)

                progressCapsule
                    .frame(height: 30)

                if profile.currentStreak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColors.streak)
                        Text("\(profile.currentStreak)")
                            .font(AppTypography.headline.monospacedDigit())
                            .foregroundStyle(AppColors.text)
                    }
                    .layoutPriority(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.faint)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(AppColors.stroke, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PremiumPressStyle())
        .onAppear { seedAndAnimate() }
        .onChange(of: liveProgress) { _, _ in animateToLive() }
        .onChange(of: profile.level) { _, _ in animateToLive() }
    }

    private var emblem: some View {
        ZStack {
            Circle()
                .fill(emblemColor.opacity(0.15))
                .frame(width: 30, height: 30)
            Image(systemName: PrestigeTheme.tier(for: profile.prestige).icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(emblemColor)
        }
    }

    private var progressCapsule: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(AppColors.stroke.opacity(0.6))
            // The fill is liquid: it pours toward the target and sloshes as
            // it settles instead of snapping. LiquidXPFill owns the motion,
            // so displayedProgress is handed over un-animated.
            LiquidXPFill(progress: displayedProgress)
        }
        .frame(height: 6)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func seedAndAnimate() {
        if !seeded {
            seeded = true
            // Seed from the persisted fill so the bar starts where it last
            // was, then springs to the live value.
            displayedProgress = cachedProgress
        }
        animateToLive()
    }

    private func animateToLive() {
        // No withAnimation: LiquidXPFill runs its own spring toward the new
        // value (and under Reduce Motion renders the flat fill directly).
        displayedProgress = liveProgress
        persistCache()
    }

    private func persistCache() {
        let level = profile.level
        if cachedProgress != liveProgress { cachedProgress = liveProgress }
        if cachedLevel != level { cachedLevel = level }
    }
}

// MARK: - Stat Triplet (Week / Cheque / Month, with week progress)

struct HomeStatTriplet: View {
    @ObservedObject var store: HoursStore

    // MARK: Week sums (Mon–Sun, matching the pay engine's week)

    private func hoursInWeek(containing date: Date) -> Double {
        var cal = Calendar.current
        cal.firstWeekday = 2
        guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return store.entries
            .filter { !$0.isOffDay && $0.date >= interval.start && $0.date < interval.end }
            .reduce(0) { $0 + $1.paidHours }
    }

    private var weekHours: Double { hoursInWeek(containing: Date()) }

    // MARK: Cheque days

    /// Distinct calendar days with a worked (non-off-day) entry in the live
    /// pay period — two shifts on one day count once.
    private var chequeDaysWorked: Int {
        let cal = Calendar.current
        let days = PayCycleEngine.entries(store.entries, in: store.currentPayCycle())
            .filter { !$0.isOffDay }
            .map { cal.startOfDay(for: $0.date) }
        return Set(days).count
    }

    // MARK: Month sums

    private var monthHours: Double { store.monthTotalHours(monthDate: Date()) }

    var body: some View {
        HStack(spacing: AppSpacing.xs + 2) {
            HomeStatTile(label: "This Week", value: AppTheme.Format.hours(weekHours))
            // Hours this cheque already lead the hero card directly above —
            // repeating them here said nothing new. Days worked answers the
            // other question a pay period raises.
            HomeStatTile(label: "Days Worked", value: "\(chequeDaysWorked)")
            HomeStatTile(label: "This Month", value: AppTheme.Format.hours(monthHours))
        }
    }
}

/// One quiet stat tile: eyebrow label, monospaced numeral. Two text lines
/// max — nothing else.
struct HomeStatTile: View {
    let label: String
    /// Pre-formatted display value — "72.63h" or a bare day count.
    let value: String

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            Text(label)
                .appText(.eyebrow)
                .foregroundStyle(AppColors.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.6) // three tiles abreast at AX sizes

            Text(value)
                .font(AppTypography.metricValue)
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.sm + 2)
        .padding(.horizontal, AppSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 0.5)
                )
        )
    }
}
