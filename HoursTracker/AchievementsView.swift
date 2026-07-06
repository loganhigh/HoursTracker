import SwiftUI

/// Lightweight badge payload synced to Firestore for friend profile display.
struct SharedBadgeSummary: Identifiable, Equatable, Hashable {
    var id: String { name }
    let icon: String
    let name: String
    let detail: String
    let isLegend: Bool
    let order: Int
}

struct AchievementsView: View {
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var authService: AuthService
    /// When true, renders only the achievements content (no ScrollView, nav, toolbar). Use when embedding in ProfileView.
    var embedded: Bool = false

    /// Owner / CEO status — strictly gated by Firebase UID via `DeveloperConfig`.
    /// Email-based gating was removed to avoid shipping a personal address in the
    /// binary and to prevent collisions if any user enters that email in pay
    /// settings.
    private var isOwner: Bool {
        DeveloperConfig.isCEO(uid: authService.user?.uid)
    }

    /// Developer badge: only awarded when Apple user ID is in DeveloperConfig.developerUserIDs.
    private var isDeveloper: Bool {
        guard let id = authService.user?.uid else { return false }
        return DeveloperConfig.developerUserIDs.contains(id)
    }

    // MARK: - Stats derived from entries
    private var stats: Stats { Stats(from: store) }

    private var ceoBadge: Badge? {
        if isOwner {
            return Badge(
                icon: "crown.fill",
                name: "CEO",
                detail: "Owner Status",
                isUnlocked: true,
                isLegend: true,
                progress: 1.0,
                order: 0
            )
        }
        return nil
    }

    /// Developer badge: only shown when the current user's Firebase UID is in
    /// `DeveloperConfig.developerUserIDs`. Rendered in its own dedicated section.
    private var developerBadge: Badge? {
        guard isDeveloper else { return nil }
        return Badge(
            icon: "hammer.fill",
            name: "Developer",
            detail: "Built Hour Tracker",
            isUnlocked: true,
            isLegend: true,
            progress: 1.0,
            order: 5
        )
    }

