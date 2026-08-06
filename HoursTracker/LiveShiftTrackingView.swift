import SwiftUI

// MARK: - Live Shift Tracking (Hour Tracker Pro — clock in/out/break)
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
// No new glow here — the hero card on Home owns this screen's one glow.

struct LiveShiftTrackingView: View {
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var liveShift: LiveShiftManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingDiscardConfirm = false
    @State private var clockOutMessage: String?

    private static let startedTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)

            Spacer(minLength: AppSpacing.md)

            if let shift = liveShift.activeShift {
                activeCard(shift)
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
    }

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                Haptics.lightTap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.subtext)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(AppColors.card)
                            .overlay(Circle().stroke(AppColors.stroke, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Text("Live Shift")
                .appText(.title)
                .foregroundStyle(AppColors.text)

            Spacer()
        }
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
                        Text("Started \(Self.startedTimeFormatter.string(from: shift.startDate))")
                            .appText(.caption)
                            .foregroundStyle(AppColors.subtext)
                    }
                }
            }

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
                .font(.system(size: 13, weight: .bold))
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
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AppColors.accent)

            Button("Discard") {
                Haptics.lightTap()
                showingDiscardConfirm = true
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AppColors.negative)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(AppColors.warning.opacity(0.10))
        )
    }

    // MARK: Actions

    private func performClockOut() {
        guard let entry = liveShift.clockOut(at: Date(), into: store) else {
            Haptics.error()
            clockOutMessage = "Shift too short to save yet — keep going, or discard it."
            return
        }
        _ = entry
        Haptics.success()
        clockOutMessage = nil
        dismiss()
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
