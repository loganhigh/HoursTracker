import SwiftUI

// MARK: - You tab

/// You tab root. `AccountView` is the primary body — it already carries the
/// profile hero, Career/Badges links, cloud sync, and (since the tab
/// restructure) the App section with Settings, Website, Contact, and the
/// version footer. This wrapper exists so the tab has a stable, named root
/// while AccountView keeps working anywhere it is pushed or presented.
struct YouTabView: View {
    @ObservedObject var store: HoursStore

    var body: some View {
        AccountView(store: store)
    }
}
