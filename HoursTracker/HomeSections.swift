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
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    var body: some View {
        // Plain tier-colour surface: text on the left, the sun path on the
        // right. At accessibility sizes the dome drops below the text.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.md))
                : AnyLayout(HStackLayout(alignment: .center, spacing: AppSpacing.xs))
            layout {
                VStack(alignment: .leading, spacing: 0) {
                    Text("TODAY")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(Color.white.opacity(0.78))
                    Text(Self.weekdayFormatter.string(from: context.date))
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 6)
                    Text(context.date.formatted(.dateTime.month(.wide).day().year()))
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.top, 2)
                    weatherPill
                        .padding(.top, AppSpacing.md)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SunDome(now: context.date, times: sunTimes(on: context.date))
            }
        }
        .padding(.vertical, 20)
        .padding(.leading, 22)
        .padding(.trailing, 18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.heroSurface)
        )
        .onAppear { weather.refreshIfNeeded() }
    }

    private func sunTimes(on date: Date) -> (sunrise: Date, sunset: Date)? {
        guard let snapshot = weather.snapshot else { return nil }
        return SunTimes.sunriseSunset(on: date, latitude: snapshot.latitude, longitude: snapshot.longitude)
    }

    @ViewBuilder
    private var weatherPill: some View {
        switch weather.status {
        case .loaded where weather.snapshot != nil:
            let snapshot = weather.snapshot!
            pill {
                Image(systemName: snapshot.symbolName)
                    .symbolRenderingMode(.multicolor)
                Text("\(snapshot.temperatureText) · \(snapshot.conditionText)")
            }
            .accessibilityElement(children: .combine)

        case .loading, .loaded:
            pill {
                LoadingDots()
                Text("Checking the weather…")
            }

        case .needsPermission:
            // Permission is asked for on the tap, not on launch — nobody
            // opens an hours app expecting a location prompt.
            Button { weather.requestPermission() } label: {
                pill { sunBadge; Text("Tap for local weather") }
            }
            .buttonStyle(.plain)

        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                pill { Image(systemName: "location.slash"); Text("Allow location for weather") }
            }
            .buttonStyle(.plain)

        case .failed:
            Button { weather.refreshIfNeeded(force: true) } label: {
                pill { Image(systemName: "arrow.clockwise"); Text("Weather unavailable") }
            }
            .buttonStyle(.plain)
        }
    }

    private var sunBadge: some View {
        Image(systemName: "sun.max.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(red: 0.10, green: 0.07, blue: 0))
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color(red: 0.95, green: 0.76, blue: 0.31)))
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 7) { content() }
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 7)
            .padding(.leading, 9)
            .padding(.trailing, 12)
            .background(Capsule().fill(Color.black.opacity(0.28)))
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
        HStack(spacing: 10) {
            HomeStatTile(icon: "clock", band: "WEEK", label: "This week", hours: weekHours, tone: 0)
            HomeStatTile(icon: "banknote", band: "CHEQUE", label: "This cheque", hours: chequeHours, tone: 1)
            HomeStatTile(icon: "calendar", band: "MONTH", label: "This month", hours: monthHours, tone: 2)
        }
    }
}

/// A stat in the calendar-leaf shape: a tinted band with an icon and short
/// label, then the hours and a plain label, all centred. The three tiles step
/// through slightly different tints of the tier accent with equal weight.
struct HomeStatTile: View {
    let icon: String
    let band: String
    let label: String
    let hours: Double
    /// 0, 1, 2: band tint step.
    let tone: Int
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(band)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .tracking(1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.white.opacity(0.82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(AppColors.accent.opacity(0.26 + Double(tone) * 0.05))

            VStack(spacing: 5) {
                HoursValue(hours: hours, size: 28, unitSize: 13, gap: 5)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(AppColors.subtext)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .padding(.horizontal, 6)
        }
        .multilineTextAlignment(.center)
        .homeCard(radius: 18)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
