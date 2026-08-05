import SwiftUI
import Combine

// MARK: - Tabs

/// The five root destinations of the app. Replaces the old side-drawer
/// navigation (SideMenu) with a native tab bar.
enum AppTab: Hashable {
    case home
    case history
    case stats
    case friends
    case you
}

/// Shared tab selection so any screen (e.g. the Home friends card) can switch
/// tabs programmatically. Injected as an environment object by `AppTabView`.
final class TabRouter: ObservableObject {
    @Published var selection: AppTab = .home
}

// MARK: - App tab view

/// Root 5-tab structure: Home · History · Stats · Friends · You.
/// Each tab owns its own `NavigationStack` so pushes stay scoped per tab.
struct AppTabView: View {
    @EnvironmentObject private var store: HoursStore
    @StateObject private var tabRouter = TabRouter()

    var body: some View {
        TabView(selection: $tabRouter.selection) {
            NavigationStack {
                HoursHomeView()
                    .background(AppColors.bg.ignoresSafeArea())
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                HistoryTabView()
            }
            .tabItem { Label("History", systemImage: "calendar") }
            .tag(AppTab.history)

            NavigationStack {
                ReportingView(store: store)
            }
            .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
            .tag(AppTab.stats)

            NavigationStack {
                FriendsView(store: store)
            }
            .tabItem { Label("Friends", systemImage: "person.2.fill") }
            .tag(AppTab.friends)

            NavigationStack {
                YouTabView(store: store)
            }
            .tabItem { Label("You", systemImage: "person.crop.circle") }
            .tag(AppTab.you)
        }
        .tint(AppColors.accent)
        .environmentObject(tabRouter)
    }
}
