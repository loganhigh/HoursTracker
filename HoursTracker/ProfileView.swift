import SwiftUI

// MARK: - Profile View (Display Name + Badges)
struct ProfileView: View {
    @ObservedObject var store: HoursStore
    // `store.displayedLevel` prefers the server-computed level from
    // StatsListenerService — observe it so the label re-renders when the
    // server snapshot lands (HoursStore itself doesn't republish on it).
    @ObservedObject private var statsListener = StatsListenerService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Level \(store.displayedLevel) • Prestige \(store.gamificationProfile.prestige) • \"\(store.displayedEquippedTitle.isEmpty ? (store.gamificationProfile.equippedTitle ?? "Rookie Grinder") : store.displayedEquippedTitle)\"")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    AchievementsView(store: store, embedded: true)
                }
            }
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("My Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Same recovery hook as CareerView: guarantees the server-stats
            // listeners are attached whenever a level-displaying screen appears.
            .onAppear { StatsListenerService.shared.ensureListening() }
        }
    }
}
