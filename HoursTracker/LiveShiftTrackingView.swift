import SwiftUI

// MARK: - Live Shift Tracking (clock in/out/break — free for everyone)
//
// Fills the Add Shift sheet (`AddShiftEntryView`) whenever a live shift is
// already running — reached either because Add Shift was opened mid-shift,
// or because the chooser's "Clock In" just started one. No longer a Home
// card (Home no longer offers clock-in at all); this view owns the timer
// and its two states:
//   - active: live elapsed timer + Take Break/Clock Out (or Resume/Clock Out
//     while on break)
//   - stale (>16h): a quiet inline warning row layered above the timer
//
// Clocking out materializes the shift into a WorkEntry (via `store.add`,
// the same path the entry editor uses) and dismisses the sheet back to
// Home. Discarding drops the shift in place — the sheet then falls back to
// the Add Shift chooser, since `AddShiftEntryView` re-renders once
// `LiveShiftManager.activeShift` goes nil.
//
// No new glow here — the hero card on Home owns this screen's one glow. The
// owl perches on the timer card: coffee while working, asleep on break.

struct LiveShiftTrackingView: View {
    @ObservedObject var store: HoursStore
    /// Clock out at this time on appear (End button, "Clock out" push).
    var clockOutAt: Date? = nil
    @EnvironmentObject private var liveShift: LiveShiftManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingDiscardConfirm = false
    @State private var clockOutMessage: String?
    /// Set after clocking out; swaps this screen for the earnings card.
    @State private var earnings: ShiftEarnings?
    @State private var savedForPrompt: [WorkEntry] = []
    @State private var showWagePrompt = false

    private static let startedTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    @State private var handledClockOut = false
    @State private var showingStartEditor = false
    @State private var editedStart = Date()
    @State private var showingLocationPicker = false
    @State private var editedPlace = ShiftPlace()

    var body: some View {
        Group {
            if let earnings {
                ShiftEarningsView(store: store, earnings: earnings) { dismiss() }
                    .transition(.opacity)
            } else {
                trackingBody
            }
        }
        .sheet(isPresented: $showingStartEditor) { startEditor }
        .sheet(isPresented: $showingLocationPicker, onDismiss: { liveShift.setPlace(editedPlace) }) {
            SavedLocationPickerSheet(place: $editedPlace, locations: store.shiftLocationSummaries())
        }
        .onAppear {
            guard let clockOutAt, !handledClockOut, liveShift.activeShift != nil else { return }
            handledClockOut = true
            performClockOut(at: clockOutAt)
        }
    }