    private var achievementsContent: some View {
        // Build Stats and the badge list exactly once per render. Previously
        // `stats` and `BadgeFactory.makeBadges(stats:)` were recomputed via three
        // separate computed properties each read twice — ~6 full passes over the
        // user's entire shift history on every render of this screen.
        let allBadges = BadgeFactory.makeBadges(stats: stats)
        let earnedBadges = allBadges.filter { $0.isUnlocked && !$0.isLegend }.sorted { $0.order < $1.order }
        let lockedBadges = allBadges.filter { !$0.isUnlocked && !$0.isLegend }.sorted { $0.order < $1.order }
        let legendBadges = allBadges.filter { $0.isLegend }.sorted { $0.order < $1.order }
        return VStack(spacing: 24) {
            if let ceo = ceoBadge {
                badgeSection(title: "Owner Badge", count: 1) { badgesGrid(badges: [ceo]) }
            }
            if let dev = developerBadge {
                badgeSection(title: "Developer Badge", count: 1) { badgesGrid(badges: [dev]) }
            }
            if !earnedBadges.isEmpty {
                badgeSection(title: "Earned Badges", count: earnedBadges.count) { badgesGrid(badges: earnedBadges) }
            }
            if earnedBadges.isEmpty && ceoBadge == nil && developerBadge == nil {
                EmptyStateView(
                    icon: "rosette",
                    title: "No badges yet — keep going!",
                    subtitle: "Log shifts to unlock your first badge."
                )
                .padding(.vertical, 16)
            }
            if !lockedBadges.isEmpty {
                badgeSection(title: "Locked Badges", count: lockedBadges.count) { badgesGrid(badges: lockedBadges) }
            }
            if !legendBadges.isEmpty {
                badgeSection(title: "Legend Badges", count: legendBadges.filter { $0.isUnlocked }.count) { badgesGrid(badges: legendBadges) }
            }
            Text("Badges unlock automatically from your hours & patterns.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 16)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, embedded ? 0 : 10)
        .padding(.bottom, embedded ? 24 : 32)
    }

    var body: some View {
        Group {
            if embedded {
                achievementsContent
            } else {
                ScrollView {
                    achievementsContent
                }
                .background(AppTheme.Colors.bg.ignoresSafeArea())
                .navigationTitle("Badges")
            }
        }
    }

    /// Public helper so other views can show the earned badge count without
    /// duplicating the Stats/BadgeFactory computation.
    static func earnedBadgeCount(for store: HoursStore) -> Int {
        earnedBadgesForSharing(from: store).filter { !$0.isLegend }.count
    }

    /// Earned badges serialized for the public profile doc so friends can
    /// see which badges someone has unlocked.
    static func earnedBadgesForSharing(from store: HoursStore) -> [SharedBadgeSummary] {
        let stats = Stats(from: store)
        return BadgeFactory.makeBadges(stats: stats)
            .filter(\.isUnlocked)
            .sorted { $0.order < $1.order }
            .map {
                SharedBadgeSummary(
                    icon: $0.icon,
                    name: $0.name,
                    detail: $0.detail,
                    isLegend: $0.isLegend,
                    order: $0.order
                )
            }
    }

    // MARK: - Badge UI

    private func badgeSection<Content: View>(title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AppDesignSystem.Typography.heroNumerals(size: 22, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.text)
                Spacer()
                Text("\(count)")
                    .font(AppDesignSystem.Typography.heroNumerals(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
            content()
        }
    }

    private func badgesGrid(badges: [Badge]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 16
        ) {
            ForEach(badges) { b in
                BadgeTile(badge: b)
            }
        }
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = store.paySettings.currencyCode
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

// MARK: - Self-contained types (NO external dependencies)

private struct Stats {
    let totalHours: Double
    let totalDays: Int           // total shifts (entries.count)
    let distinctDays: Int        // unique calendar days worked
    let saturdays: Int           // distinct Saturdays worked
    let sundays: Int             // distinct Sundays worked
    let overtimeDays: Int        // distinct days with OT > 0
    let longDaysOver12: Int      // shifts >= 12 hours
    let longDaysOver14: Int      // shifts >= 14 hours
    let maxShiftHours: Double
    let bestStreak: Int          // max consecutive worked days
    let bestLongShift12hStreak: Int // consecutive shifts >= 12h
    let noBreakDays: Int
    let nightShiftCount: Int
    let graveyardShiftCount: Int
    let maxMonthlyHours: Double  // max hours in any single month
    let maxMonthlyOvertimeHours: Double
    let maxWeeklyHours: Double   // max hours in any single week
    let maxYearlyHours: Double
    let monthsWorked: Int
    let hasPerfectMonth: Bool
    let hasEveryWeekendWorkedMonth: Bool
    let perfectWeekExists: Bool  // any week with 7 distinct worked days
    let firstEntryDate: Date?

    init(from store: HoursStore) {
        let entries = store.entries
        let cal = Calendar.current
        let breakdowns = entries.map { store.payBreakdown(for: $0) }

        totalHours = entries.reduce(0) { $0 + $1.paidHours }
        totalDays = entries.count
        longDaysOver12 = entries.filter { $0.paidHours >= 12 }.count
        longDaysOver14 = entries.filter { $0.paidHours >= 14 }.count
        maxShiftHours = entries.map(\.paidHours).max() ?? 0
        noBreakDays = entries.filter { !$0.isOffDay && $0.breakMinutes == 0 && $0.paidHours >= 6 }.count
        nightShiftCount = entries.filter {
            let hour = cal.component(.hour, from: $0.start)
            return hour >= 20 || hour < 4
        }.count
        graveyardShiftCount = entries.filter {
            let hour = cal.component(.hour, from: $0.start)
            return hour >= 22 || hour < 3
        }.count
        firstEntryDate = entries.map(\.date).min()

        let workDates = Set(entries.map { cal.startOfDay(for: $0.date) })
        distinctDays = workDates.count

        saturdays = Set(entries.filter { cal.component(.weekday, from: $0.date) == 7 }.map { cal.startOfDay(for: $0.date) }).count
        sundays = Set(entries.filter { cal.component(.weekday, from: $0.date) == 1 }.map { cal.startOfDay(for: $0.date) }).count

        let otEntries = entries.enumerated().filter { breakdowns[$0.offset].overtimeHours > 0 }
        overtimeDays = Set(otEntries.map { cal.startOfDay(for: $0.element.date) }).count

        bestStreak = Stats.computeBestStreak(dates: Array(workDates), calendar: cal)
        bestLongShift12hStreak = Stats.computeBestLongShiftStreak(entries: entries, calendar: cal, minHours: 12)
        maxMonthlyHours = Stats.computeMaxMonthlyHours(entries: entries, calendar: cal)
        maxMonthlyOvertimeHours = Stats.computeMaxMonthlyOvertimeHours(entries: entries, breakdowns: breakdowns, calendar: cal)
        maxWeeklyHours = Stats.computeMaxWeeklyHours(entries: entries, calendar: cal)
        maxYearlyHours = Stats.computeMaxYearlyHours(entries: entries, calendar: cal)
        monthsWorked = Set(entries.map { cal.date(from: cal.dateComponents([.year, .month], from: $0.date)) ?? $0.date }).count
        hasPerfectMonth = Stats.computeHasPerfectMonth(dates: Array(workDates), calendar: cal)
        hasEveryWeekendWorkedMonth = Stats.computeHasEveryWeekendWorkedMonth(dates: Array(workDates), calendar: cal)
        perfectWeekExists = Stats.computePerfectWeekExists(dates: Array(workDates), calendar: cal)
    }

    private static func computeBestStreak(dates: [Date], calendar: Calendar) -> Int {
        guard !dates.isEmpty else { return 0 }
        let sorted = Array(Set(dates)).sorted()
        var best = 1
        var current = 1
        for i in 1..<sorted.count {
            let prev = calendar.startOfDay(for: sorted[i - 1])
            let curr = calendar.startOfDay(for: sorted[i])
            let daysDiff = calendar.dateComponents([.day], from: prev, to: curr).day ?? 0
            if daysDiff == 1 {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }

    private static func computeMaxMonthlyHours(entries: [WorkEntry], calendar: Calendar) -> Double {
        var monthToHours: [Date: Double] = [:]
        for e in entries {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: e.date)) ?? e.date
            monthToHours[monthStart, default: 0] += e.paidHours
        }
        return monthToHours.values.max() ?? 0
    }

    private static func computeMaxMonthlyOvertimeHours(entries: [WorkEntry], breakdowns: [HoursStore.PayBreakdown], calendar: Calendar) -> Double {
        var monthToOT: [Date: Double] = [:]
        for (index, e) in entries.enumerated() {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: e.date)) ?? e.date
            monthToOT[monthStart, default: 0] += breakdowns[index].overtimeHours
        }
        return monthToOT.values.max() ?? 0
    }
    
    private static func computeMaxWeeklyHours(entries: [WorkEntry], calendar: Calendar) -> Double {
        var cal = calendar
        cal.firstWeekday = 1 // Sunday
        var weekToHours: [Date: Double] = [:]
        
        for entry in entries {
            if let weekStart = cal.dateInterval(of: .weekOfYear, for: entry.date)?.start {
                weekToHours[weekStart, default: 0] += entry.paidHours
            }
        }
        return weekToHours.values.max() ?? 0
    }

    private static func computeMaxYearlyHours(entries: [WorkEntry], calendar: Calendar) -> Double {
        var yearToHours: [Int: Double] = [:]
        for e in entries {
            let year = calendar.component(.year, from: e.date)
            yearToHours[year, default: 0] += e.paidHours
        }
        return yearToHours.values.max() ?? 0
    }

    private static func computeBestLongShiftStreak(entries: [WorkEntry], calendar: Calendar, minHours: Double) -> Int {
        let longShiftDays = entries
            .filter { $0.paidHours >= minHours }
            .map { calendar.startOfDay(for: $0.date) }
        guard !longShiftDays.isEmpty else { return 0 }
        let sorted = Array(Set(longShiftDays)).sorted()
        var best = 1
        var current = 1
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            let diff = calendar.dateComponents([.day], from: prev, to: curr).day ?? 0
            if diff == 1 {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }

    private static func computeHasPerfectMonth(dates: [Date], calendar: Calendar) -> Bool {
        let workedDays = Set(dates.map { calendar.startOfDay(for: $0) })
        let monthStarts = Set(workedDays.map { calendar.date(from: calendar.dateComponents([.year, .month], from: $0)) ?? $0 })
        for monthStart in monthStarts {
            guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else { continue }
            var workedCount = 0
            for day in dayRange {
                guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
                if workedDays.contains(calendar.startOfDay(for: date)) {
                    workedCount += 1
                }
            }
            if workedCount == dayRange.count {
                return true
            }
        }
        return false
    }

    private static func computeHasEveryWeekendWorkedMonth(dates: [Date], calendar: Calendar) -> Bool {
        let workedDays = Set(dates.map { calendar.startOfDay(for: $0) })
        let monthStarts = Set(workedDays.map { calendar.date(from: calendar.dateComponents([.year, .month], from: $0)) ?? $0 })
        for monthStart in monthStarts {
            guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else { continue }
            var weekendDaysInMonth: [Date] = []
            for day in dayRange {
                guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
                let weekday = calendar.component(.weekday, from: date)
                if weekday == 1 || weekday == 7 {
                    weekendDaysInMonth.append(calendar.startOfDay(for: date))
                }
            }
            guard !weekendDaysInMonth.isEmpty else { continue }
            let allWorked = weekendDaysInMonth.allSatisfy { workedDays.contains($0) }
            if allWorked { return true }
        }
        return false
    }

    private static func computePerfectWeekExists(dates: [Date], calendar: Calendar) -> Bool {
        var cal = calendar
        cal.firstWeekday = 1
        for d in dates {
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: d)?.start else { continue }
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let daysInWeek = dates.filter { $0 >= weekStart && $0 < weekEnd }
            let distinct = Set(daysInWeek.map { calendar.startOfDay(for: $0) })
            if distinct.count >= 7 { return true }
        }
        return false
    }
}

private struct Badge: Identifiable {
    let id = UUID()
    let icon: String
    let name: String
    let detail: String
    let isUnlocked: Bool
    let isLegend: Bool
    let progress: Double // 0..1
    let order: Int
}

private enum BadgeFactory {
    static func makeBadges(stats: Stats) -> [Badge] {
        func hoursBadge(_ target: Double, icon: String, name: String, detail: String? = nil, order: Int, legend: Bool = false) -> Badge {
            let p = target <= 0 ? 0 : min(1, max(0, stats.totalHours / target))
            let d = detail ?? "Logged \(Int(target)) hours"
            return Badge(
                icon: icon,
                name: name,
                detail: d,
                isUnlocked: stats.totalHours >= target,
                isLegend: legend,
                progress: p,
                order: order
            )
        }

        func countBadge(_ value: Int, target: Int, icon: String, name: String, detail: String, order: Int, legend: Bool = false) -> Badge {
            let p = target <= 0 ? 0 : min(1, max(0, Double(value) / Double(target)))
            return Badge(
                icon: icon,
                name: name,
                detail: detail,
                isUnlocked: value >= target,
                isLegend: legend,
                progress: p,
                order: order
            )
        }

        func doubleBadge(_ value: Double, target: Double, icon: String, name: String, detail: String, order: Int, legend: Bool = false) -> Badge {
            let p = target <= 0 ? 0 : min(1, max(0, value / target))
            return Badge(
                icon: icon,
                name: name,
                detail: detail,
                isUnlocked: value >= target,
                isLegend: legend,
                progress: p,
                order: order
            )
        }

        func boolBadge(_ value: Bool, icon: String, name: String, detail: String, order: Int, legend: Bool = false) -> Badge {
            return Badge(
                icon: icon,
                name: name,
                detail: detail,
                isUnlocked: value,
                isLegend: legend,
                progress: value ? 1 : 0,
                order: order
            )
        }

        var badges: [Badge] = []
        func appendUnique(_ badge: Badge) {
            guard !badges.contains(where: { $0.name == badge.name }) else { return }
            badges.append(badge)
        }

        // Existing core achievements
        appendUnique(hoursBadge(50, icon: "clock.fill", name: "50 Hours", order: 10))
        appendUnique(hoursBadge(100, icon: "clock.badge.checkmark.fill", name: "100 Hours", order: 20))
        appendUnique(hoursBadge(250, icon: "speedometer", name: "250 Hours", order: 30))
        appendUnique(hoursBadge(500, icon: "flame.fill", name: "500 Hours", order: 40))
        appendUnique(hoursBadge(750, icon: "flame.fill", name: "750 Hours", order: 45))
        appendUnique(hoursBadge(1000, icon: "trophy.fill", name: "1,000 Hours", order: 50))
        appendUnique(hoursBadge(1250, icon: "trophy.fill", name: "1,250 Hours", order: 55))
        appendUnique(hoursBadge(1500, icon: "star.fill", name: "1,500 Hours", order: 60))
        appendUnique(hoursBadge(1750, icon: "star.fill", name: "1,750 Hours", order: 65))
        appendUnique(hoursBadge(2000, icon: "flag.fill", name: "2,000 Hours", order: 70))
        appendUnique(hoursBadge(2500, icon: "bolt.circle.fill", name: "2,500 Hours", order: 80))
        appendUnique(hoursBadge(3000, icon: "crown.fill", name: "3,000 Hours", order: 90))
        appendUnique(hoursBadge(4000, icon: "crown.fill", name: "4,000 Hours", detail: "Logged 4,000 hours", order: 95))

        appendUnique(countBadge(stats.totalDays, target: 10, icon: "checkmark.circle", name: "10 Shifts Logged", detail: "Logged 10 shifts", order: 110))
        appendUnique(countBadge(stats.totalDays, target: 25, icon: "checkmark.circle", name: "25 Shifts Logged", detail: "Logged 25 shifts", order: 115))
        appendUnique(countBadge(stats.totalDays, target: 50, icon: "checkmark.seal.fill", name: "50 Shifts Logged", detail: "Logged 50 shifts", order: 120))
        appendUnique(countBadge(stats.totalDays, target: 100, icon: "checkmark.seal.fill", name: "100 Shifts Logged", detail: "Logged 100 shifts", order: 130))
        appendUnique(countBadge(stats.totalDays, target: 200, icon: "checkmark.seal.fill", name: "200 Shifts Logged", detail: "Logged 200 shifts", order: 140))
        appendUnique(countBadge(stats.totalDays, target: 500, icon: "checkmark.seal.fill", name: "500 Shifts Logged", detail: "Logged 500 shifts", order: 150))

        appendUnique(countBadge(stats.bestStreak, target: 7, icon: "flame.fill", name: "No Days Off", detail: "7 consecutive days worked", order: 155))
        appendUnique(countBadge(stats.bestStreak, target: 14, icon: "flame.fill", name: "14-Day Streak", detail: "14 consecutive days worked", order: 160))

        appendUnique(countBadge(stats.overtimeDays, target: 1, icon: "bolt.fill", name: "First Overtime Shift", detail: "1 OT shift", order: 165))
        appendUnique(countBadge(stats.overtimeDays, target: 10, icon: "bolt.fill", name: "Overtime Beast", detail: "10 OT days", order: 170))
        appendUnique(countBadge(stats.overtimeDays, target: 20, icon: "bolt.fill", name: "Overtime King", detail: "20 OT days", order: 172))
        appendUnique(countBadge(stats.longDaysOver12, target: 1, icon: "figure.walk.motion", name: "Longest Shift Logged", detail: "Log a 12+ hour shift", order: 175))
        appendUnique(countBadge(stats.longDaysOver12, target: 5, icon: "figure.walk.motion", name: "12h Warrior", detail: "5x 12h shifts", order: 180))
        appendUnique(countBadge(stats.longDaysOver14, target: 1, icon: "sunrise.fill", name: "Sunrise to Sunset", detail: "14+ hour day", order: 182))

        appendUnique(countBadge(stats.saturdays, target: 3, icon: "calendar.badge.clock", name: "Weekend Starter", detail: "Worked 3 Saturdays", order: 185))
        appendUnique(countBadge(stats.saturdays, target: 10, icon: "calendar.badge.clock", name: "Saturday Grinder", detail: "Worked 10 Saturdays", order: 187))
        appendUnique(countBadge(stats.sundays, target: 2, icon: "sun.max.fill", name: "Sunday Double-Time", detail: "Worked 2 Sundays", order: 190))
        appendUnique(countBadge(stats.sundays, target: 5, icon: "sun.max.fill", name: "Sunday Warrior", detail: "Worked 5 Sundays", order: 192))

        appendUnique(countBadge(stats.totalDays, target: 20, icon: "checkmark.seal.fill", name: "Consistent", detail: "Logged 20 days", order: 195))
        appendUnique(countBadge(stats.totalDays, target: 60, icon: "crown.fill", name: "Work Machine", detail: "Logged 60 days", order: 200))

        appendUnique(hoursBadge(5000, icon: "crown.fill", name: "5,000 Hours Logged", detail: "Logged 5,000 hours", order: 300, legend: true))
        appendUnique(hoursBadge(7500, icon: "crown.fill", name: "7,500 Hours Logged", detail: "Logged 7,500 hours", order: 310, legend: true))
        appendUnique(hoursBadge(10000, icon: "crown.fill", name: "10,000 Hours Logged", detail: "Logged 10,000 hours", order: 320, legend: true))
        appendUnique(countBadge(stats.totalDays, target: 1000, icon: "checkmark.seal.fill", name: "1,000 Shifts Logged", detail: "Logged 1,000 shifts", order: 330, legend: true))
        appendUnique(countBadge(stats.distinctDays, target: 100, icon: "calendar.badge.checkmark", name: "Consistency King", detail: "100 distinct days worked", order: 340, legend: true))
        appendUnique(countBadge(stats.longDaysOver12, target: 25, icon: "figure.walk.motion", name: "Long-Haul", detail: "25 shifts of 12+ hours", order: 350, legend: true))
        appendUnique(doubleBadge(stats.maxMonthlyHours, target: 200, icon: "dumbbell.fill", name: "200h Month Monster", detail: "200+ hours in a single month", order: 360, legend: true))
        appendUnique(doubleBadge(stats.maxMonthlyHours, target: 200, icon: "star.circle.fill", name: "Two-Hundred Club", detail: "200+ hours in a single month", order: 365, legend: true))
        appendUnique(doubleBadge(stats.maxWeeklyHours, target: 60, icon: "bolt.heart.fill", name: "60 Hour Beast", detail: "60+ hours in a single week", order: 367, legend: true))
        appendUnique(doubleBadge(stats.maxWeeklyHours, target: 80, icon: "flame.circle.fill", name: "80 Hour Demon", detail: "80+ hours in a single week", order: 368, legend: true))
        appendUnique(countBadge(stats.overtimeDays, target: 60, icon: "bolt.circle.fill", name: "OT Legend", detail: "60 OT days", order: 370, legend: true))
        appendUnique(countBadge(stats.overtimeDays, target: 30, icon: "bolt.circle.fill", name: "OT Addict", detail: "30 OT days", order: 375, legend: true))
        appendUnique(boolBadge(stats.perfectWeekExists, icon: "checkmark.circle.fill", name: "Perfect Week", detail: "7 days in one week", order: 380, legend: true))
        appendUnique(countBadge(stats.sundays, target: 6, icon: "sparkles", name: "Sunday Demon", detail: "Worked 6 Sundays", order: 390, legend: true))

        // Special / status
        appendUnique(boolBadge(stats.firstEntryDate != nil, icon: "clock.arrow.circlepath", name: "Early Adopter", detail: "Started tracking early", order: 12))
        appendUnique(boolBadge(stats.firstEntryDate != nil, icon: "person.crop.circle.badge.checkmark", name: "OG User", detail: "One of the originals", order: 14))
        appendUnique(boolBadge(stats.totalDays >= 30, icon: "building.columns.fill", name: "Founding Member", detail: "Built your foundation here", order: 15))
        appendUnique(doubleBadge(stats.totalHours, target: 9000, icon: "chart.bar.doc.horizontal.fill", name: "Top 1% Grinder", detail: "Elite work output", order: 16, legend: true))

        // Expanded hour milestones
        appendUnique(hoursBadge(3500, icon: "crown.fill", name: "3,500 Hours", order: 92))
        appendUnique(hoursBadge(4500, icon: "crown.fill", name: "4,500 Hours", order: 97))
        appendUnique(hoursBadge(5000, icon: "crown.fill", name: "5,000 Hours", detail: "Logged 5,000 hours", order: 301, legend: true))
        appendUnique(hoursBadge(6000, icon: "crown.fill", name: "6,000 Hours", detail: "Logged 6,000 hours", order: 305, legend: true))
        appendUnique(hoursBadge(7000, icon: "crown.fill", name: "7,000 Hours", detail: "Logged 7,000 hours", order: 308, legend: true))
        appendUnique(hoursBadge(8000, icon: "crown.fill", name: "8,000 Hours", detail: "Logged 8,000 hours", order: 312, legend: true))
        appendUnique(hoursBadge(9000, icon: "crown.fill", name: "9,000 Hours", detail: "Logged 9,000 hours", order: 316, legend: true))
        appendUnique(hoursBadge(12000, icon: "crown.fill", name: "12,000 Hours", detail: "Logged 12,000 hours", order: 321, legend: true))
        appendUnique(hoursBadge(15000, icon: "crown.fill", name: "15,000 Hours", detail: "Logged 15,000 hours", order: 322, legend: true))
        appendUnique(hoursBadge(20000, icon: "crown.fill", name: "20,000 Hours", detail: "Logged 20,000 hours", order: 323, legend: true))
        appendUnique(hoursBadge(25000, icon: "crown.fill", name: "25,000 Hours", detail: "Logged 25,000 hours", order: 324, legend: true))

        // Expanded shift counts
        appendUnique(countBadge(stats.totalDays, target: 750, icon: "checkmark.seal.fill", name: "750 Shifts Logged", detail: "Logged 750 shifts", order: 151))
        appendUnique(countBadge(stats.totalDays, target: 1500, icon: "checkmark.seal.fill", name: "1,500 Shifts Logged", detail: "Logged 1,500 shifts", order: 332, legend: true))
        appendUnique(countBadge(stats.totalDays, target: 2000, icon: "checkmark.seal.fill", name: "2,000 Shifts Logged", detail: "Logged 2,000 shifts", order: 334, legend: true))
        appendUnique(countBadge(stats.totalDays, target: 3000, icon: "checkmark.seal.fill", name: "3,000 Shifts Logged", detail: "Logged 3,000 shifts", order: 336, legend: true))
        appendUnique(countBadge(stats.totalDays, target: 5000, icon: "checkmark.seal.fill", name: "5,000 Shifts Logged", detail: "Logged 5,000 shifts", order: 338, legend: true))

        // Streaks / consistency
        appendUnique(countBadge(stats.bestStreak, target: 3, icon: "flame.fill", name: "3-Day Streak", detail: "3 consecutive days worked", order: 152))
        appendUnique(countBadge(stats.bestStreak, target: 5, icon: "flame.fill", name: "5-Day Streak", detail: "5 consecutive days worked", order: 153))
        appendUnique(countBadge(stats.bestStreak, target: 10, icon: "flame.fill", name: "10-Day Streak", detail: "10 consecutive days worked", order: 156))
        appendUnique(countBadge(stats.bestStreak, target: 21, icon: "flame.fill", name: "21-Day Streak", detail: "21 consecutive days worked", order: 161))
        appendUnique(countBadge(stats.bestStreak, target: 30, icon: "flame.fill", name: "30-Day Streak", detail: "30 consecutive days worked", order: 162))
        appendUnique(countBadge(stats.bestStreak, target: 60, icon: "flame.fill", name: "60-Day Streak", detail: "60 consecutive days worked", order: 163))
        appendUnique(countBadge(stats.bestStreak, target: 90, icon: "flame.fill", name: "90-Day Streak", detail: "90 consecutive days worked", order: 164))
        appendUnique(countBadge(stats.bestStreak, target: 180, icon: "flame.fill", name: "6-Month Streak", detail: "180 consecutive days worked", order: 166, legend: true))
        appendUnique(countBadge(stats.bestStreak, target: 365, icon: "flame.fill", name: "1-Year Streak", detail: "365 consecutive days worked", order: 167, legend: true))
        appendUnique(countBadge(stats.bestStreak, target: 30, icon: "calendar.badge.checkmark", name: "Never Miss", detail: "30 days without missing", order: 168))

        // Long shifts / grind
        appendUnique(doubleBadge(stats.maxShiftHours, target: 10, icon: "hourglass", name: "10h Shift", detail: "Logged a 10+ hour shift", order: 176))
        appendUnique(doubleBadge(stats.maxShiftHours, target: 14, icon: "hourglass", name: "14h Shift", detail: "Logged a 14+ hour shift", order: 177))
        appendUnique(doubleBadge(stats.maxShiftHours, target: 16, icon: "hourglass", name: "16h Shift", detail: "Logged a 16+ hour shift", order: 178))
        appendUnique(doubleBadge(stats.maxShiftHours, target: 18, icon: "bolt.heart.fill", name: "18h Iron Man", detail: "Logged an 18+ hour shift", order: 179, legend: true))
        appendUnique(doubleBadge(stats.maxShiftHours, target: 20, icon: "flame.circle.fill", name: "20h Madness", detail: "Logged a 20+ hour shift", order: 181, legend: true))
        appendUnique(doubleBadge(stats.maxShiftHours, target: 16, icon: "arrow.triangle.2.circlepath", name: "Double Shift Day", detail: "Pulled a double shift", order: 183))
        appendUnique(countBadge(stats.bestLongShift12hStreak, target: 2, icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", name: "Back-to-Back Long Shifts", detail: "2 consecutive 12h+ shifts", order: 184))
        appendUnique(countBadge(stats.noBreakDays, target: 5, icon: "nosign", name: "No Break Grind", detail: "5 long shifts with no break", order: 186))
        appendUnique(countBadge(stats.nightShiftCount, target: 10, icon: "moon.stars.fill", name: "Night Shift Survivor", detail: "Worked 10 night shifts", order: 188))
        appendUnique(countBadge(stats.graveyardShiftCount, target: 25, icon: "moon.zzz.fill", name: "Graveyard King", detail: "Worked 25 graveyard shifts", order: 189))

        // Monthly performance
        appendUnique(doubleBadge(stats.maxMonthlyHours, target: 100, icon: "calendar", name: "First 100h Month", detail: "Logged 100 hours in a month", order: 201))
        appendUnique(doubleBadge(stats.maxMonthlyHours, target: 150, icon: "calendar", name: "150h Month", detail: "Logged 150 hours in a month", order: 202))
        appendUnique(doubleBadge(stats.maxMonthlyHours, target: 180, icon: "calendar", name: "180h Month", detail: "Logged 180 hours in a month", order: 203))
        appendUnique(doubleBadge(stats.maxMonthlyHours, target: 200, icon: "calendar", name: "200h Month", detail: "Logged 200 hours in a month", order: 204))
        appendUnique(doubleBadge(stats.maxMonthlyHours, target: 220, icon: "calendar", name: "220h Month", detail: "Logged 220 hours in a month", order: 206))
        appendUnique(doubleBadge(stats.maxMonthlyHours, target: 250, icon: "calendar", name: "250h Month", detail: "Logged 250 hours in a month", order: 207, legend: true))
        appendUnique(doubleBadge(stats.maxMonthlyHours, target: 300, icon: "calendar", name: "300h Month", detail: "Logged 300 hours in a month", order: 208, legend: true))
        appendUnique(boolBadge(stats.hasPerfectMonth, icon: "calendar.badge.checkmark", name: "Perfect Month", detail: "Worked every day in a month", order: 209, legend: true))
        appendUnique(boolBadge(stats.hasPerfectMonth, icon: "calendar.badge.checkmark", name: "No Days Missed Month", detail: "No missed days in a month", order: 210, legend: true))
        appendUnique(doubleBadge(stats.maxMonthlyOvertimeHours, target: 20, icon: "bolt.fill", name: "Overtime Month", detail: "20+ overtime hours in a month", order: 211))
        appendUnique(doubleBadge(stats.maxMonthlyHours, target: 280, icon: "flame.fill", name: "Insane Month", detail: "280+ hours in a month", order: 212, legend: true))

        // Weekly performance
        appendUnique(doubleBadge(stats.maxWeeklyHours, target: 40, icon: "calendar.badge.clock", name: "40 Hour Week", detail: "Worked 40+ hours in a week", order: 213))
        appendUnique(doubleBadge(stats.maxWeeklyHours, target: 50, icon: "calendar.badge.clock", name: "50 Hour Week", detail: "Worked 50+ hours in a week", order: 214))
        appendUnique(doubleBadge(stats.maxWeeklyHours, target: 70, icon: "calendar.badge.clock", name: "70 Hour Week", detail: "Worked 70+ hours in a week", order: 215))
        appendUnique(boolBadge(stats.perfectWeekExists, icon: "calendar.badge.checkmark", name: "No Days Missed Week", detail: "Worked every day in a week", order: 216))
        appendUnique(boolBadge(stats.perfectWeekExists && stats.maxWeeklyHours >= 60, icon: "flame.fill", name: "Full Grind Week", detail: "Perfect week with heavy hours", order: 217))
        appendUnique(boolBadge(stats.perfectWeekExists && stats.bestStreak >= 14, icon: "lock.shield", name: "Locked-In Week", detail: "Dialed in for a full week", order: 218))

        // Weekend grind
        appendUnique(countBadge(stats.saturdays + stats.sundays, target: 20, icon: "calendar", name: "Weekend Warrior", detail: "Worked 20 weekend days", order: 219))
        appendUnique(boolBadge(stats.saturdays >= 8 && stats.sundays >= 8, icon: "calendar", name: "No Days Off Weekend", detail: "Worked heavy weekend volume", order: 220))
        appendUnique(boolBadge(stats.hasEveryWeekendWorkedMonth, icon: "calendar", name: "Every Weekend Worked (Month)", detail: "Worked every weekend day in a month", order: 221, legend: true))

        // Discipline / logging behavior
        appendUnique(countBadge(stats.totalDays, target: 1, icon: "checkmark.circle.fill", name: "First Shift Logged", detail: "Logged your first shift", order: 222))
        appendUnique(countBadge(stats.totalDays, target: 5, icon: "checkmark.circle.fill", name: "First Week Logged", detail: "Logged your first week", order: 223))
        appendUnique(countBadge(stats.monthsWorked, target: 1, icon: "calendar", name: "First Month Logged", detail: "Logged shifts in your first month", order: 224))
        appendUnique(boolBadge(stats.perfectWeekExists, icon: "list.bullet.clipboard", name: "Logged Every Shift This Week", detail: "Perfect weekly logging", order: 225))
        appendUnique(boolBadge(stats.hasPerfectMonth, icon: "list.bullet.clipboard", name: "Logged Every Shift This Month", detail: "Perfect monthly logging", order: 226))
        appendUnique(countBadge(stats.bestStreak, target: 7, icon: "checkmark.circle", name: "No Missed Logs (7 Days)", detail: "Logged daily for 7 days", order: 227))
        appendUnique(countBadge(stats.bestStreak, target: 30, icon: "checkmark.circle", name: "No Missed Logs (30 Days)", detail: "Logged daily for 30 days", order: 228))
        appendUnique(countBadge(stats.totalDays, target: 25, icon: "folder", name: "Organized Worker", detail: "Consistent logging habit", order: 229))
        appendUnique(countBadge(stats.totalDays, target: 100, icon: "clock.arrow.circlepath", name: "Always Tracking", detail: "100 logged shifts", order: 230))
        appendUnique(countBadge(stats.totalDays, target: 150, icon: "clock.badge.checkmark", name: "Never Late Logger", detail: "150 logged shifts", order: 231))
        appendUnique(countBadge(stats.bestStreak, target: 30, icon: "calendar.badge.clock", name: "Daily Logger", detail: "30-day logging streak", order: 232))
        appendUnique(countBadge(stats.totalDays, target: 30, icon: "sparkles", name: "Habit Builder", detail: "Built a strong logging habit", order: 233))

        // Progression / comeback energy
        appendUnique(countBadge(stats.totalDays, target: 14, icon: "arrow.clockwise", name: "Back on Track", detail: "Logged 14 shifts", order: 234))
        appendUnique(countBadge(stats.bestStreak, target: 7, icon: "arrow.uturn.forward.circle", name: "Restarted Strong", detail: "Strong comeback streak", order: 235))
        appendUnique(countBadge(stats.bestStreak, target: 30, icon: "figure.strengthtraining.traditional", name: "No Quit Mentality", detail: "30-day streak", order: 236))
        appendUnique(doubleBadge(stats.totalHours, target: 2000, icon: "person.2.badge.gearshape", name: "Built Different", detail: "Crossed 2,000 hours", order: 237))
        appendUnique(countBadge(stats.totalDays, target: 365, icon: "calendar", name: "Still Going", detail: "365 shifts logged", order: 238))
        appendUnique(countBadge(stats.bestStreak, target: 60, icon: "flame", name: "Relentless", detail: "60-day streak", order: 239))
        appendUnique(doubleBadge(stats.maxWeeklyHours, target: 70, icon: "speedometer", name: "All Gas No Brakes", detail: "70+ hour week", order: 240))
        appendUnique(doubleBadge(stats.totalHours, target: 1000, icon: "arrow.up.forward.circle", name: "Leveling Up", detail: "Hit 1,000 hours", order: 241))
        appendUnique(doubleBadge(stats.totalHours, target: 3000, icon: "arrow.up.forward.circle.fill", name: "Next Level", detail: "Hit 3,000 hours", order: 242))
        appendUnique(doubleBadge(stats.totalHours, target: 6000, icon: "star.circle.fill", name: "Elite Worker", detail: "Hit 6,000 hours", order: 243, legend: true))

        // Rare / flex
        appendUnique(countBadge(stats.totalDays, target: 365, icon: "calendar.badge.checkmark", name: "365 Days Logged", detail: "365 shifts logged", order: 391, legend: true))
        appendUnique(countBadge(stats.bestStreak, target: 90, icon: "calendar.badge.checkmark", name: "No Days Missed (90 Days)", detail: "90-day streak", order: 392, legend: true))
        appendUnique(countBadge(stats.bestStreak, target: 180, icon: "calendar.badge.checkmark", name: "No Days Missed (180 Days)", detail: "180-day streak", order: 393, legend: true))
        appendUnique(countBadge(stats.bestLongShift12hStreak, target: 7, icon: "figure.run", name: "7-Day 12h+ Streak", detail: "7 consecutive 12h+ shifts", order: 394, legend: true))
        appendUnique(countBadge(stats.bestStreak, target: 30, icon: "figure.walk", name: "30 Days Straight Worked", detail: "30-day work streak", order: 395, legend: true))
        appendUnique(countBadge(stats.bestStreak, target: 60, icon: "figure.walk", name: "60 Days Straight Worked", detail: "60-day work streak", order: 396, legend: true))
        appendUnique(countBadge(stats.bestStreak, target: 100, icon: "figure.walk", name: "100 Days Straight Worked", detail: "100-day work streak", order: 397, legend: true))
        appendUnique(doubleBadge(stats.maxYearlyHours, target: 1000, icon: "chart.bar.xaxis", name: "1,000 Hours in a Year", detail: "Logged 1,000 hours in one year", order: 398, legend: true))
        appendUnique(doubleBadge(stats.maxYearlyHours, target: 2000, icon: "chart.bar.xaxis", name: "2,000 Hours in a Year", detail: "Logged 2,000 hours in one year", order: 399, legend: true))
        appendUnique(doubleBadge(stats.maxShiftHours, target: 18, icon: "timer.circle.fill", name: "Marathon Worker", detail: "18+ hour shift", order: 401, legend: true))

        // Fun / personality
        appendUnique(doubleBadge(stats.totalHours, target: 500, icon: "checkmark.seal", name: "Built for This", detail: "500+ hours logged", order: 244))
        appendUnique(doubleBadge(stats.totalHours, target: 2500, icon: "sparkles", name: "Different Breed", detail: "2,500+ hours logged", order: 245))
        appendUnique(countBadge(stats.totalDays, target: 250, icon: "rosette", name: "Certified Grinder", detail: "250 shifts logged", order: 246))
        appendUnique(countBadge(stats.totalDays, target: 7, icon: "power", name: "Work Mode Activated", detail: "Logged 7 shifts", order: 247))
        appendUnique(doubleBadge(stats.maxWeeklyHours, target: 60, icon: "bolt.fill", name: "Beast Mode", detail: "60+ hour week", order: 248))
        appendUnique(countBadge(stats.bestStreak, target: 45, icon: "switch.2", name: "No Off Switch", detail: "45-day streak", order: 249))
        appendUnique(countBadge(stats.overtimeDays, target: 30, icon: "diamond.fill", name: "Pressure Makes Diamonds", detail: "30 OT days", order: 250))
        appendUnique(countBadge(stats.totalDays, target: 50, icon: "sunrise", name: "Rise & Grind", detail: "50 shifts logged", order: 251))
        appendUnique(countBadge(stats.bestStreak, target: 21, icon: "lock.fill", name: "Locked In", detail: "21-day streak", order: 252))
        appendUnique(countBadge(stats.totalDays, target: 1, icon: "target", name: "Make It Count", detail: "Started your tracking journey", order: 253))

        return badges
    }
}

private struct BadgeTile: View {
    let badge: Badge

    var body: some View {
        let locked = !badge.isUnlocked

        VStack(spacing: 6) {
            ZStack {
                if locked {
                    ProgressRing(progress: badge.progress)
                        .frame(width: 64, height: 64)
                }

                Circle()
                    .fill(
                        locked
                        ? AnyShapeStyle(AppTheme.Colors.card2)
                        : AnyShapeStyle(AppTheme.Colors.accentGradient)
                    )
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .stroke(
                                locked ? AppTheme.Colors.stroke : Color.white.opacity(0.25),
                                lineWidth: locked ? 0.5 : 1
                            )
                    )
                    .shadow(color: locked ? Color.clear : AppTheme.Colors.accent.opacity(0.45), radius: 10, y: 3)

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.subtext)
                } else {
                    Image(systemName: badge.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 68)

            VStack(spacing: 2) {
                Text(badge.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(locked ? AppTheme.Colors.subtext.opacity(0.8) : AppTheme.Colors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .frame(height: 32, alignment: .top)

                Text(badge.detail)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.subtext.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .frame(height: 28, alignment: .top)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
    }
}

private struct ProgressRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.Colors.stroke.opacity(0.7), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AppTheme.Colors.accentGradient,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}
