import SwiftUI

// MARK: - Start sheet (from a tapped "You're at work" push)

/// Starts a live shift with a chosen start time: now, the moment they got
/// there, or any time in the last 12 hours (arrived early, start at 7).
struct LiveShiftStartSheet: View {
    let prompt: ArrivalPrompt
    @ObservedObject var store: HoursStore
    @Environment(\.dismiss) private var dismiss

    private enum StartChoice: Hashable { case now, arrived, custom }

    @State private var choice: StartChoice = .now
    @State private var customTime = Date()
    @State private var place = ShiftPlace()
    @State private var showingLocationPicker = false

    private var arrivedDiffers: Bool { Date().timeIntervalSince(prompt.arrivedAt) >= 60 }

    private var startDate: Date {
        switch choice {
        case .now: return Date()
        case .arrived: return prompt.arrivedAt
        case .custom: return min(customTime, Date())
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    VStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(AppColors.accent)
                        Text(place.isEmpty ? "Start your shift" : "You're at \(place.trimmedName)")
                            .appText(.title)
                            .foregroundStyle(AppColors.text)
                            .multilineTextAlignment(.center)
                        Text("When did your shift start?")
                            .appText(.subheadline)
                            .foregroundStyle(AppColors.subtext)
                    }
                    .padding(.top, AppSpacing.sm)

                    AddShiftPanel {
                        option(.now, title: "Now", detail: Date().formatted(date: .omitted, time: .shortened))
                        if arrivedDiffers {
                            EntryRowDivider()
                            option(.arrived, title: "When I arrived",
                                   detail: prompt.arrivedAt.formatted(date: .omitted, time: .shortened))
                        }
                        EntryRowDivider()
                        option(.custom, title: "Pick a time",
                               detail: choice == .custom ? nil : "e.g. your scheduled start")
                        if choice == .custom {
                            DatePicker("Start time", selection: $customTime,
                                       in: Date().addingTimeInterval(-12 * 3600)...Date(),
                                       displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                        }
                    }

                    AddShiftPanel {
                        AddShiftFieldRow(
                            icon: "mappin.and.ellipse",
                            label: "Location",
                            value: place.displayText ?? "Select location",
                            isPlaceholder: place.isEmpty,
                            accessory: .chevron
                        ) {
                            Haptics.lightTap()
                            showingLocationPicker = true
                        }
                    }

                    Text("You can change the start time and location while the shift runs.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.faint)
                        .multilineTextAlignment(.center)

                    Button {
                        Haptics.success()
                        LiveShiftManager.shared.clockIn(at: startDate, place: place)
                        dismiss()
                    } label: {
                        Label("Start live shift", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xl)
            }
            .background(AppColors.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .onAppear {
            if let site = ArrivalMonitor.shared.site(id: prompt.siteID) { place = site.place }
            customTime = prompt.arrivedAt
            if arrivedDiffers { choice = .arrived }
        }
        .sheet(isPresented: $showingLocationPicker) {
            SavedLocationPickerSheet(place: $place, locations: store.shiftLocationSummaries())
        }
    }

    private func option(_ value: StartChoice, title: String, detail: String?) -> some View {
        let selected = choice == value
        return Button {
            Haptics.lightTap()
            withAnimation(AppMotion.Spring.snappy) { choice = value }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                    if let detail {
                        Text(detail)
                            .appText(.caption)
                            .foregroundStyle(AppColors.subtext)
                    }
                }
                Spacer(minLength: AppSpacing.xs)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AppColors.accent : AppColors.faint)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Live shift bar (every tab, while clocked in)

/// Pinned above the tab bar while a live shift runs: the running time,
/// where, and an End button. Tapping the bar opens the full live screen
/// (breaks, start time, location).
struct LiveShiftBar: View {
    @EnvironmentObject private var liveShift: LiveShiftManager
    var onOpen: () -> Void
    var onEnd: () -> Void

    @State private var confirmingEnd = false

    var body: some View {
        if let shift = liveShift.activeShift {
            HStack(spacing: AppSpacing.sm) {
                Button(action: onOpen) {
                    HStack(spacing: AppSpacing.sm) {
                        Circle()
                            .fill(shift.isOnBreak ? AppColors.gold : AppColors.positive)
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 1) {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(Self.elapsed(shift.elapsedWorked(at: context.date)))
                                    .font(.system(.headline, design: .rounded, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(AppColors.text)
                            }
                            Text(subtitle(shift))
                                .appText(.caption)
                                .foregroundStyle(AppColors.subtext)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Live shift running. Open live shift")

                Button {
                    Haptics.lightTap()
                    confirmingEnd = true
                } label: {
                    Text("End")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(AppColors.textOnAccent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(AppColors.accentGradient))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End live shift")
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColors.card)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppColors.stroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            )
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, AppSpacing.xs)
            .confirmationDialog("End your live shift now?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("End shift") { onEnd() }
                Button("Cancel", role: .cancel) {}
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func subtitle(_ shift: LiveShift) -> String {
        var parts: [String] = [shift.isOnBreak ? "On break" : "On shift"]
        if let name = shift.locationName, !name.isEmpty { parts.append(name) }
        parts.append("since \(shift.startDate.formatted(date: .omitted, time: .shortened))")
        return parts.joined(separator: " · ")
    }

    private static func elapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
