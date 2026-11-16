import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFunctions

// MARK: - Welcome back to the leaderboard
//
// People with no app opens or shifts for 30+ days are left off the global
// leaderboard (functions/src/leaderboard/boardActivity.js). When one comes
// back, the app asks the server to re-rank them right away
// (`rejoinLeaderboard`) and Home shows "You're back on the board at #X".

@MainActor
final class BoardReturnCenter: ObservableObject {
    static let shared = BoardReturnCenter()

    struct Return: Equatable {
        let rank: Int?
    }

    @Published private(set) var pending: Return?

    private static let lastForegroundKey = "board_return_last_foreground_v1"
    /// Only ask the server after a gap close to the 30-day cutoff (or the
    /// first launch of this build), so normal launches cost nothing.
    private static let checkAfter: TimeInterval = 25 * 86_400

    private var checking = false

    private init() {}

    /// Call on every foreground activation.
    func appBecameActive(now: Date = Date()) {
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: Self.lastForegroundKey) as? Date
        defaults.set(now, forKey: Self.lastForegroundKey)
        guard Auth.auth().currentUser != nil, !checking else { return }
        if let last, now.timeIntervalSince(last) < Self.checkAfter { return }
        checking = true
        Task { [weak self] in
            defer { self?.checking = false }
            do {
                let result = try await Functions.functions(region: "us-central1")
                    .httpsCallable("rejoinLeaderboard")
                    .call([:])
                let data = result.data as? [String: Any] ?? [:]
                guard data["returned"] as? Bool == true else { return }
                let rank = (data["rank"] as? Int) ?? (data["rank"] as? NSNumber)?.intValue
                withAnimation(AppMotion.Spring.podium) {
                    self?.pending = Return(rank: rank.flatMap { $0 > 0 ? $0 : nil })
                }
            } catch {
                // Not worth surfacing: the 15-minute board rebuild re-ranks
                // them anyway; only the welcome card is skipped.
            }
        }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { pending = nil }
    }
}

struct BoardReturnCard: View {
    let info: BoardReturnCenter.Return
    let onOpenBoard: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            OwlView(pose: .wave, size: .peek)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back")
                    .appText(.headline)
                    .foregroundStyle(AppColors.text)
                Text(info.rank.map { "You're back on the leaderboard at #\($0)." }
                     ?? "You're back on the leaderboard. Log a shift to climb.")
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.lightTap()
                    onOpenBoard()
                } label: {
                    Text("See leaderboard")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(AppColors.accent.opacity(0.15)))
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(PremiumPressStyle())
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.md)
        .homeCard()
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.faint)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .padding(6)
        }
        .onAppear { Haptics.success() }
    }
}
