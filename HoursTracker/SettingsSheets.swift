import SwiftUI

// MARK: - Settings sub-sheets (Phase 10)
//
// Notifications, reminder-time picker, and data-export sheets presented from
// SettingsView. Same grouped-list language as the main form: quiet card rows,
// centered eyebrow headers, icon squares, accent-tinted toggles.

// MARK: - Notifications Sheet

struct NotificationsSheet: View {
    @ObservedObject var store: HoursStore
    let onDismiss: () -> Void

    @ObservedObject private var smartNotifier = SmartNotifier.shared
    @ObservedObject private var weeklyNotifier = WeeklyMilestoneNotifier.shared
    @State private var showingReminderTimePicker = false
    @State private var notificationDenied = false

    var body: some View {
        NavigationStack {
            Form {
                if notificationDenied {
                    Section {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                SettingsRowLabel(
                                    icon: "bell.slash.fill",
                                    title: "Notifications are off",
                                    tint: AppColors.warning
                                )
                                Spacer(minLength: AppSpacing.xs)
                                Text("Open Settings")
                                    .appText(.caption)
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    } footer: {
                        Text("Enable notifications in Settings to receive reminders and milestone alerts.")
                            .appText(.caption)
                            .foregroundStyle(AppColors.subtext)
                    }
                    .listRowBackground(AppColors.card.opacity(0.55))
                    .listRowSeparatorTint(AppColors.stroke)
                }
                Section {
                    Toggle(isOn: $weeklyNotifier.isEnabled) {
                        SettingsRowLabel(icon: "flag.checkered", title: "Weekly Milestones")
                    }
                    .tint(AppColors.accent)

                    Toggle(isOn: $smartNotifier.payProgressEnabled) {
                        SettingsRowLabel(icon: "hourglass", title: "Pay Period Progress")
                    }
                    .tint(AppColors.accent)

                    Toggle(isOn: $smartNotifier.dailyReminderEnabled) {
                        SettingsRowLabel(icon: "alarm.fill", title: "Daily Shift Reminder")
                    }
                    .tint(AppColors.accent)

                    Toggle(isOn: $smartNotifier.forgotHoursReminderEnabled) {
                        SettingsRowLabel(icon: "questionmark.circle.fill", title: "Did you work today?")
                    }
                    .tint(AppColors.accent)

                    Toggle(isOn: $smartNotifier.streakNotificationsEnabled) {
                        SettingsRowLabel(icon: "flame.fill", title: "Streak alerts")
                    }
                    .tint(AppColors.accent)

                    Toggle(isOn: $smartNotifier.motivationReminderEnabled) {
                        SettingsRowLabel(icon: "sparkles", title: "Daily motivation")
                    }
                    .tint(AppColors.accent)

                    Toggle(isOn: $smartNotifier.friendShiftNotificationsEnabled) {
                        SettingsRowLabel(icon: "person.2.wave.2.fill", title: "Friend shift alerts")
                    }
                    .tint(AppColors.accent)

                    Toggle(isOn: $smartNotifier.leaderboardAlertsEnabled) {
                        SettingsRowLabel(icon: "trophy.fill", title: "Leaderboard alerts")
                    }
                    .tint(AppColors.accent)

                    if smartNotifier.dailyReminderEnabled {
                        Button {
                            showingReminderTimePicker = true
                        } label: {
                            SettingsValueRow(
                                icon: "clock.fill",
                                title: "Reminder Time",
                                value: formatHour(smartNotifier.dailyReminderHour)
                            )
                        }
                    }
                } header: {
                    SectionEyebrow("Alerts")
                } footer: {
                    Text("Get notified about milestones, progress, daily reminders, motivation quotes, streak alerts, friend shifts (e.g. \"Jacob worked 13h today\"), when someone passes you on the global leaderboard, and \"Did you work today?\".")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .sheet(isPresented: $showingReminderTimePicker) {
                ReminderTimePickerSheet(
                    hour: $smartNotifier.dailyReminderHour,
                    onDismiss: { showingReminderTimePicker = false }
                )
            }
            .onAppear {
                let entries = store.entries
                let streak = store.gamificationProfile.currentStreak
                Task {
                    let granted = await SmartNotifier.shared.requestPermissionsIfNeeded()
                    if granted {
                        SmartNotifier.shared.scheduleDailyReminder()
                        SmartNotifier.shared.scheduleForgotHoursReminderIfNeeded(entries: entries)
                        SmartNotifier.shared.scheduleMotivationReminderIfNeeded(entries: entries)
                        SmartNotifier.shared.scheduleStreakNotificationsIfNeeded(entries: entries, currentStreak: streak)
                        // Re-schedule anniversary if company data exists
                        let companyName = UserDefaults.standard.string(forKey: "company_name") ?? ""
                        let startTS = UserDefaults.standard.double(forKey: "company_start_date_ts")
                        if granted && !companyName.isEmpty && startTS > 0 {
                            let startDate = Date(timeIntervalSince1970: startTS)
                            SmartNotifier.shared.scheduleWorkAnniversaryNotification(companyName: companyName, startDate: startDate)
                        }
                    }
                    let status = await NotificationManager.shared.authorizationStatus()
                    await MainActor.run {
                        notificationDenied = (status == .denied)
                    }
                }
            }
            .onChange(of: smartNotifier.motivationReminderEnabled) { _, isEnabled in
                if isEnabled {
                    smartNotifier.scheduleMotivationReminderIfNeeded(entries: store.entries)
                } else {
                    smartNotifier.cancelMotivationReminders()
                }
            }
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        if let date = calendar.date(from: components) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }
}

// MARK: - Reminder Time Picker Sheet

struct ReminderTimePickerSheet: View {
    @Binding var hour: Int
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Hour", selection: $hour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(formatPickerHour(h)).tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                } header: {
                    SectionEyebrow("Daily Reminder Time")
                } footer: {
                    Text("You'll be reminded to log your shift if you haven't already.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Reminder Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }

    private func formatPickerHour(_ hour: Int) -> String {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        if let date = calendar.date(from: components) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }
}

// MARK: - Data Export Sheet

struct SettingsExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct DataExportSheet: View {
    @ObservedObject var store: HoursStore
    @Environment(\.dismiss) private var dismiss

    @State private var scope: DataExportScope = .all
    @State private var selectedDate = Date()
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var shareItem: SettingsExportShareItem?

    private let exportService = DataExportService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Range", selection: $scope) {
                        ForEach(DataExportScope.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, AppSpacing.xxs)

                    if scope == .month {
                        Picker(selection: monthBinding) {
                            ForEach(1...12, id: \.self) { month in
                                Text(Self.monthFormatter.monthSymbols[month - 1]).tag(month)
                            }
                        } label: {
                            SettingsRowLabel(icon: "calendar", title: "Month")
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.accent)
                    } else if scope == .year {
                        Picker(selection: yearBinding) {
                            ForEach(availableYears, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        } label: {
                            SettingsRowLabel(icon: "calendar", title: "Year")
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.accent)
                    }
                } header: {
                    SectionEyebrow("Export Range")
                } footer: {
                    Text("All Data includes active records plus archived yearly history.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)

                Section {
                    Button {
                        exportCSV()
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            SettingsRowLabel(
                                icon: "doc.text",
                                title: isExporting ? "Preparing file..." : "Download CSV",
                                isBusy: isExporting
                            )
                            Spacer(minLength: AppSpacing.xs)
                            SettingsChevron()
                        }
                    }
                    .disabled(isExporting)

                    Button {
                        exportPDF()
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            SettingsRowLabel(
                                icon: "doc.richtext",
                                title: isExporting ? "Preparing file..." : "Download PDF",
                                isBusy: isExporting
                            )
                            Spacer(minLength: AppSpacing.xs)
                            SettingsChevron()
                        }
                    }
                    .disabled(isExporting)
                } header: {
                    SectionEyebrow("Format")
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Download Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url]) { shareItem = nil }
            }
            .alert("Export Failed", isPresented: .init(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "Export failed. Please try again.")
            }
        }
    }

