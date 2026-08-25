import Foundation

// MARK: - When Wrapped is offered
//
// Pure, testable rules for "should this user be offered Wrapped right now,
// and for which year". Both the Home card and the push notification read
// from here, so there is one definition of the season rather than two that
// can drift apart.
//
// Timing: January of the following year. The year has to be *finished*
// before its numbers are worth showing — Hour Tracker users track hours for
// pay, so a total that keeps climbing through December would read as broken
// rather than exciting.

enum WrappedAvailability {

    /// Tunables for the season and the "enough data to be worth it" bar.
    enum Rules {
        /// Wrapped is offered during January (month 1) for the year before.
        static let seasonMonth = 1
        /// Either threshold qualifies: someone with few but very long shifts
        /// has just as much of a year to look back on as a high-shift-count
        /// worker, so requiring both would wrongly exclude them.
        static let minimumShifts = 20
        static let minimumHours: Double = 100
        /// Local hour on Jan 1 the "your Wrapped is ready" push fires.
        static let notificationHour = 10
        /// The earliest year Wrapped will ever be offered for.
        ///
        /// Hour Tracker shipped in early 2026, so 2025 and earlier hold
        /// little or no data — offering a "2025 Wrapped" would produce a
        /// hollow story from a year the app barely existed for. This floor
        /// means the first Wrapped anyone sees is 2026, on 1 Jan 2027.
        static let firstEligibleYear = 2026
    }

    // MARK: - Debug season override

    #if DEBUG
    /// Debug-only key that pretends it's Wrapped season right now, so the
    /// January experience can be checked outside January.
    ///
    /// When on, Wrapped is offered for the **current** year (in progress, so
    /// there is real data to look at) and the data threshold is bypassed.
    /// Both the floor and the month check are ignored. This whole block is
    /// compiled out of Release, so it cannot affect a shipping build.
    static let debugForceSeasonKey = "wrapped_debug_force_season"

    static var isDebugSeasonForced: Bool {
        UserDefaults.standard.bool(forKey: debugForceSeasonKey)
    }
    #endif

    // MARK: - Season

    /// Whether Wrapped exists at all for a given year — see
    /// `Rules.firstEligibleYear`.
    static func isEligibleYear(_ year: Int) -> Bool {
        year >= Rules.firstEligibleYear
    }

    /// The year whose Wrapped should be offered `asOf` a given date, or nil
    /// outside the season. In January 2027 this is 2026; in January 2026 it
    /// would be 2025, which predates the app, so nothing is offered.
    static func offeredYear(asOf date: Date = Date(), calendar: Calendar = .current) -> Int? {
        #if DEBUG
        if isDebugSeasonForced {
            // Current (in-progress) year, so there are real hours to look at.
            return calendar.component(.year, from: date)
        }
        #endif
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return nil }
        guard month == Rules.seasonMonth else { return nil }
        let candidate = year - 1
        guard isEligibleYear(candidate) else { return nil }
        return candidate
    }

    /// True when `date` falls inside the Wrapped season at all.
    static func isInSeason(_ date: Date = Date(), calendar: Calendar = .current) -> Bool {
        offeredYear(asOf: date, calendar: calendar) != nil
    }

    // MARK: - Data bar

    /// Whether a year has enough in it to be worth presenting. A near-empty
    /// year produces a two-slide story, which reads as broken rather than
    /// minimal — better not to offer it than to offer something hollow.
    static func meetsDataThreshold(_ stats: WrappedYearStats) -> Bool {
        stats.totalShifts >= Rules.minimumShifts || stats.totalHours >= Rules.minimumHours
    }

    // MARK: - Dismissal memory

    private static func dismissedKey(year: Int) -> String { "wrapped_home_card_dismissed_\(year)" }
    private static func notifiedKey(year: Int) -> String { "wrapped_notified_\(year)" }

    static func hasDismissedHomeCard(year: Int, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: dismissedKey(year: year))
    }

    static func markHomeCardDismissed(year: Int, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: dismissedKey(year: year))
    }

    static func hasScheduledNotification(year: Int, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: notifiedKey(year: year))
    }

    static func markNotificationScheduled(year: Int, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: notifiedKey(year: year))
    }

    // MARK: - Composite decision

    /// Whether the Home card should be visible. Note that *viewing* Wrapped
    /// deliberately does not hide the card — only an explicit dismiss does —
    /// so a user can re-watch it for the rest of January.
    static func shouldShowHomeCard(
        stats: WrappedYearStats?,
        asOf date: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let year = offeredYear(asOf: date, calendar: calendar) else { return false }
        guard let stats, stats.year == year else { return false }
        #if DEBUG
        // Forced season ignores the data bar so the card always appears.
        if isDebugSeasonForced { return !hasDismissedHomeCard(year: year, defaults: defaults) }
        #endif
        guard meetsDataThreshold(stats) else { return false }
        return !hasDismissedHomeCard(year: year, defaults: defaults)
    }

    /// How many years back the You-tab entry will look for something worth
    /// showing. Bounded so a long-time user doesn't pay for an unbounded
    /// scan, but deep enough to cover a gap year.
    private static let lookbackYears = 5

    /// The most recent **completed** year with enough data to be worth
    /// watching, or nil if there isn't one.
    ///
    /// Unlike the seasonal Home card, this is not restricted to January —
    /// it backs the permanent You-tab entry, so Wrapped stays reachable the
    /// rest of the year instead of vanishing once the card is dismissed.
    /// Only completed years are considered: an in-progress year's totals
    /// would still be moving.
    static func mostRecentEligibleYear(
        asOf date: Date = Date(),
        calendar: Calendar = .current,
        statsProvider: (Int) -> WrappedYearStats
    ) -> WrappedYearStats? {
        #if DEBUG
        if isDebugSeasonForced {
            // Offer the in-progress year so the You-tab row is visible too.
            return statsProvider(calendar.component(.year, from: date))
        }
        #endif
        let lastCompletedYear = calendar.component(.year, from: date) - 1
        // Never walk below the year the app existed from.
        let earliest = max(lastCompletedYear - lookbackYears + 1, Rules.firstEligibleYear)
        guard lastCompletedYear >= earliest else { return nil }
        for year in stride(from: lastCompletedYear, through: earliest, by: -1) {
            let stats = statsProvider(year)
            if meetsDataThreshold(stats) { return stats }
        }
        return nil
    }

    /// The moment the "your Wrapped is ready" push should fire for `year`:
    /// 10am local on January 1 of the following year.
    static func notificationDate(forYear year: Int, calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.year = year + 1
        components.month = 1
        components.day = 1
        components.hour = Rules.notificationHour
        components.minute = 0
        return calendar.date(from: components)
    }
}
