import Combine
import Foundation

/// A savings goal ("Vacation: $2,400"). Progress is what the user actually
/// puts aside — the amount saved when the goal was set plus each deposit they
/// record — so every number on screen is one they entered. The only estimate
/// is the timeline, and it is plain division: what's left over the monthly
/// amount they said they plan to save.
struct EarningsGoal: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var targetAmount: Double
    /// Saved before the goal was created (entered in the editor).
    var alreadySaved: Double = 0
    /// What the user plans to set aside each month; 0 means not set, and the
    /// goal simply has no timeline.
    var monthlyContribution: Double = 0
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
        case id, name, targetAmount, alreadySaved, monthlyContribution, createdAt, deposits
    }

    /// Goals saved by older builds lack newer keys (`deposits`,
    /// `monthlyContribution`); decode them with defaults instead of failing,
    /// which would drop every saved goal.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        targetAmount = try c.decode(Double.self, forKey: .targetAmount)
        alreadySaved = try c.decodeIfPresent(Double.self, forKey: .alreadySaved) ?? 0
        monthlyContribution = try c.decodeIfPresent(Double.self, forKey: .monthlyContribution) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        deposits = try c.decodeIfPresent([GoalDeposit].self, forKey: .deposits) ?? []
    }
}

/// Derived, display-ready numbers for one goal.
struct EarningsGoalProgress: Identifiable {
    let goal: EarningsGoal

    var id: UUID { goal.id }
    var progress: Double { goal.savedTotal }
    var remaining: Double { max(0, goal.targetAmount - progress) }
    var isComplete: Bool { goal.targetAmount > 0 && remaining <= 0.005 }
    var fraction: Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(1, max(0, progress / goal.targetAmount))
    }

    /// Whole months to finish at the planned monthly amount; nil when there
    /// is no plan (or the goal is already reached).
    var monthsToGo: Int? {
        guard !isComplete, goal.monthlyContribution > 0.005 else { return nil }
        return Int((remaining / goal.monthlyContribution).rounded(.up))
    }
}

// MARK: - Calculation

enum EarningsGoalCalculator {
    static func progress(for goals: [EarningsGoal]) -> [EarningsGoalProgress] {
        goals.map { EarningsGoalProgress(goal: $0) }
    }

    /// "About 7 months to go", "About 1 month to go", "About 2 years to go".
    static func timelineText(months: Int) -> String {
        if months >= 24 {
            let years = (Double(months) / 12).rounded()
            return "About \(Int(years)) years to go"
        }
        return months == 1 ? "About 1 month to go" : "About \(months) months to go"
    }
}

// MARK: - Persistence

/// Local-only goal storage (UserDefaults JSON, like certificates and pay
/// history). Account-bound: cleared on sign-out and on delete-all-data so a
/// goal never follows the phone to the next account.
final class EarningsGoalStore: ObservableObject {
    static let shared = EarningsGoalStore()

    private static let storageKey = "earnings_goals_v1"
    /// The expenses list was retired; its saved data is deleted on launch.
    private static let legacyExpensesKey = "goal_expenses_v1"

    @Published private(set) var goals: [EarningsGoal] = []

    private init() {
        UserDefaults.standard.removeObject(forKey: Self.legacyExpensesKey)
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
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyExpensesKey)
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
