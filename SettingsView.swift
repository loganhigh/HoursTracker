import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @ObservedObject var store: HoursStore
    @Binding var settings: PaySettings
    /// When set (panel mode), Done calls this instead of dismiss.
    var onClose: (() -> Void)? = nil

    @State private var showingDeleteConfirm = false
    @State private var showingNotificationsSheet = false
    @State private var showingDataExportSheet = false
    @State private var showingYearEndSummary = false
    @State private var showingRestoreBackupConfirm = false
    @State private var showBackupSavedAlert = false
    @State private var showRestoreSuccessAlert = false
    @State private var backupErrorMessage: String?
    @AppStorage("auto_yearly_reset_enabled") private var autoYearlyResetEnabled = true
    /// Master switch for the Friends/social experience on this device. Absence
    /// of the stored value reads as `true`, so fresh installs and upgrading
    /// users both get Friends without any migration write.
    @AppStorage(FriendsFeature.storageKey) private var friendsEnabled = true
    @AppStorage(CrewFeatures.enabledKey) private var crewTextBoss = false

    @ObservedObject private var smartNotifier = SmartNotifier.shared
    @ObservedObject private var weeklyNotifier = WeeklyMilestoneNotifier.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bg.ignoresSafeArea()
                Form {
                // MARK: - Jobs
                // Every job (main included) with its company details, wage,
                // pay cycle and overtime in one editor, the same one each
                // job's card opens on the You page.
                JobsListSection(store: store)

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

                // Job Sites removed 2026-10: shifts take a map pin instead
                // (ShiftLocationPicker), with recent spots from past shifts.
                // Shift Templates also stay out of Settings for now;
                // ShiftTemplatesSettingsView is intact.

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
                    NavigationLink {
                        ArrivalAlertsView(store: store)
                    } label: {
                        SettingsRowLabel(
                            icon: "location.circle.fill",
                            title: "Arrive at Work",
                            subtitle: "Start your live shift when you get there"
                        )
                    }
                    if crewTextBoss {
                        NavigationLink {
                            CrewTextBossSettingsView()
                        } label: {
                            SettingsRowLabel(
                                icon: "message.fill",
                                title: "Text your boss",
                                subtitle: "After you log today's shift"
                            )
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

                    Button {
                        showingYearEndSummary = true
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            SettingsRowLabel(
                                icon: "doc.text.magnifyingglass",
                                title: "Year-End Summary",
                                subtitle: "Hours, overtime and gross pay for tax time"
                            )
                            Spacer(minLength: AppSpacing.xs)
                            SettingsChevron()
                        }
                    }
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
                    // Assurance banner: one calm line instead of the old
                    // paragraph — the footer keeps the fine print.
                    HStack(spacing: AppSpacing.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [AppColors.accent.opacity(0.28), AppColors.accent.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 40, height: 40)
                            Image(systemName: "lock.shield.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppColors.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your data stays yours")
                                .appText(.headline)
                                .foregroundStyle(AppColors.text)
                            Text("Entries live on this device. Only what you choose to share is synced — never sold.")
                                .appText(.caption)
                                .foregroundStyle(AppColors.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, AppSpacing.xxs)

                    Button {
                        Haptics.lightTap()
                        UIApplication.shared.open(AppLegalURLs.privacyPolicy)
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            SettingsRowLabel(icon: "hand.raised.fill", title: "Privacy Policy")
                            Spacer(minLength: AppSpacing.xs)
                            SettingsChevron()
                        }
                    }

                    Button {
                        Haptics.lightTap()
                        UIApplication.shared.open(AppLegalURLs.termsOfUse)
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            SettingsRowLabel(icon: "doc.text.fill", title: "Terms of Use")
                            Spacer(minLength: AppSpacing.xs)
                            SettingsChevron()
                        }
                    }
                } header: {
                    SectionEyebrow("Privacy & Security")
                } footer: {
                    Text("Delete All Data removes local entries and settings on this device only. To permanently delete your account and synced cloud data, use Account → Delete account.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)

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
            .sheet(isPresented: $showingNotificationsSheet) {
                NotificationsSheet(store: store, onDismiss: { showingNotificationsSheet = false })
            }
            .sheet(isPresented: $showingDataExportSheet) {
                DataExportSheet(store: store)
            }
            .sheet(isPresented: $showingYearEndSummary) {
                YearEndSummarySheet(store: store)
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
