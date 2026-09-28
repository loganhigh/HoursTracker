import SwiftUI
import Combine

// MARK: - Add Shift entry point (Hour Tracker Pro — router)
//
// The single way a shift gets into the log, live-tracked or manual. Home's
// "Add Shift" button (and every other add-shift affordance) presents this
// instead of jumping straight to the wizard:
//
//   - An already-running live shift takes over immediately — this sheet
//     shows the timer/break/clock-out interface (`LiveShiftTrackingView`).
//   - Otherwise the manual wizard opens directly — manual entry is the
//     natural default. "Clock In" (Pro-gated) lives as a toggle at the top
//     of the wizard's first screen instead of an up-front chooser; picking
//     it starts the live shift right here, and this same sheet transitions
//     into the tracking view without closing and reopening, because it
//     observes `LiveShiftManager.activeShift`.

struct AddShiftEntryView: View {
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var liveShift: LiveShiftManager

    var body: some View {
        Group {
            if liveShift.activeShift != nil {
                LiveShiftTrackingView(store: store)
            } else {
                AddShiftWizardView(store: store)
            }
        }
        .onAppear { AddFlowPresence.shared.isActive = true }
        .onDisappear { AddFlowPresence.shared.isActive = false }
    }
}

/// Whether the add-shift flow is on screen. Celebrations that are presented
/// as sheets from the screen underneath (badge unlocks) must wait for it:
/// presenting one while this full-screen cover is up makes iOS dismiss the
/// cover — which threw away the shift earnings card mid-view.
@MainActor
final class AddFlowPresence: ObservableObject {
    static let shared = AddFlowPresence()
    @Published var isActive = false
    private init() {}
}
