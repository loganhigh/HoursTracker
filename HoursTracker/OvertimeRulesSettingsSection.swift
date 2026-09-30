import SwiftUI

/// Settings → Overtime Rules. Daily or weekly overtime, the work-week
/// threshold (36 / 40 / 44 / custom), the OT rate, optional double time,
/// the weekend premiums switch and the stat holiday's paid hours.
struct OvertimeRulesSettingsSection: View {
    @ObservedObject var store: HoursStore
    @Binding var settings: PaySettings

    /// Stays on "Custom" after picking it even while the stepper sits on a
    /// preset value, so the stepper doesn't vanish mid-edit.
    @State private var customWorkWeek = false

    private static let workWeekPresets: [Double] = [36, 40, 44]

    private var workWeekSelection: Double {
        if customWorkWeek { return 0 }
        return Self.workWeekPresets.contains(settings.weeklyOvertimeThreshold) ? settings.weeklyOvertimeThreshold : 0
    }

    private var doubleTimeOn: Bool { settings.doubleTimeAfterHours != nil }

    private var doubleTimeDefault: Double {
        settings.overtimeType == .weekly ? settings.weeklyOvertimeThreshold + 8 : 12
    }

    var body: some View {
        Section {
            Picker("Overtime type", selection: Binding(
                get: { settings.overtimeType },
                set: { settings.overtimeType = $0; store.persist() }
            )) {
                ForEach(OvertimeType.settingsCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, AppSpacing.xxs)

            if settings.overtimeType == .daily {
                stepperRow(icon: "sun.max.fill", title: "Daily OT after",
                           value: $settings.weekdayOvertimeAfterHours, range: 1...24, step: 0.5)
            } else {
                workWeekRows
            }

            stepperRow(icon: "multiply.circle.fill", title: "OT rate",
                       value: $settings.weekdayOvertimeMultiplier, range: 1.0...4.0, step: 0.25, format: "×%.2g")

            Toggle(isOn: Binding(
                get: { doubleTimeOn },
                set: { on in
                    Haptics.lightTap()
                    settings.doubleTimeAfterHours = on ? doubleTimeDefault : nil
                    store.persist()
                }
            )) {
                SettingsRowLabel(icon: "2.circle.fill", title: "Double time")
            }
            .tint(AppColors.accent)

            if doubleTimeOn {
                stepperRow(
                    icon: "clock.badge.fill",
                    title: "Double time after",
                    value: Binding(
                        get: { settings.doubleTimeAfterHours ?? doubleTimeDefault },
                        set: { settings.doubleTimeAfterHours = $0 }
                    ),
                    range: settings.overtimeType == .weekly ? 1...168 : 1...24,
                    step: settings.overtimeType == .weekly ? 1 : 0.5
                )
            }

            Toggle(isOn: Binding(
                get: { settings.weekendPremiumsEnabled },
                set: { Haptics.lightTap(); settings.weekendPremiumsEnabled = $0; store.persist() }
            )) {
                SettingsRowLabel(icon: "calendar.badge.exclamationmark", title: "Weekend premiums")
            }
            .tint(AppColors.accent)
        } header: {
            SectionEyebrow("Overtime Rules")
        } footer: {
            Text(footer)
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
        }
        .listRowBackground(AppColors.card.opacity(0.55))
        .listRowSeparatorTint(AppColors.stroke)

        Section {
            Toggle(isOn: Binding(
                get: { settings.statHolidayOptionsEnabled },
                set: { Haptics.lightTap(); settings.statHolidayOptionsEnabled = $0; store.persist() }
            )) {
                SettingsRowLabel(icon: "star.circle.fill", title: "Stat holiday pay")
            }
            .tint(AppColors.accent)
            if settings.statHolidayOptionsEnabled {
                stepperRow(icon: "clock.fill", title: "Stat pay hours",
                           value: $settings.statHolidayPaidHours, range: 0...24, step: 0.5)
            }
        } header: {
            SectionEyebrow("Stat Holidays")
        } footer: {
            Text(settings.statHolidayOptionsEnabled
                 ? "Adds a Stat holiday switch to work shifts: a day off with stat pay, or worked at regular time, time and a half, double time, or double time plus the stat pay. Stat pay is paid at your regular rate for the hours set here."
                 : "Off: shifts are just hours — no stat holiday options in the editor.")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
        }
        .listRowBackground(AppColors.card.opacity(0.55))
        .listRowSeparatorTint(AppColors.stroke)
    }

    @ViewBuilder
    private var workWeekRows: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            SettingsRowLabel(icon: "calendar.badge.clock", title: "Work week")
            Picker("Work week", selection: Binding(
                get: { workWeekSelection },
                set: { choice in
                    Haptics.lightTap()
                    if choice == 0 {
                        customWorkWeek = true
                    } else {
                        customWorkWeek = false
                        settings.weeklyOvertimeThreshold = choice
                        store.persist()
                    }
                }
            )) {
                ForEach(Self.workWeekPresets, id: \.self) { hours in
                    Text("\(Int(hours))h").tag(hours)
                }
                Text("Custom").tag(0.0)
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, AppSpacing.xxs)

        if workWeekSelection == 0 {
            stepperRow(icon: "slider.horizontal.3", title: "Overtime after",
                       value: $settings.weeklyOvertimeThreshold, range: 1...168, step: 1)
        }
    }

    private func stepperRow(icon: String, title: String, value: Binding<Double>,
                            range: ClosedRange<Double>, step: Double, format: String? = nil) -> some View {
        HStack(spacing: AppSpacing.sm) {
            SettingsRowLabel(icon: icon, title: title)
            Spacer(minLength: AppSpacing.xs)
            OTHoursStepper(
                value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; store.persist() }),
                range: range,
                step: step,
                format: format
            )
        }
    }

    private var footer: String {
        var parts: [String] = []
        switch settings.overtimeType {
        case .daily:
            parts.append("Overtime after \(hours(settings.weekdayOvertimeAfterHours)) in a shift")
            if let dt = settings.doubleTimeAfterHours { parts.append("double time after \(hours(dt))") }
        case .weekly, .dailyAndWeekly:
            let start = PayCycleEngine.weekdayName(settings.weekStartWeekday ?? 2)
            parts.append("Overtime once the week (from \(start)) passes \(hours(settings.weeklyOvertimeThreshold))")
            if let dt = settings.doubleTimeAfterHours { parts.append("double time after \(hours(dt))") }
        }
        var text = parts.joined(separator: ", ") + "."
        text += settings.weekendPremiumsEnabled
            ? " Weekend premiums: Saturday's first \(hours(settings.saturdayOvertimeAfterHours)) regular then ×\(mult(settings.saturdayMultiplier)); all of Sunday ×\(mult(settings.sundayMultiplier))."
            : " Saturday and Sunday count like any other day."
        return text
    }

    private func hours(_ h: Double) -> String { HolidayPayRule.hoursText(h) }
    private func mult(_ m: Double) -> String { HolidayPayRule.multText(m) }
}
