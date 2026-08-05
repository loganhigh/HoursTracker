import SwiftUI

// MARK: - You tab

/// You tab root. `AccountView` is the primary body — identity hero with the
/// XP capsule, lifetime stats grid, the navigation card (Career, Badges,
/// Settings, Website, Contact), the account card (cloud sync / sign out /
/// delete), and the version footer. This wrapper exists so the tab has a
/// stable, named root while AccountView keeps working anywhere it is pushed
/// or presented.
struct YouTabView: View {
    @ObservedObject var store: HoursStore

    var body: some View {
        AccountView(store: store)
    }
}
