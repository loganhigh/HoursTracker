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
//     natural default. "Clock In" lives as a toggle at the top
//     of the wizard's first screen instead of an up-front chooser; picking
//     it starts the live shift right here, and this same sheet transitions
//     into the tracking view without closing and reopening, because it
//     observes `LiveShiftManager.activeShift`.

struct AddShiftEntryView: View {
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var liveShift: LiveShiftManager
    /// Day to pre-select in the manual wizard (e.g. a suggested missing shift).
    var initialDate: Date? = nil

    /// Once the live screen is up it stays up for the life of this sheet —
    /// clocking out clears `activeShift`, and the earnings card that follows
    /// belongs to the live screen, not the wizard.
    @State private var showingLive = false

    var body: some View {
        Group {
            if showingLive || liveShift.activeShift != nil {
                LiveShiftTrackingView(store: store)
            } else {
                AddShiftWizardView(store: store, initialDate: initialDate)
            }
        }
        .onAppear { if liveShift.activeShift != nil { showingLive = true } }
        .onChange(of: liveShift.activeShift != nil) { _, active in
            if active { showingLive = true }
        }
    }
}
