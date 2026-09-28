import Foundation

/// Lifetime milestones on the You tab: money earned, total hours, shifts
/// logged. Data-driven — add a row to `IncomeMilestone.all` for a new one.
struct IncomeMilestone: Identifiable, Equatable {
    enum Kind: String {
        case earnings
        case hours
        case shifts
    }

    let kind: Kind
    let threshold: Double

    /// Stable across releases — persisted in the "seen" set.
    var id: String { "\(kind.rawValue)_\(Int(threshold))" }

    static let all: [IncomeMilestone] = [
        IncomeMilestone(kind: .earnings, threshold: 10_000),
        IncomeMilestone(kind: .earnings, threshold: 25_000),
        IncomeMilestone(kind: .earnings, threshold: 50_000),
        IncomeMilestone(kind: .earnings, threshold: 100_000),
        IncomeMilestone(kind: .hours, threshold: 1_000),
        IncomeMilestone(kind: .shifts, threshold: 100)
    ]

    var icon: String {
        switch kind {
        case .earnings: return "dollarsign.circle.fill"
        case .hours: return "clock.fill"
        case .shifts: return "briefcase.fill"
        }
    }

    /// "Lifetime earnings" / "Total hours" / "Shifts logged".
    var categoryLabel: String {
        switch kind {
        case .earnings: return "Lifetime earnings"
        case .hours: return "Total hours"
        case .shifts: return "Shifts logged"
        }
    }

    /// Headline value: "$10,000", "1,000", "100".
    func valueText(currencyCode: String) -> String {
        IncomeMilestoneFormat.value(threshold, kind: kind, currencyCode: currencyCode)
    }

    /// Row title: "$10,000 earned", "1,000 total hours", "100 shifts".
    func title(currencyCode: String) -> String {
        let value = valueText(currencyCode: currencyCode)
        switch kind {
        case .earnings: return "\(value) earned"
        case .hours: return "\(value) total hours"
        case .shifts: return "\(value) shifts"
        }
    }
}

/// One milestone's standing for the current user.
struct IncomeMilestoneProgress: Identifiable, Equatable {
    let milestone: IncomeMilestone
    /// Lifetime total in the milestone's unit.
    let current: Double
    /// Date of the entry on which the running total first crossed the
    /// threshold; `nil` while unreached.
    let reachedDate: Date?

    var id: String { milestone.id }
    var isReached: Bool { reachedDate != nil }
    var remaining: Double { max(0, milestone.threshold - current) }
    var fraction: Double {
        guard milestone.threshold > 0 else { return 0 }
        return min(1, max(0, current / milestone.threshold))
    }
}

// MARK: - Calculation

enum IncomeMilestoneCalculator {
    /// A worked, priced entry. Pay is `nil`-free: 0 when pay can't be computed.
    struct Shift {
        let date: Date
        let hours: Double
        let pay: Double
    }

    /// Every worked entry (not an off day, paid hours > 0), priced with the
    /// store's own `payBreakdown(for:)` so earnings match History.
    static func shifts(store: HoursStore) -> [Shift] {
        store.allEntriesIncludingArchive().compactMap { entry in
            guard !entry.isOffDay else { return nil }
            let hours = entry.paidHours
            guard hours.isFinite, hours > 0 else { return nil }
            let pay = store.payBreakdown(for: entry).pay
            return Shift(date: entry.date, hours: hours, pay: pay.isFinite && pay > 0 ? pay : 0)
        }
    }

    static func progress(store: HoursStore) -> [IncomeMilestoneProgress] {
        progress(
            shifts: shifts(store: store),
            includeEarnings: store.paySettings.showPayCalculations
        )
    }

    /// Walks shifts oldest-first; each milestone's reached date is the date
    /// of the shift whose running total first meets its threshold.
    static func progress(
        shifts: [Shift],
        includeEarnings: Bool,
        milestones: [IncomeMilestone] = IncomeMilestone.all
    ) -> [IncomeMilestoneProgress] {
        let active = milestones.filter { includeEarnings || $0.kind != .earnings }
        guard !active.isEmpty else { return [] }

        let ordered = shifts.sorted { $0.date < $1.date }
        var pay = 0.0, hours = 0.0, count = 0.0
        var reached: [String: Date] = [:]

        for shift in ordered {
            pay += shift.pay
            hours += shift.hours
            count += 1
            for m in active where reached[m.id] == nil {
                if total(for: m.kind, pay: pay, hours: hours, count: count) >= m.threshold - 0.0001 {
                    reached[m.id] = shift.date
                }
            }
        }

        return active.map { m in
            IncomeMilestoneProgress(
                milestone: m,
                current: total(for: m.kind, pay: pay, hours: hours, count: count),
                reachedDate: reached[m.id]
            )
        }
    }

    private static func total(for kind: IncomeMilestone.Kind, pay: Double, hours: Double, count: Double) -> Double {
        switch kind {
        case .earnings: return pay
        case .hours: return hours
        case .shifts: return count
        }
    }
}

// MARK: - Seen / celebrated tracking

/// Which milestones this device has already celebrated. Local-only and
/// account-bound — cleared alongside the other per-account local data.
enum IncomeMilestoneSeenStore {
    static let key = "milestones_celebrated_v1"

    /// Only milestones crossed this recently pop a celebration; older ones
    /// (backfilled history, a cloud restore landing after first launch) are
    /// marked seen silently so a restore never floods the screen.
    static let celebrationWindowDays = 30

    static var hasInitialized: Bool {
        UserDefaults.standard.object(forKey: key) != nil
    }

    static var seen: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func markSeen(_ ids: some Sequence<String>) {
        let merged = seen.union(ids)
        UserDefaults.standard.set(merged.sorted(), forKey: key)
    }

    static func removeAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Records every reached milestone as seen and returns the one to
    /// celebrate now, if any. First run seeds the set without celebrating.
    /// When several cross at once, the last in list order (the biggest)
    /// is celebrated and the rest are marked seen with it.
    static func consumeNewlyReached(
        _ rows: [IncomeMilestoneProgress],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> IncomeMilestoneProgress? {
        let reached = rows.filter(\.isReached)
        guard hasInitialized else {
            markSeen(reached.map(\.id))
            return nil
        }
        let known = seen
        let fresh = reached.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return nil }
        markSeen(fresh.map(\.id))

        let cutoff = calendar.date(
            byAdding: .day,
            value: -celebrationWindowDays,
            to: calendar.startOfDay(for: now)
        ) ?? .distantPast
        return fresh.last { ($0.reachedDate ?? .distantPast) >= cutoff }
    }
}

// MARK: - Formatting

enum IncomeMilestoneFormat {
    static func value(_ value: Double, kind: IncomeMilestone.Kind, currencyCode: String) -> String {
        switch kind {
        case .earnings:
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = currencyCode
            f.maximumFractionDigits = 0
            f.minimumFractionDigits = 0
            return f.string(from: NSNumber(value: value.rounded(.down))) ?? "$\(Int(value))"
        case .hours, .shifts:
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: value.rounded(.down))) ?? "\(Int(value))"
        }
    }

    /// "$1,240 to go" / "212 hours to go" / "1 shift to go".
    static func remaining(_ row: IncomeMilestoneProgress, currencyCode: String) -> String {
        let kind = row.milestone.kind
        let amount = row.remaining.rounded(.up)
        let text = value(amount, kind: kind, currencyCode: currencyCode)
        switch kind {
        case .earnings: return "\(text) to go"
        case .hours: return "\(text) \(amount == 1 ? "hour" : "hours") to go"
        case .shifts: return "\(text) \(amount == 1 ? "shift" : "shifts") to go"
        }
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
