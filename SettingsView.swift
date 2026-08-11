import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @ObservedObject var store: HoursStore
    @Binding var settings: PaySettings
    /// When set (panel mode), Done calls this instead of dismiss.
    var onClose: (() -> Void)? = nil

    @State private var showingDeleteConfirm = false
    @State private var showingPaydayPicker = false
    @State private var showingCutoffPicker = false
    @State private var showingNotificationsSheet = false
    @State private var showingDataExportSheet = false
    @State private var showingRestoreBackupConfirm = false
    @State private var showBackupSavedAlert = false
    @State private var showRestoreSuccessAlert = false
    @State private var backupErrorMessage: String?
    @State private var showingPremiumSheet = false
    @AppStorage("auto_yearly_reset_enabled") private var autoYearlyResetEnabled = true
    /// Master switch for the Friends/social experience on this device. Absence
    /// of the stored value reads as `true`, so fresh installs and upgrading
    /// users both get Friends without any migration write.
    @AppStorage(FriendsFeature.storageKey) private var friendsEnabled = true

    @ObservedObject private var smartNotifier = SmartNotifier.shared
    @ObservedObject private var weeklyNotifier = WeeklyMilestoneNotifier.shared
    @ObservedObject private var premium = PremiumManager.shared

    private var paydayDate: Date {
        let span = PayCycleEngine.spanDays(for: settings.payPeriodType)
        return settings.nextPayday ?? Calendar.current.date(byAdding: .day, value: span, to: Date()) ?? Date()
    }

    private var cutoffPickerDate: Date {
        settings.nextCutoff ?? paydayDate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bg.ignoresSafeArea()
                Form {
                // MARK: - Payday
                Section {
                    Picker("Pay period", selection: Binding(
                        get: { settings.payPeriodType },
                        set: { newType in
                            settings.payPeriodType = newType
                            store.persist()
                        }
                    )) {
                        ForEach(PayPeriodType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, AppSpacing.xxs)

                    Button {
                        showingPaydayPicker = true
                    } label: {
                        SettingsValueRow(
                            icon: "calendar",
                            title: "Next payday",
                            value: paydayDate.formatted(date: .abbreviated, time: .omitted)
                        )
                    }

                    Toggle(isOn: Binding(
                        get: { settings.payPeriodUsesCutoff },
                        set: { enabled in
                            settings.payPeriodUsesCutoff = enabled
                            if !enabled {
                                settings.nextCutoff = nil
                            }
                            store.persist()
                        }
                    )) {
                        SettingsRowLabel(icon: "clock.badge.checkmark", title: "Hours cutoff")
                    }
                    .tint(AppColors.accent)

                    if settings.payPeriodUsesCutoff {
                        Button {
                            showingCutoffPicker = true
                        } label: {
                            SettingsValueRow(
                                icon: "calendar.badge.checkmark",
                                title: "Cutoff date",
                                value: settings.nextCutoff?.formatted(date: .abbreviated, time: .omitted)
                                    ?? "Select date"
                            )
                        }
                    }
                } header: {
                    SectionEyebrow("Pay Cycle")
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)

                // MARK: - Overtime Rules
                Section {
                    // Type picker
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

                    // Daily threshold
                    if settings.overtimeType == .daily {
                        HStack(spacing: AppSpacing.sm) {
                            SettingsRowLabel(icon: "sun.max.fill", title: "Daily OT after")
                            Spacer(minLength: AppSpacing.xs)
                            OTHoursStepper(
                                value: Binding(
                                    get: { settings.weekdayOvertimeAfterHours },
                                    set: { settings.weekdayOvertimeAfterHours = $0; store.persist() }
                                ),
                                range: 1...24,
                                step: 0.5
                            )
                        }
                    }

                    // Weekly threshold
                    if settings.overtimeType == .weekly {
                        HStack(spacing: AppSpacing.sm) {
                            SettingsRowLabel(icon: "calendar.badge.clock", title: "Weekly OT after")
                            Spacer(minLength: AppSpacing.xs)
                            OTHoursStepper(
                                value: Binding(
                                    get: { settings.weeklyOvertimeThreshold },
                                    set: { settings.weeklyOvertimeThreshold = $0; store.persist() }
                                ),
                                range: 1...168,
                                step: 1
                            )
                        }
                    }

                    // OT pay multiplier
                    HStack(spacing: AppSpacing.sm) {
                        SettingsRowLabel(icon: "multiply.circle.fill", title: "OT rate")
                        Spacer(minLength: AppSpacing.xs)
                        OTHoursStepper(
                            value: Binding(
                                get: { settings.weekdayOvertimeMultiplier },
                                set: { settings.weekdayOvertimeMultiplier = $0; store.persist() }
                            ),
                            range: 1.0...4.0,
                            step: 0.25,
                            format: "×%.2g"
                        )
                    }

                } header: {
                    SectionEyebrow("Overtime Rules")
                } footer: {
                    Text(settings.overtimeType.description)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)

                // MARK: - Friends
                Section {
                    Toggle(isOn: $friendsEnabled) {
                        SettingsRowLabel(icon: "person.2.fill", title: "Friends")
                    }
                    .tint(AppColors.accent)

                    if friendsEnabled {
                        NavigationLink {
                            FriendsPrivacySettingsView(store: store)
                        } label: {
                            SettingsRowLabel(icon: "hand.raised.fill", title: "Friends privacy")
                        }
                    }
                } header: {
                    SectionEyebrow("Friends")
                } footer: {
                    Text(friendsEnabled
                         ? "Friends only see what you share. Toggle anything off to hide it instantly."
                         : "Hides the Friends tab and social features on this device. Your friends and privacy settings are kept, and your stats stay on the leaderboards.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)

                // Teams section removed 2026-08: crew create/join is paused
                // until the Teams tier ships. CrewService and the sheets are
                // intact — restore the section to re-enable.

                // MARK: - Job Sites
                Section {
                    NavigationLink {
                        JobSitesSettingsView(store: store)
                    } label: {
                        SettingsRowLabel(
                            icon: "mappin.and.ellipse",
                            title: "Job Sites",
                            subtitle: store.jobSites.isEmpty
                                ? "Save the places you work"
                                : "\(store.jobSites.count) saved"
                        )
                    }

                    // Shift Templates removed from Settings for now — revisit
                    // later. ShiftTemplatesSettingsView and store.shiftTemplates
                    // are untouched; restore the row to re-enable.
                } header: {
                    SectionEyebrow("Job Sites")
                } footer: {
                    Text("Saved locations appear when you add a shift. Stored on this device.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)

                // Certificates removed from Settings for now — revisit later.

                // MARK: - Notifications
                Section {
                    Button {
                        showingNotificationsSheet = true
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            SettingsRowLabel(icon: "bell.fill", title: "Notifications")
                            Spacer(minLength: AppSpacing.xs)
                            SettingsChevron()
                        }
                    }
                } header: {
                    SectionEyebrow("Notifications")
                } footer: {
                    Text("Manage notification preferences")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)

                // MARK: - Hour Tracker Pro
                // The only Pro surface that shows regardless of entitlement, so
                // it is the one that has to be switched off explicitly. Every
                // other Pro affordance in Settings is an `if !premium.isPremium`
                // crown badge, which disappears on its own once the kill switch
                // pins the entitlement open.
                if MonetizationConfig.isProEnabled {
                    Section {
                        Button {
                            Haptics.lightTap()
                            showingPremiumSheet = true
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                SettingsRowLabel(
                                    icon: "crown.fill",
                                    title: "Hour Tracker Pro",
                                    subtitle: premium.isPremium
                                        ? (premium.activeSubscription?.settingsStatusLine ?? "Active")
                                        : "Live tracking, Dynamic Island, templates, reports"
                                )
                                Spacer(minLength: AppSpacing.xs)
                                SettingsChevron()
                            }
                        }
                    } header: {
                        SectionEyebrow("Hour Tracker Pro")
                    }
                    .listRowBackground(AppColors.card.opacity(0.55))
                    .listRowSeparatorTint(AppColors.stroke)
                }

                // MARK: - Data & Backup
                Section {
                    Button {
                        showingDataExportSheet = true
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            SettingsRowLabel(icon: "square.and.arrow.down", title: "Download My Data")
                            Spacer(minLength: AppSpacing.xs)
                            SettingsChevron()
                        }
                    }

                    // Professional Reports removed from Settings for now —
                    // revisit later. ProfessionalReportsSheet and the upgrade
                    // paywall it gated are untouched; restore the row to
                    // re-enable.
                } header: {
                    SectionEyebrow("Data & Backup")
                } footer: {
                    Text("Automatically archives previous years and starts fresh each new year. Export all records or a selected month/year anytime.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .padding(.bottom, AppSpacing.sm)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)

                // Backup & Restore section removed for now — revisit later.

                // MARK: - Privacy & Security
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            SettingsIconSquare(icon: "lock.shield.fill")

                            Text("Work entries and pay settings are stored on your device. If you sign in with Apple, optional cloud sync, friends, and social features use Firebase to store the data you choose to share. We do not sell your information.")
                                .appText(.metricLabel)
                                .foregroundStyle(AppColors.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        LegalLinksSection()
                    }
                    .padding(.vertical, AppSpacing.xxs)
                } header: {
                    SectionEyebrow("Privacy & Security")
                } footer: {
                    Text("Delete All Data removes local entries and settings on this device only. To permanently delete your account and synced cloud data, use Account → Delete account.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)

                if DeveloperConfig.isCEO(uid: authService.user?.uid) {
                    Section {
                        NavigationLink {
                            AdminPanelView()
                        } label: {
                            SettingsRowLabel(icon: "person.2.badge.gearshape", title: "Admin console")
                        }
                    }
                    .listRowBackground(AppColors.card.opacity(0.55))
                    .listRowSeparatorTint(AppColors.stroke)
                }

                Section {
                    Button(role: .destructive, action: {
                        showingDeleteConfirm = true
                    }) {
                        SettingsRowLabel(
                            icon: "trash",
                            title: "Delete All Data",
                            tint: AppColors.negative,
                            titleTint: AppColors.negative
                        )
                    }
                } header: {
                    SectionEyebrow("Local Data")
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.persist()
                        if let onClose { onClose() } else { dismiss() }
                    }
                }
            }
            }
            .onDisappear {
                store.persist()
            }
            .sheet(isPresented: $showingPaydayPicker) {
                AutoDismissDatePickerSheet(
                    date: Binding(
                        get: { paydayDate },
                        set: {
                            settings.nextPayday = $0
                            store.persist()
                        }
                    ),
                    title: "Next Payday",
                    onDismiss: { showingPaydayPicker = false }
                )
            }
            .sheet(isPresented: $showingCutoffPicker) {
                AutoDismissDatePickerSheet(
                    date: Binding(
                        get: { cutoffPickerDate },
                        set: {
                            settings.nextCutoff = $0
                            store.persist()
                        }
                    ),
                    title: "Cutoff Date",
                    onDismiss: { showingCutoffPicker = false }
                )
            }
            .sheet(isPresented: $showingNotificationsSheet) {
                NotificationsSheet(store: store, onDismiss: { showingNotificationsSheet = false })
            }
            .sheet(isPresented: $showingDataExportSheet) {
                DataExportSheet(store: store)
            }
            .sheet(isPresented: $showingPremiumSheet) {
                PremiumUpgradeView()
            }
            // Crew sheets and the join-crew deep-link consumption are paused
            // with the Teams section. A pending join code from a deep link is
            // ignored rather than presenting a sheet users can no longer reach.
            .alert("Delete All Data", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    store.deleteAllData()
                }
            } message: {
                Text("This permanently deletes all work entries and settings stored on this device. It does not delete your cloud account. For full account removal, go to Account → Delete account.")
            }
            .alert("Restore from backup?", isPresented: $showingRestoreBackupConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Restore", role: .destructive) {
                    do {
                        try store.restoreFromLocalBackup()
                        Haptics.success()
                        showRestoreSuccessAlert = true
                    } catch {
                        backupErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            } message: {
                Text("Missing entries from your backup will be added back. Nothing currently in the app will be removed or overwritten.")
            }
            .alert("Backup complete", isPresented: $showBackupSavedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your data is saved on this device. You can restore it anytime with Restore from last back-up.")
            }
            .alert("Restored", isPresented: $showRestoreSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your data was restored from the last backup.")
            }
            .alert("Error", isPresented: Binding(
                get: { backupErrorMessage != nil },
                set: { if !$0 { backupErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { backupErrorMessage = nil }
            } message: {
                Text(backupErrorMessage ?? "")
            }
            .onChange(of: autoYearlyResetEnabled) { _, isEnabled in
                if isEnabled {
                    store.applyYearlyResetIfNeeded()
                }
            }
        }
    }

    private func performLocalBackup() {
        do {
            try store.createLocalBackup()
            Haptics.success()
            showBackupSavedAlert = true
        } catch {
            backupErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
