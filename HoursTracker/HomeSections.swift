import SwiftUI

// MARK: - Home Sections (Phase 3 — Hero Ledger home)
//
// Small, explicit-dependency section views extracted from HoursHomeView so
// its `body` stays a short list the type-checker resolves quickly.
// Companion file: HomeListsSections.swift (recent shifts / yearly / friends).

// MARK: - Today Hero (the ONE hero card on Home)

/// Today's date with the local weather beneath it. Cheque hours live in the
/// stat triplet below, the pay projection in History, and prestige on the You
/// tab — so this card is purely "what's today like". No owl here (user's call):
/// Home's only owl is on the tip card.
struct TodayHeroCard: View {
    @ObservedObject var store: HoursStore
    @ObservedObject private var weather = WeatherService.shared
    @Environment(\.openURL) private var openURL

    private static let todayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    var body: some View {
        // A solid block of the tier colour, like a Duolingo unit banner:
        // the one loud surface on Home, so prestige shows at a glance.
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Today")
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textOnAccent.opacity(0.8))

            Text(Self.todayFormatter.string(from: Date()))
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundStyle(AppColors.textOnAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            weatherRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .chunkyCard(fill: AppColors.accent, border: AppColors.accent.opacity(0.0), radius: 22)
        .onAppear { weather.refreshIfNeeded() }
    }

    /// Text colours for the solid accent fill: full and dimmed on-accent.
    private var onAccent: Color { AppColors.textOnAccent }
    private var onAccentDim: Color { AppColors.textOnAccent.opacity(0.8) }

    @ViewBuilder
    private var weatherRow: some View {
        switch weather.status {
        case .loaded where weather.snapshot != nil:
            let snapshot = weather.snapshot!
            HStack(spacing: 6) {
                Image(systemName: snapshot.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(AppTypography.subheadline.weight(.semibold))
                Text(snapshot.temperatureText)
                    .font(AppTypography.headline)
                    .monospacedDigit()
                    .foregroundStyle(onAccent)
                Text(snapshot.locality.isEmpty
                     ? snapshot.conditionText
                     : "\(snapshot.conditionText) · \(snapshot.locality)")
                    .appText(.subheadline)
                    .foregroundStyle(onAccentDim)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .combine)

        case .loading, .loaded:
            HStack(spacing: 6) {
                LoadingDots()
                Text("Checking the weather…")
                    .appText(.subheadline)
                    .foregroundStyle(onAccentDim)
            }

        case .needsPermission:
            // Permission is asked for on the tap, not on launch — nobody
            // opens an hours app expecting a location prompt.
            Button { weather.requestPermission() } label: {
                Label("Tap to show local weather", systemImage: "location.fill")
                    .font(AppTypography.subheadline.weight(.bold))
                    .foregroundStyle(onAccent)
            }
            .buttonStyle(.plain)

        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Allow location in Settings for weather", systemImage: "location.slash")
                    .appText(.caption)
                    .foregroundStyle(onAccentDim)
            }
            .buttonStyle(.plain)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

        case .failed:
            Button { weather.refreshIfNeeded(force: true) } label: {
                Label("Weather unavailable — tap to retry", systemImage: "arrow.clockwise")
                    .appText(.caption)
                    .foregroundStyle(onAccentDim)
            }
            .buttonStyle(.plain)
        }
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
                .legendShimmer(PrestigeTheme.tier(for: profile.prestige))
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

// MARK: - Stat Triplet (Week / Cheque / Month)

struct HomeStatTriplet: View {
    @ObservedObject var store: HoursStore

    // MARK: Week sums (follows the "Week starts on" setting, matching the pay engine's week)

    private func hoursInWeek(containing date: Date) -> Double {
        var cal = Calendar.current
        cal.firstWeekday = store.paySettings.weekStartWeekday ?? 2
        guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return store.entries
            .filter { !$0.isOffDay && $0.date >= interval.start && $0.date < interval.end }
            .reduce(0) { $0 + $1.paidHours }
    }

    private var weekHours: Double { hoursInWeek(containing: Date()) }

    // MARK: Cheque hours

    /// Paid hours in the live pay period — the number the Today card used to
    /// lead with.
    private var chequeHours: Double {
        PayCycleEngine.entries(store.entries, in: store.currentPayCycle())
            .reduce(0) { $0 + $1.paidHours }
    }

    // MARK: Month sums

    private var monthHours: Double { store.monthTotalHours(monthDate: Date()) }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            HomeStatTile(icon: "clock.fill", tint: AppColors.accent, label: "Week", value: AppTheme.Format.hours(weekHours))
            HomeStatTile(icon: "banknote.fill", tint: AppColors.positive, label: "Cheque", value: AppTheme.Format.hours(chequeHours))
            HomeStatTile(icon: "calendar", tint: AppColors.streak, label: "Month", value: AppTheme.Format.hours(monthHours))
        }
    }
}

/// Duolingo-style stat tile: coloured icon, bold number, small label.
struct HomeStatTile: View {
    let icon: String
    let tint: Color
    let label: String
    /// Pre-formatted display value — "72.63h" or a bare day count.
    let value: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.system(.body, weight: .heavy))
                .foregroundStyle(tint)

            Text(value)
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .heavy))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.subtext)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .padding(.horizontal, AppSpacing.xxs)
        .chunkyCard()
    }
}