    private func exportCSV() {
        isExporting = true
        do {
            let url = try exportService.exportCSV(scope: scope, selectedDate: selectedDate, store: store)
            isExporting = false
            shareItem = SettingsExportShareItem(url: url)
        } catch {
            isExporting = false
            exportError = (error as? LocalizedError)?.errorDescription ?? "Export failed. Please try again."
        }
    }

    private func exportPDF() {
        isExporting = true
        do {
            let url = try exportService.exportPDF(scope: scope, selectedDate: selectedDate, store: store)
            isExporting = false
            shareItem = SettingsExportShareItem(url: url)
        } catch {
            isExporting = false
            exportError = (error as? LocalizedError)?.errorDescription ?? "Export failed. Please try again."
        }
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.month, from: selectedDate) },
            set: { newMonth in
                let calendar = Calendar.current
                let year = calendar.component(.year, from: selectedDate)
                if let updated = calendar.date(from: DateComponents(year: year, month: newMonth, day: 1)) {
                    selectedDate = updated
                }
            }
        )
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.year, from: selectedDate) },
            set: { newYear in
                let calendar = Calendar.current
                let month = calendar.component(.month, from: selectedDate)
                if let updated = calendar.date(from: DateComponents(year: newYear, month: month, day: 1)) {
                    selectedDate = updated
                }
            }
        )
    }

    private var availableYears: [Int] {
        let calendar = Calendar.current
        let entryYears = store.allEntriesIncludingArchive().map { calendar.component(.year, from: $0.date) }
        let archiveYears = store.yearArchives.map(\.year)
        let currentYear = calendar.component(.year, from: Date())
        let selectedYear = calendar.component(.year, from: selectedDate)
        let combined = Set(entryYears + archiveYears + [currentYear, selectedYear])
        return combined.sorted()
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        return formatter
    }()
}
