import SwiftUI
import Combine

// MARK: - Tabs

/// The root destinations of the app. Replaces the old side-drawer navigation
/// (SideMenu) with a native tab bar. `.add` is a pseudo-tab: selecting it
/// never switches screens — it presents the add-shift editor instead.
enum AppTab: Hashable {
    case home
    case history
    case add
    case friends
    case you
}

/// Shared tab selection so any screen (e.g. the Home friends card) can switch
/// tabs programmatically. Injected as an environment object by `AppTabView`.
final class TabRouter: ObservableObject {
    @Published var selection: AppTab = .home
}

// MARK: - App tab view

/// Root tab structure: Home · History · + · Friends · You.
/// Each real tab owns its own `NavigationStack` so pushes stay scoped per tab.
/// The middle "+" item is intercepted: choosing it keeps the current tab
/// selected and presents the same `EntryEditorView` add sheet Home uses.
struct AppTabView: View {
    @EnvironmentObject private var store: HoursStore
    @StateObject private var tabRouter = TabRouter()
    @State private var showingAddShift = false

    /// Intercepting selection binding: the "+" item opens the add-shift sheet
    /// instead of becoming the selected tab.
    private var selection: Binding<AppTab> {
        Binding(
            get: { tabRouter.selection },
            set: { newValue in
                if newValue == .add {
                    Haptics.lightTap()
                    showingAddShift = true
                } else {
                    tabRouter.selection = newValue
                }
            }
        )
    }

    var body: some View {
        TabView(selection: selection) {
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

            // Never actually selected — the binding intercepts this tag.
            Color.clear
                .tabItem { Label("Add Shift", systemImage: "plus.circle.fill") }
                .tag(AppTab.add)

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
        .sheet(isPresented: $showingAddShift) {
            EntryEditorView(store: store, mode: .add)
        }
    }
}
