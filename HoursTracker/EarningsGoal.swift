import Combine
import Foundation

/// A work-powered earnings goal ("Vacation: $2,400"). Progress is funded by
/// the pay of shifts logged on/after the day the goal was created, plus any
/// amount the user had already put aside. Goals don't split earnings — every
/// goal counts the same shifts independently.
struct EarningsGoal: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var targetAmount: Double
    var alreadySaved: Double = 0
    var createdAt: Date = Date()
}

/// Derived, display-ready numbers for one goal.
struct EarningsGoalProgress: Identifiable {
    let goal: EarningsGoal
    /// Pay from shifts dated on/after the goal's creation day.
    let earnedFromShifts: Double
    /// `nil` when there's no usable average (no paid shifts yet).
    let shiftsNeeded: Int?

    var id: UUID { goal.id }
    var progress: Double { goal.alreadySaved + earnedFromShifts }
    var remaining: Double { max(0, goal.targetAmount - progress) }
    var isComplete: Bool { goal.targetAmount > 0 && remaining <= 0.005 }
    var fraction: Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(1, max(0, progress / goal.targetAmount))
    }
}

// MARK: - Calculation

enum EarningsGoalCalculator {
    /// Window for "current average earnings". Falls back to all-time when the
    /// user hasn't logged a paid shift in this window.
    static let averageLookbackDays = 90

    /// Every paid work shift up to now, priced with the store's own
    /// `payBreakdown(for:)` — the same pay figure History and the cheque
    /// views show, overtime and holiday rules included.
    static func pricedShifts(store: HoursStore, now: Date = Date()) -> [(date: Date, pay: Double)] {
        store.allEntriesIncludingArchive().compactMap { entry in
            guard !entry.isOffDay, entry.paidHours > 0, entry.date <= now else { return nil }
            let pay = store.payBreakdown(for: entry).pay
            guard pay.isFinite, pay > 0 else { return nil }
            return (entry.date, pay)
        }
    }

    /// Average pay per shift over the lookback window, else all-time.
    static func averagePerShift(
        _ shifts: [(date: Date, pay: Double)],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double? {
        let cutoff = calendar.date(
            byAdding: .day,
            value: -averageLookbackDays,
            to: calendar.startOfDay(for: now)
        ) ?? .distantPast
        let recent = shifts.filter { $0.date >= cutoff }
        let pool = recent.isEmpty ? shifts : recent
        guard !pool.isEmpty else { return nil }
        let avg = pool.reduce(0) { $0 + $1.pay } / Double(pool.count)
        return avg.isFinite && avg > 0 ? avg : nil
    }

    static func progress(
        for goals: [EarningsGoal],
        store: HoursStore,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [EarningsGoalProgress] {
        guard !goals.isEmpty else { return [] }
        let shifts = pricedShifts(store: store, now: now)
        let average = averagePerShift(shifts, now: now, calendar: calendar)
        return goals.map { goal in
            let start = calendar.startOfDay(for: goal.createdAt)
            let earned = shifts.reduce(0) { $1.date >= start ? $0 + $1.pay : $0 }
            let remaining = max(0, goal.targetAmount - goal.alreadySaved - earned)
            var needed: Int?
            if let average {
                needed = remaining <= 0.005 ? 0 : Int((remaining / average).rounded(.up))
            }
            return EarningsGoalProgress(goal: goal, earnedFromShifts: earned, shiftsNeeded: needed)
        }
    }
}

// MARK: - Persistence

/// Local-only goal storage (UserDefaults JSON, like certificates and pay
/// history). Account-bound: cleared on sign-out and on delete-all-data so a
/// goal never follows the phone to the next account.
final class EarningsGoalStore: ObservableObject {
    static let shared = EarningsGoalStore()

    private static let storageKey = "earnings_goals_v1"

    @Published private(set) var goals: [EarningsGoal] = []

    private init() {
        load()
    }

    func add(_ goal: EarningsGoal) {
        goals.append(goal)
        save()
    }

    func update(_ goal: EarningsGoal) {
        guard let idx = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[idx] = goal
        save()
    }

    func delete(id: UUID) {
        goals.removeAll { $0.id == id }
        save()
    }

    func removeAll() {
        goals.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([EarningsGoal].self, from: data) else { return }
        goals = decoded
    }
}
