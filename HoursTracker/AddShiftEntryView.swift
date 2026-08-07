import SwiftUI

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
        if liveShift.activeShift != nil {
            LiveShiftTrackingView(store: store)
        } else {
            AddShiftWizardView(store: store)
        }
    }
}