    private var trackingBody: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)

            Spacer(minLength: AppSpacing.md)

            if let shift = liveShift.activeShift {
                let owl = OwlLines.liveShift(isOnBreak: shift.isOnBreak, isStale: shift.isStale)
                activeCard(shift)
                    .owlPeek(owl.pose, size: .companion, alignment: .center)
                    .padding(.top, OwlView.Size.companion.height - OwlPerchMetrics.feetOverlap / 2)
                    .padding(.horizontal, AppSpacing.lg)
            }

            Spacer(minLength: AppSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.bg.ignoresSafeArea())
        .alert("Discard this shift?", isPresented: $showingDiscardConfirm) {
            Button("Discard", role: .destructive) {
                liveShift.discard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clocked-in time won't be saved.")
        }
        .sheet(isPresented: $showWagePrompt, onDismiss: afterWagePrompt) {
            WagePromptSheet(store: store)
        }
    }

    private var header: some View {
        AddShiftSheetHeader(title: "Live Shift") { dismiss() }
    }

    // MARK: Active

    private func activeCard(_ shift: LiveShift) -> some View {
        VStack(spacing: AppSpacing.md) {
            if shift.isStale {
                staleRow
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                VStack(spacing: AppSpacing.xs) {
                    Text(Self.formatElapsed(shift.elapsedWorked(at: now)))
                        .font(AppTypography.heroNumber)
                        .monospacedDigit()
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    if shift.isOnBreak {
                        Text("On break · \(shift.totalBreakMinutes(at: now))m")
                            .appText(.caption)
                            .foregroundStyle(AppColors.warning)
                    } else {
                        // Tap to move the start (got there early, started late).
                        Button {
                            Haptics.lightTap()
                            editedStart = shift.startDate
                            showingStartEditor = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Started \(Self.startedTimeFormatter.string(from: shift.startDate))")
                                Image(systemName: "pencil")
                                    .font(.caption2.weight(.bold))
                            }
                            .appText(.caption)
                            .foregroundStyle(AppColors.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Change when the shift started")
                    }
                }
            }

            if store.hasMultipleJobs {
                JobPickerMenu(store: store, selection: store.job(id: shift.jobID).id) { liveShift.setJob($0) }
            }

            Button {
                Haptics.lightTap()
                editedPlace = shift.place
                showingLocationPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(shift.place.displayText ?? "Add location")
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .opacity(0.6)
                }
                .appText(.subheadline)
                .foregroundStyle(shift.place.isEmpty ? AppColors.subtext : AppColors.text)
            }
            .buttonStyle(.plain)

            if let clockOutMessage {
                Text(clockOutMessage)
                    .appText(.caption)
                    .foregroundStyle(AppColors.negative)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                if shift.isOnBreak {
                    Button("Resume") {
                        Haptics.lightTap()
                        liveShift.endBreak()
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Clock Out") { performClockOut() }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Take Break") {
                        Haptics.lightTap()
                        liveShift.startBreak()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Clock Out") { performClockOut() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(AppColors.card2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .stroke(AppColors.stroke, lineWidth: 1)
        )
    }

    private var staleRow: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.warning)

            Text("Still clocked in since yesterday?")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            Button("Clock out now") {
                performClockOut()
            }
            .font(AppTypography.caption.weight(.bold))
            .foregroundStyle(AppColors.accent)

            Button("Discard") {
                Haptics.lightTap()
                showingDiscardConfirm = true
            }
            .font(AppTypography.caption.weight(.bold))
            .foregroundStyle(AppColors.negative)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(AppColors.warning.opacity(0.10))
        )
    }

    // MARK: Start time editor

    /// Earliest allowed start: 24 hours back. Latest: now, or the first
    /// break if one has been taken.
    private var startRange: ClosedRange<Date> {
        let now = Date()
        let ahead = now.addingTimeInterval(LiveShiftManager.maxFutureStartSeconds)
        let latest = liveShift.activeShift?.breaks.first?.start ?? ahead
        return now.addingTimeInterval(-24 * 3600)...min(latest, ahead)
    }

    private var startEditor: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.md) {
                Text("When did this shift start?")
                    .appText(.headline)
                    .foregroundStyle(AppColors.text)
                DatePicker("Start", selection: $editedStart, in: startRange,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                Spacer(minLength: 0)
            }
            .padding(AppSpacing.lg)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Start time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingStartEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if liveShift.setStartDate(editedStart) { Haptics.success() } else { Haptics.error() }
                        showingStartEditor = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Actions

    private func performClockOut(at date: Date = Date()) {
        guard let entry = liveShift.clockOut(at: min(date, Date()), into: store) else {
            Haptics.error()
            let worked = liveShift.activeShift?.elapsedWorked(at: Date()) ?? 0
            clockOutMessage = worked > 24 * 3600
                ? "This shift is over 24 hours, so it can't be saved. Discard it and log the hours by hand."
                : "Shift too short to save yet — keep going, or discard it."
            return
        }
        Haptics.success()
        clockOutMessage = nil
        // Same landing as a manual save: the earnings card, or the wage
        // prompt first when no wage is set yet.
        if let result = store.shiftEarnings(for: [entry]) {
            withAnimation(.easeInOut(duration: 0.35)) { earnings = result }
        } else if !store.paySettings.hourlyRateSet, WagePromptSheet.shouldOffer() {
            savedForPrompt = [entry]
            showWagePrompt = true
        } else {
            dismiss()
        }
    }

    private func afterWagePrompt() {
        if let result = store.shiftEarnings(for: savedForPrompt) {
            withAnimation(.easeInOut(duration: 0.35)) { earnings = result }
        } else {
            dismiss()
        }
    }

    // MARK: Formatting

    private static func formatElapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }
}
