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

    private var todayHours: Double {
        let cal = Calendar.current
        return store.entries
            .filter { cal.isDateInToday($0.date) && !$0.isOffDay }
            .reduce(0) { $0 + $1.paidHours }
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

                // ONE dominant numeral — today's hours — over one compact
                // cheque line. Zero renders quiet (subtext), never alarming,
                // and there is no instructional copy.
                VStack(spacing: AppSpacing.xs) {
                    AnimatedMetricText(value: todayHours) { AppTheme.Format.hours($0) }
                        .font(AppTypography.heroNumber)
                        .foregroundStyle(todayHours > 0 ? AppColors.text : AppColors.subtext)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    chequeLine
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
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(AppColors.text)
            Text("this cheque · \(cycle.workRangeText())")
                .appText(.caption)
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
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.stroke.opacity(0.6))
                    .frame(height: 6)
                // No fill at zero progress — an empty track is honest; a
                // floating 6pt knob reads as a rendering bug.
                if displayedProgress > 0 {
                    Capsule()
                        .fill(AppColors.accentGradient)
                        .frame(width: max(6, geo.size.width * displayedProgress), height: 6)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
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
        let target = liveProgress
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            displayedProgress = target
        }
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

    // MARK: Cheque sums

    private var chequeHours: Double {
        PayCycleEngine.entries(store.entries, in: store.currentPayCycle())
            .reduce(0) { $0 + $1.paidHours }
    }

    // MARK: Month sums

    private var monthHours: Double { store.monthTotalHours(monthDate: Date()) }

    /// Weekly reference line for the context bar: the weekly OT threshold when
    /// weekly rules apply, else daily threshold × 5. Nil hides the bar.
    private var weekTarget: Double? {
        let s = store.paySettings
        switch s.overtimeType {
        case .weekly, .dailyAndWeekly:
            return s.weeklyOvertimeThreshold > 0 ? s.weeklyOvertimeThreshold : nil
        case .daily:
            return s.weekdayOvertimeAfterHours > 0 ? s.weekdayOvertimeAfterHours * 5 : nil
        }
    }

    var body: some View {
        HStack(spacing: AppSpacing.xs + 2) {
            HomeStatTile(
                label: "This Week",
                hours: weekHours,
                progress: weekTarget.map { min(max(weekHours / $0, 0), 1) }
            )
            HomeStatTile(
                label: "This Cheque",
                hours: chequeHours,
                progress: nil
            )
            HomeStatTile(
                label: "This Month",
                hours: monthHours,
                progress: nil
            )
        }
    }
}

/// One quiet stat tile: eyebrow label, monospaced numeral, optional thin
/// context bar. Two text lines max — nothing else.
struct HomeStatTile: View {
    let label: String
    let hours: Double
    let progress: Double?

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            Text(label)
                .appText(.eyebrow)
                .foregroundStyle(AppColors.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.6) // three tiles abreast at AX sizes

            Text(AppTheme.Format.hours(hours))
                .font(AppTypography.metricValue)
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Context bar only when there is actual progress to show — an
            // empty track with a floating dot under "0h" reads as broken.
            if let progress, progress > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppColors.stroke.opacity(0.6))
                        Capsule()
                            .fill(AppColors.accentGradient)
                            .frame(width: max(3, geo.size.width * progress))
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, AppSpacing.xs)
            }
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
