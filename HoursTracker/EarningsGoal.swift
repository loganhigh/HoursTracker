import Combine
import Foundation

/// A work-powered earnings goal ("Vacation: $2,400"). Progress is what the
/// user actually puts aside — the amount saved when the goal was set plus
/// each deposit they record — not every dollar they earn, so it stays
/// accurate. Shifts come in as the estimate of how many more it'll take.
struct EarningsGoal: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var targetAmount: Double
    /// Saved before the goal was created (entered in the editor).
    var alreadySaved: Double = 0
    var createdAt: Date = Date()
    /// Money the user has put toward the goal since, newest last.
    var deposits: [GoalDeposit] = []

    var savedTotal: Double { alreadySaved + deposits.reduce(0) { $0 + $1.amount } }
}

/// One amount the user put toward a goal.
struct GoalDeposit: Identifiable, Codable, Equatable {
    var id = UUID()
    var amount: Double
    var date: Date = Date()
}

extension EarningsGoal {
    private enum CodingKeys: String, CodingKey {
        case id, name, targetAmount, alreadySaved, createdAt, deposits
    }

    /// Goals saved before deposits existed have no `deposits` key; decode
    /// them with an empty list instead of failing (which would drop every
    /// saved goal).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        targetAmount = try c.decode(Double.self, forKey: .targetAmount)
        alreadySaved = try c.decodeIfPresent(Double.self, forKey: .alreadySaved) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        deposits = try c.decodeIfPresent([GoalDeposit].self, forKey: .deposits) ?? []
    }
}

/// A regular living cost (rent, car, phone). Goals use the total to work
/// out what a shift really leaves over for saving.
struct GoalExpense: Identifiable, Codable, Equatable {
    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case weekly, biweekly, monthly, yearly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .weekly: return "Weekly"
            case .biweekly: return "Every 2 weeks"
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            }
        }
        /// Occurrences per average month.
        var perMonth: Double {
            switch self {
            case .weekly: return 52.0 / 12.0
            case .biweekly: return 26.0 / 12.0
            case .monthly: return 1
            case .yearly: return 1.0 / 12.0
            }
        }
    }

    var id = UUID()
    var name: String
    var amount: Double
    var frequency: Frequency = .monthly

    var monthlyAmount: Double { amount * frequency.perMonth }
}

/// Derived, display-ready numbers for one goal.
struct EarningsGoalProgress: Identifiable {
    let goal: EarningsGoal
    /// `nil` when there's no usable average (no paid shifts yet), or when
    /// expenses use up everything a shift earns (`expensesExceedPay`).
    let shiftsNeeded: Int?
    /// Sum of the user's expenses per month; 0 when none are entered.
    var monthlyExpenses: Double = 0
    /// Expenses take all of an average shift's pay, so no number of shifts
    /// reaches the goal at the current pace.
    var expensesExceedPay: Bool = false

    var id: UUID { goal.id }
    var progress: Double { goal.savedTotal }
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

    /// How the user is working: average pay per shift and shifts per month.
    struct Pace: Equatable {
        let averagePay: Double
        let shiftsPerMonth: Double
    }

    /// Pace over the lookback window, else all-time. Shifts per month is
    /// measured over the span the shifts actually cover (never shorter than
    /// two weeks, so a brand-new user's first busy days don't read as a
    /// 30-shift month).
    static func pace(
        _ shifts: [(date: Date, pay: Double)],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Pace? {
        let cutoff = calendar.date(
            byAdding: .day,
            value: -averageLookbackDays,
            to: calendar.startOfDay(for: now)
        ) ?? .distantPast
        let recent = shifts.filter { $0.date >= cutoff }
        let pool = recent.isEmpty ? shifts : recent
        guard let first = pool.map(\.date).min(), let last = pool.map(\.date).max() else { return nil }
        let avg = pool.reduce(0) { $0 + $1.pay } / Double(pool.count)
        guard avg.isFinite, avg > 0 else { return nil }

        let spanEnd = recent.isEmpty ? last : now
        let spanDays = (spanEnd.timeIntervalSince(first) / 86_400) + 1
        let clampedDays = min(Double(averageLookbackDays), max(14, spanDays))
        let perMonth = Double(pool.count) / clampedDays * 30.44
        return Pace(averagePay: avg, shiftsPerMonth: perMonth)
    }

    /// What one shift leaves for saving once expenses are covered: average
    /// pay minus the expenses a month's shifts have to carry, per shift.
    static func savingsPerShift(pace: Pace, monthlyExpenses: Double) -> Double {
        guard monthlyExpenses > 0, pace.shiftsPerMonth > 0 else { return pace.averagePay }
        return pace.averagePay - monthlyExpenses / pace.shiftsPerMonth
    }

    static func progress(
        for goals: [EarningsGoal],
        store: HoursStore,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [EarningsGoalProgress] {
        guard !goals.isEmpty else { return [] }
        let shifts = pricedShifts(store: store, now: now)
        let pace = pace(shifts, now: now, calendar: calendar)
        let monthlyExpenses = EarningsGoalStore.shared.monthlyExpenses
        return goals.map { goal in
            let remaining = max(0, goal.targetAmount - goal.savedTotal)
            var needed: Int?
            var exceeds = false
            if let pace {
                let perShift = savingsPerShift(pace: pace, monthlyExpenses: monthlyExpenses)
                if remaining <= 0.005 {
                    needed = 0
                } else if perShift > 0.005 {
                    needed = Int((remaining / perShift).rounded(.up))
                } else {
                    exceeds = true
                }
            }
            return EarningsGoalProgress(
                goal: goal,
                shiftsNeeded: needed,
                monthlyExpenses: monthlyExpenses,
                expensesExceedPay: exceeds
            )
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
    private static let expensesKey = "goal_expenses_v1"

    @Published private(set) var goals: [EarningsGoal] = []
    @Published private(set) var expenses: [GoalExpense] = []

    var monthlyExpenses: Double { expenses.reduce(0) { $0 + $1.monthlyAmount } }

    private init() {
        load()
    }

    func addExpense(_ expense: GoalExpense) {
        expenses.append(expense)
        saveExpenses()
    }

    func updateExpense(_ expense: GoalExpense) {
        guard let idx = expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        expenses[idx] = expense
        saveExpenses()
    }

    func deleteExpense(id: UUID) {
        expenses.removeAll { $0.id == id }
        saveExpenses()
    }

    private func saveExpenses() {
        guard let data = try? JSONEncoder().encode(expenses) else { return }
        UserDefaults.standard.set(data, forKey: Self.expensesKey)
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

    func addDeposit(_ amount: Double, to goalID: UUID) {
        guard amount > 0, amount.isFinite,
              let idx = goals.firstIndex(where: { $0.id == goalID }) else { return }
        goals[idx].deposits.append(GoalDeposit(amount: amount))
        save()
    }

    func deleteDeposit(_ depositID: UUID, from goalID: UUID) {
        guard let idx = goals.firstIndex(where: { $0.id == goalID }) else { return }
        goals[idx].deposits.removeAll { $0.id == depositID }
        save()
    }

    func delete(id: UUID) {
        goals.removeAll { $0.id == id }
        save()
    }

    func removeAll() {
        goals.removeAll()
        expenses.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        UserDefaults.standard.removeObject(forKey: Self.expensesKey)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        defer { loadExpenses() }
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([EarningsGoal].self, from: data) else { return }
        goals = decoded
    }

    private func loadExpenses() {
        guard let data = UserDefaults.standard.data(forKey: Self.expensesKey),
              let decoded = try? JSONDecoder().decode([GoalExpense].self, from: data) else { return }
        expenses = decoded
    }
}
