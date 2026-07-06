import WidgetKit
import SwiftUI

@main
struct HoursTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        HoursTrackerWidget()
        HoursTrackerLockScreenWidget()
    }
}
