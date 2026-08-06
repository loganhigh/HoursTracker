import SwiftUI
import Combine

// MARK: - Friends feature preference

/// Local, device-only switch for the Friends / social experience.
///
/// This is a *display* preference: it hides the Friends tab, the Home friends
/// card and the global Top 5 board, and it stops the friend listeners on this
/// device. It never deletes friendships and never writes privacy fields — the
/// server keeps publishing the user's stats exactly as before.
///
/// The stored value is absent for fresh installs *and* for everyone upgrading
/// from a build that predates this setting, so absence must read as ON. Nothing
/// ever writes `false` implicitly: only the Settings toggle writes this key.
enum FriendsFeature {
    static let storageKey = "friends_enabled"

    /// Non-SwiftUI read for call sites that aren't views.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }
}

// MARK: - Tabs

/// The root destinations of the app. Replaces the old side-drawer navigation
/// (SideMenu) with a native tab bar. `.settings` is a pseudo-tab: selecting it
/// never switches screens — it presents the Settings sheet instead.
enum AppTab: Hashable {
    case home
    case history
    case settings
    case friends
    case you
}

/// Shared tab selection so any screen (e.g. the Home friends card) can switch
/// tabs programmatically. Injected as an environment object by `AppTabView`.
final class TabRouter: ObservableObject {
    @Published var selection: AppTab = .home
}

// MARK: - App tab view

/// Root tab structure: Home · History · Settings · Friends · You.
/// Each real tab owns its own `NavigationStack` so pushes stay scoped per tab.
/// The middle gear item is intercepted: choosing it keeps the current tab
/// selected and presents `SettingsView` as a sheet. Shifts are still added from
/// the Home screen's primary "Add Shift" button.
///
/// Friends is conditional on `FriendsFeature`: with the toggle off the bar is
/// Home · History · Settings · You.
struct AppTabView: View {
    @EnvironmentObject private var store: HoursStore
    @EnvironmentObject private var authService: AuthService
    @StateObject private var tabRouter = TabRouter()
    @State private var showingSettings = false
    @AppStorage(FriendsFeature.storageKey) private var friendsEnabled = true

    /// Intercepting selection binding: the gear item opens the Settings sheet
    /// instead of becoming the selected tab, and a request for a tab that isn't
    /// currently in the bar falls back to Home.
    private var selection: Binding<AppTab> {
        Binding(
            get: { tabRouter.selection },
            set: { newValue in
                switch newValue {
                case .settings:
                    Haptics.lightTap()
                    showingSettings = true
                case .friends where !friendsEnabled:
                    tabRouter.selection = .home
                default:
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
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)

            if friendsEnabled {
                NavigationStack {
                    FriendsView(store: store)
                }
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
                .tag(AppTab.friends)
            }

            NavigationStack {
                YouTabView(store: store)
            }
            .tabItem { Label("You", systemImage: "person.crop.circle") }
            .tag(AppTab.you)
        }
        .tint(AppColors.accent)
        .environmentObject(tabRouter)
        .onChange(of: friendsEnabled) { _, isEnabled in
            // Friends can be the selected tab at the moment it's switched off
            // (the toggle lives in a sheet that can be opened from anywhere).
            // Without this the bar would drop the tag it is selected on and
            // leave the app showing a blank destination.
            if !isEnabled && tabRouter.selection == .friends {
                tabRouter.selection = .home
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, settings: $store.paySettings)
                .environmentObject(authService)
        }
    }
}
