import SwiftUI
import PhotosUI
import VisionKit

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
    @AppStorage("auto_yearly_reset_enabled") private var autoYearlyResetEnabled = true
    
    @ObservedObject private var smartNotifier = SmartNotifier.shared
    @ObservedObject private var weeklyNotifier = WeeklyMilestoneNotifier.shared

    private var paydayDate: Date {
        let span = PayCycleEngine.spanDays(for: settings.payPeriodType)
        return settings.nextPayday ?? Calendar.current.date(byAdding: .day, value: span, to: Date()) ?? Date()
    }

    private var cutoffPickerDate: Date {
        settings.nextCutoff ?? paydayDate
    }

    /// Centered small-caps section header — same language as the Home sections.
    private func settingsHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(AppTheme.Colors.subtext)
            .frame(maxWidth: .infinity, alignment: .center)
            .textCase(nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.bg.ignoresSafeArea()
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
                    .padding(.vertical, 4)

                    Button {
                        showingPaydayPicker = true
                    } label: {
                        HStack {
                            Text("Next payday")
                                .foregroundStyle(AppTheme.Colors.text)
                            Spacer()
                            Text(paydayDate.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(AppTheme.Colors.accent)
                        }
                    }

                    Toggle("Hours cutoff", isOn: Binding(
                        get: { settings.payPeriodUsesCutoff },
                        set: { enabled in
                            settings.payPeriodUsesCutoff = enabled
                            if !enabled {
                                settings.nextCutoff = nil
                            }
                            store.persist()
                        }
                    ))

                    if settings.payPeriodUsesCutoff {
                        Button {
                            showingCutoffPicker = true
                        } label: {
                            HStack {
                                Text("Cutoff date")
                                    .foregroundStyle(AppTheme.Colors.text)
                                Spacer()
                                Text(
                                    settings.nextCutoff?.formatted(date: .abbreviated, time: .omitted)
                                        ?? "Select date"
                                )
                                .foregroundStyle(AppTheme.Colors.accent)
                            }
                        }
                    }
                } header: {
                    settingsHeader("Pay Cycle")
                }
                .listRowBackground(AppTheme.Colors.card.opacity(0.55))

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
                    .padding(.vertical, 4)

                    // Daily threshold
                    if settings.overtimeType == .daily {
                        HStack {
                            Image(systemName: "sun.max.fill")
                                .foregroundStyle(AppTheme.Colors.accent)
                            Text("Daily OT after")
                                .foregroundStyle(AppTheme.Colors.text)
                            Spacer()
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
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(AppTheme.Colors.accent)
                            Text("Weekly OT after")
                                .foregroundStyle(AppTheme.Colors.text)
                            Spacer()
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
                    HStack {
                        Image(systemName: "multiply.circle.fill")
                            .foregroundStyle(AppTheme.Colors.accent)
                        Text("OT rate")
                            .foregroundStyle(AppTheme.Colors.text)
                        Spacer()
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
                    settingsHeader("Overtime Rules")
                } footer: {
                    Text(settings.overtimeType.description)
                }
                .listRowBackground(AppTheme.Colors.card.opacity(0.55))

                // MARK: - Friends Privacy
                Section {
                    NavigationLink {
                        FriendsPrivacySettingsView(store: store)
                    } label: {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(AppTheme.Colors.accent)
                            Text("Friends privacy")
                                .foregroundStyle(AppTheme.Colors.text)
                            Spacer()
                        }
                    }
                } header: {
                    settingsHeader("Friends")
                } footer: {
                    Text("Friends only see what you share. Toggle anything off to hide it instantly.")
                }
                .listRowBackground(AppTheme.Colors.card.opacity(0.55))

                // Certificates removed from Settings for now — revisit later.

                // MARK: - Notifications
                Section {
                    Button {
                        showingNotificationsSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(AppTheme.Colors.accent)
                            Text("Notifications")
                                .foregroundStyle(AppTheme.Colors.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .systemGray3))
                        }
                    }
                } header: {
                    settingsHeader("Notifications")
                } footer: {
                    Text("Manage notification preferences")
                }
                .listRowBackground(AppTheme.Colors.card.opacity(0.55))

                // MARK: - Data & Backup
                Section {
                    Button {
                        showingDataExportSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundStyle(AppTheme.Colors.accent)
                            Text("Download My Data")
                                .foregroundStyle(Color(uiColor: .label))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .systemGray3))
                        }
                    }
                } header: {
                    settingsHeader("Data & Backup")
                } footer: {
                    Text("Automatically archives previous years and starts fresh each new year. Export all records or a selected month/year anytime.")
                        .padding(.bottom, 12)
                }
                .listRowBackground(AppTheme.Colors.card.opacity(0.55))

                // Backup & Restore section removed for now — revisit later.

                // MARK: - Privacy & Security
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(AppTheme.Colors.accent)
                                .font(.title3)
                                .padding(.top, 2)

                            Text("Work entries and pay settings are stored on your device. If you sign in with Apple, optional cloud sync, friends, and social features use Firebase to store the data you choose to share. We do not sell your information.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        LegalLinksSection()
                    }
                    .padding(.vertical, 4)
                } header: {
                    settingsHeader("Privacy & Security")
                } footer: {
                    Text("Delete All Data removes local entries and settings on this device only. To permanently delete your account and synced cloud data, use Account → Delete account.")
                }
                .listRowBackground(AppTheme.Colors.card.opacity(0.55))

                if DeveloperConfig.isCEO(uid: authService.user?.uid) {
                    Section {
                        NavigationLink {
                            AdminPanelView()
                        } label: {
                            HStack {
                                Image(systemName: "person.2.badge.gearshape")
                                    .foregroundStyle(AppTheme.Colors.accent)
                                Text("Admin console")
                                    .foregroundStyle(AppTheme.Colors.text)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.Colors.card.opacity(0.55))
                }

                Section {
                    Button(role: .destructive, action: {
                        showingDeleteConfirm = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete All Data")
                            Spacer()
                        }
                    }
                } header: {
                    settingsHeader("Local Data")
                }
                .listRowBackground(AppTheme.Colors.card.opacity(0.55))
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Colors.bg, for: .navigationBar)
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

// MARK: - Friends Privacy (Settings)

private struct FriendsPrivacySettingsView: View {
    @ObservedObject var store: HoursStore
    @ObservedObject private var socialPrivacy = SocialPrivacyStore.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: shareHoursBinding) {
                    privacyRowLabel(
                        icon: "clock.fill",
                        title: "Show hours to friends",
                        subtitle: "Weekly + total hours on the leaderboard"
                    )
                }
                NavigationLink {
                    CountryFlagPickerView(store: store)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Country flag")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.text)
                            Text("Shown beside your name on Top 5 Hour Trackers")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(AppTheme.Colors.subtext)
                        }
                        Spacer(minLength: 8)
                        if let flag = CountryFlag.emoji(for: CountryFlag.resolvedCode) {
                            Text(flag)
                                .font(.system(size: 20))
                        }
                    }
                }
                Toggle(isOn: shareBadgesBinding) {
                    privacyRowLabel(
                        icon: "rosette",
                        title: "Show badges to friends",
                        subtitle: "Badge count + equipped title"
                    )
                }
                Toggle(isOn: shareActivityBinding) {
                    privacyRowLabel(
                        icon: "sparkles",
                        title: "Post to activity feed",
                        subtitle: "Shifts, badges, milestones + friend alerts"
                    )
                }
                Toggle(isOn: acceptInvitesBinding) {
                    privacyRowLabel(
                        icon: "person.crop.circle.badge.plus",
                        title: "Accept friend invites",
                        subtitle: "Allow others to send you requests"
                    )
                }
            } footer: {
                Text("Friends only see what you share. Your country flag appears on the public Top 5 board when hours sharing is on.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Friends privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var shareHoursBinding: Binding<Bool> {
        Binding(
            get: { socialPrivacy.flags.shareHours },
            set: { newValue in
                Haptics.lightTap()
                socialPrivacy.update { $0.shareHours = newValue }
                store.syncProfileSnapshotToCloud()
            }
        )
    }

    private var shareBadgesBinding: Binding<Bool> {
        Binding(
            get: { socialPrivacy.flags.shareBadges },
            set: { newValue in
                Haptics.lightTap()
                socialPrivacy.update { $0.shareBadges = newValue }
                store.syncProfileSnapshotToCloud()
            }
        )
    }

    private var shareActivityBinding: Binding<Bool> {
        Binding(
            get: { socialPrivacy.flags.shareActivity },
            set: { newValue in
                Haptics.lightTap()
                socialPrivacy.update { $0.shareActivity = newValue }
                store.syncProfileSnapshotToCloud()
            }
        )
    }

    private var acceptInvitesBinding: Binding<Bool> {
        Binding(
            get: { socialPrivacy.flags.acceptInvites },
            set: { newValue in
                Haptics.lightTap()
                socialPrivacy.update { $0.acceptInvites = newValue }
                store.syncProfileSnapshotToCloud()
            }
        )
    }

    @ViewBuilder
    private func privacyRowLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.text)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
        }
    }
}

// MARK: - Certificates (Settings)

private struct CertificatesSettingsView: View {
    @ObservedObject var store: HoursStore
    @State private var selectedCertificateItem: PhotosPickerItem?
    @State private var showingCertificatePhotoPicker = false
    @State private var showingCertificateScanner = false
    @State private var showingCertificateAddOptions = false
    @State private var showingCertificateScannerUnavailable = false
    @State private var showingCertificateFullScreen: CertificateEntry?
    @State private var editingCertificateLabel: CertificateEntry?

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                SectionCard(
                    title: nil,
                    subtitle: "Training Certificates",
                    trailing: nil,
                    centerHeader: true
                ) {
                    VStack(spacing: 12) {
                        if store.certificateEntries.isEmpty {
                            Text("No certificates yet. Add your first one below.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.subtext)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 20)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(store.certificateEntries) { entry in
                                        SettingsCertificateThumbnail(store: store, entry: entry)
                                            .onTapGesture { showingCertificateFullScreen = entry }
                                            .contextMenu {
                                                Button {
                                                    editingCertificateLabel = entry
                                                } label: {
                                                    Label("Edit label", systemImage: "pencil")
                                                }
                                                Button(role: .destructive) {
                                                    store.deleteCertificate(entry: entry)
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(height: 108)
                        }

                        Button {
                            showingCertificateAddOptions = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 18))
                                Text("Add Certificates")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(AppTheme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(InteractiveButtonStyle())
                        .confirmationDialog("Add Certificate", isPresented: $showingCertificateAddOptions, titleVisibility: .visible) {
                            Button("Upload Photo") {
                                showingCertificatePhotoPicker = true
                            }
                            Button("Scan Document") {
                                if VNDocumentCameraViewController.isSupported {
                                    showingCertificateScanner = true
                                } else {
                                    showingCertificateScannerUnavailable = true
                                }
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("Choose how you want to add your certificate.")
                        }
                        .photosPicker(
                            isPresented: $showingCertificatePhotoPicker,
                            selection: $selectedCertificateItem,
                            matching: .images
                        )
                        .onChange(of: selectedCertificateItem) { _, newItem in
                            guard let newItem else { return }
                            Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self) {
                                    await MainActor.run {
                                        store.addCertificate(imageData: data)
                                        if let added = store.certificateEntries.last {
                                            editingCertificateLabel = added
                                        }
                                        Haptics.success()
                                        selectedCertificateItem = nil
                                    }
                                }
                            }
                        }
                        .sheet(isPresented: $showingCertificateScanner) {
                            DocumentScannerSheet { scannedImages in
                                for image in scannedImages {
                                    guard let data = image.jpegData(compressionQuality: 0.92) else { continue }
                                    store.addCertificate(imageData: data)
                                }
                                if let added = store.certificateEntries.last {
                                    editingCertificateLabel = added
                                }
                                Haptics.success()
                                showingCertificateScanner = false
                            } onCancel: {
                                showingCertificateScanner = false
                            }
                        }
                        .alert("Scanner Unavailable", isPresented: $showingCertificateScannerUnavailable) {
                            Button("OK", role: .cancel) { }
                        } message: {
                            Text("Document scanning is available on a real iPhone/iPad with camera support, not in the simulator.")
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Certificates")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $showingCertificateFullScreen) { entry in
            SettingsCertificateFullScreenView(store: store, entry: entry) {
                showingCertificateFullScreen = nil
            }
        }
        .sheet(item: $editingCertificateLabel) { entry in
            SettingsCertificateLabelSheet(store: store, entry: entry) {
                editingCertificateLabel = nil
            }
        }
    }
}

private struct SettingsCertificateThumbnail: View {
    @ObservedObject var store: HoursStore
    let entry: CertificateEntry

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let url = store.certificateFileURL(for: entry.filename),
                   let data = try? Data(contentsOf: url),
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.Colors.stroke, lineWidth: 1)
            )

            Text(entry.label.isEmpty ? "Certificate" : entry.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
    }
}

private struct SettingsCertificateFullScreenView: View {
    @ObservedObject var store: HoursStore
    let entry: CertificateEntry
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppTheme.Colors.bg.ignoresSafeArea()

            if let url = store.certificateFileURL(for: entry.filename),
               let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                VStack(spacing: 12) {
                    if !entry.label.isEmpty {
                        Text(entry.label)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.text)
                            .padding(.horizontal, 20)
                    }

                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.Colors.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(AppTheme.Colors.stroke.opacity(0.5), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)
                        )
                        .padding(16)
                }
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(20)
        }
        .onTapGesture { onDismiss() }
    }
}

private struct SettingsCertificateLabelSheet: View {
    @ObservedObject var store: HoursStore
    let entry: CertificateEntry
    let onDismiss: () -> Void
    @State private var label: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label, prompt: Text("e.g. Forklift cert, Safety 2024"))
                } footer: {
                    Text("Add a label to find this certificate easily.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("Certificate label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateCertificateLabel(
                            id: entry.id,
                            label: label.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        Haptics.success()
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { label = entry.label }
        }
    }
}

// MARK: - Awards (Settings)

private struct AwardsSettingsView: View {
    @ObservedObject var store: HoursStore
    @State private var selectedAwardItem: PhotosPickerItem?
    @State private var showingAwardPhotoPicker = false
    @State private var showingAwardScanner = false
    @State private var showingAwardAddOptions = false
    @State private var showingAwardScannerUnavailable = false
    @State private var showingAwardFullScreen: AwardEntry?
    @State private var editingAwardLabel: AwardEntry?

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                SectionCard(
                    title: nil,
                    subtitle: "Job Awards",
                    trailing: nil,
                    centerHeader: true
                ) {
                    VStack(spacing: 12) {
                        if store.awardEntries.isEmpty {
                            Text("No awards yet. Add your first one below.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.subtext)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 20)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(store.awardEntries) { entry in
                                        SettingsAwardThumbnail(store: store, entry: entry)
                                            .onTapGesture { showingAwardFullScreen = entry }
                                            .contextMenu {
                                                Button {
                                                    editingAwardLabel = entry
                                                } label: {
                                                    Label("Edit label", systemImage: "pencil")
                                                }
                                                Button(role: .destructive) {
                                                    store.deleteAward(entry: entry)
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(height: 108)
                        }

                        Button {
                            showingAwardAddOptions = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "rosette")
                                    .font(.system(size: 18))
                                Text("Add Awards")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(AppTheme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(InteractiveButtonStyle())
                        .confirmationDialog("Add Award", isPresented: $showingAwardAddOptions, titleVisibility: .visible) {
                            Button("Upload Photo") {
                                showingAwardPhotoPicker = true
                            }
                            Button("Scan Document") {
                                if VNDocumentCameraViewController.isSupported {
                                    showingAwardScanner = true
                                } else {
                                    showingAwardScannerUnavailable = true
                                }
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("Choose how you want to add your award.")
                        }
                        .photosPicker(
                            isPresented: $showingAwardPhotoPicker,
                            selection: $selectedAwardItem,
                            matching: .images
                        )
                        .onChange(of: selectedAwardItem) { _, newItem in
                            guard let newItem else { return }
                            Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self) {
                                    await MainActor.run {
                                        store.addAward(imageData: data)
                                        if let added = store.awardEntries.last {
                                            editingAwardLabel = added
                                        }
                                        Haptics.success()
                                        selectedAwardItem = nil
                                    }
                                }
                            }
                        }
                        .sheet(isPresented: $showingAwardScanner) {
                            DocumentScannerSheet { scannedImages in
                                for image in scannedImages {
                                    guard let data = image.jpegData(compressionQuality: 0.92) else { continue }
                                    store.addAward(imageData: data)
                                }
                                if let added = store.awardEntries.last {
                                    editingAwardLabel = added
                                }
                                Haptics.success()
                                showingAwardScanner = false
                            } onCancel: {
                                showingAwardScanner = false
                            }
                        }
                        .alert("Scanner Unavailable", isPresented: $showingAwardScannerUnavailable) {
                            Button("OK", role: .cancel) { }
                        } message: {
                            Text("Document scanning is available on a real iPhone/iPad with camera support, not in the simulator.")
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Awards")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $showingAwardFullScreen) { entry in
            SettingsAwardFullScreenView(store: store, entry: entry) {
                showingAwardFullScreen = nil
            }
        }
        .sheet(item: $editingAwardLabel) { entry in
            SettingsAwardLabelSheet(store: store, entry: entry) {
                editingAwardLabel = nil
            }
        }
    }
}

private struct SettingsAwardThumbnail: View {
    @ObservedObject var store: HoursStore
    let entry: AwardEntry

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let url = store.awardFileURL(for: entry.filename),
                   let data = try? Data(contentsOf: url),
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "rosette")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.Colors.stroke, lineWidth: 1)
            )

            Text(entry.label.isEmpty ? "Award" : entry.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
    }
}

private struct SettingsAwardFullScreenView: View {
    @ObservedObject var store: HoursStore
    let entry: AwardEntry
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppTheme.Colors.bg.ignoresSafeArea()

            if let url = store.awardFileURL(for: entry.filename),
               let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                VStack(spacing: 12) {
                    if !entry.label.isEmpty {
                        Text(entry.label)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.text)
                            .padding(.horizontal, 20)
                    }

                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.Colors.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(AppTheme.Colors.stroke.opacity(0.5), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)
                        )
                        .padding(16)
                }
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(20)
        }
        .onTapGesture { onDismiss() }
    }
}

private struct SettingsAwardLabelSheet: View {
    @ObservedObject var store: HoursStore
    let entry: AwardEntry
    let onDismiss: () -> Void
    @State private var label: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label, prompt: Text("e.g. Employee of the Month, Safety Star"))
                } footer: {
                    Text("Add a label to find this award easily.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("Award label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateAwardLabel(
                            id: entry.id,
                            label: label.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        Haptics.success()
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { label = entry.label }
        }
    }
}

private struct SettingsExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DataExportSheet: View {
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

                    if scope == .month {
                        Picker("Month", selection: monthBinding) {
                            ForEach(1...12, id: \.self) { month in
                                Text(Self.monthFormatter.monthSymbols[month - 1]).tag(month)
                            }
                        }
                        .pickerStyle(.menu)
                    } else if scope == .year {
                        Picker("Year", selection: yearBinding) {
                            ForEach(availableYears, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text("Export Range")
                } footer: {
                    Text("All Data includes active records plus archived yearly history.")
                }

                Section {
                    Button {
                        exportCSV()
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                            } else {
                                Image(systemName: "doc.text")
                            }
                            Text(isExporting ? "Preparing file..." : "Download CSV")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isExporting)

                    Button {
                        exportPDF()
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                            } else {
                                Image(systemName: "doc.richtext")
                            }
                            Text(isExporting ? "Preparing file..." : "Download PDF")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isExporting)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.bg.ignoresSafeArea())
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

private struct DocumentScannerSheet: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) { }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: ([UIImage]) -> Void
        private let onCancel: () -> Void

        init(onScan: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images: [UIImage] = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onScan(images)
        }
    }
}

// MARK: - Notifications Sheet

private struct NotificationsSheet: View {
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
                            HStack {
                                Text("Notifications are off")
                                    .foregroundStyle(Color(uiColor: .label))
                                Spacer()
                                Text("Open Settings")
                                    .foregroundStyle(AppTheme.Colors.accent)
                            }
                        }
                    } footer: {
                        Text("Enable notifications in Settings to receive reminders and milestone alerts.")
                    }
                }
                Section {
                    Toggle("Weekly Milestones", isOn: $weeklyNotifier.isEnabled)
                        .tint(AppTheme.Colors.accent)
                    
                    Toggle("Pay Period Progress", isOn: $smartNotifier.payProgressEnabled)
                        .tint(AppTheme.Colors.accent)
                    
                    Toggle("Daily Shift Reminder", isOn: $smartNotifier.dailyReminderEnabled)
                        .tint(AppTheme.Colors.accent)
                    
                    Toggle("Did you work today?", isOn: $smartNotifier.forgotHoursReminderEnabled)
                        .tint(AppTheme.Colors.accent)
                    
                    Toggle("Streak alerts", isOn: $smartNotifier.streakNotificationsEnabled)
                        .tint(AppTheme.Colors.accent)

                    Toggle("Daily motivation", isOn: $smartNotifier.motivationReminderEnabled)
                        .tint(AppTheme.Colors.accent)

                    Toggle("Friend shift alerts", isOn: $smartNotifier.friendShiftNotificationsEnabled)
                        .tint(AppTheme.Colors.accent)
                    
                    if smartNotifier.dailyReminderEnabled {
                        Button {
                            showingReminderTimePicker = true
                        } label: {
                            HStack {
                                Text("Reminder Time")
                                    .foregroundStyle(Color(uiColor: .label))
                                Spacer()
                                Text(formatHour(smartNotifier.dailyReminderHour))
                                    .foregroundStyle(Color(uiColor: .systemBlue))
                            }
                        }
                    }
                } footer: {
                    Text("Get notified about milestones, progress, daily reminders, motivation quotes, streak alerts, friend shifts (e.g. \"Jacob worked 13h today\") and \"Did you work today?\".")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.bg.ignoresSafeArea())
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

private struct ReminderTimePickerSheet: View {
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
                    Text("Daily reminder time")
                } footer: {
                    Text("You'll be reminded to log your shift if you haven't already.")
                }
            }
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

// MARK: - Goal Progress Card

private struct GoalProgressCard: View {
    let title: String
    let saved: Double
    let target: Double
    let currencyCode: String

    private var progress: Double { min(max(saved / target, 0), 1) }
    private var remaining: Double { max(target - saved, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: progress)
                .tint(.green)

            HStack {
                Text("Saved \(money(saved))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Left \(money(remaining))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

// MARK: - Currency Picker

/// Full-screen currency picker presented from the Settings row. Renders one
/// option per row with the symbol, ISO code, and localized name so the choice
/// is unambiguous, and shows a checkmark on the selected currency.
private struct CurrencyPickerView: View {
    @Binding var selection: String
    let options: [CurrencyOption]
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""

    private var filteredOptions: [CurrencyOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return options }
        let needle = trimmed.lowercased()
        return options.filter {
            $0.code.lowercased().contains(needle)
                || $0.displayName.lowercased().contains(needle)
        }
    }

    var body: some View {
        List {
            ForEach(filteredOptions) { option in
                Button {
                    selection = option.code
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Text(option.symbol)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.accent)
                            .frame(width: 36, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.code)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.text)
                            Text(option.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.subtext)
                        }
                        Spacer()
                        if option.code == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search currencies")
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - OT Hours Stepper

/// Compact stepper widget showing the current value with +/− buttons.
private struct OTHoursStepper: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    /// Nil = hours label ("8h" / "8.5h"). Pass "×%.2g" for multiplier display.
    var format: String? = nil

    private var formattedValue: String {
        if let fmt = format {
            return String(format: fmt, value)
        }
        let rounded = (value * 10).rounded() / 10
        let isWhole = rounded == rounded.rounded(.towardZero)
        return isWhole ? "\(Int(rounded))h" : "\(rounded)h"
    }

    var body: some View {
        HStack(spacing: 6) {
            stepButton(
                systemName: "minus",
                enabled: value > range.lowerBound + 0.0001
            ) {
                adjust(by: -step)
            }

            Text(formattedValue)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
                .monospacedDigit()
                .frame(minWidth: 52)
                .multilineTextAlignment(.center)
                .allowsHitTesting(false)

            stepButton(
                systemName: "plus",
                enabled: value < range.upperBound - 0.0001
            ) {
                adjust(by: step)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }

    private func stepButton(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? AppTheme.Colors.accent : AppTheme.Colors.subtext.opacity(0.35))
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(enabled ? AppTheme.Colors.accent.opacity(0.12) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func adjust(by delta: Double) {
        Haptics.lightTap()
        var next = value + delta
        next = min(range.upperBound, max(range.lowerBound, next))
        if step > 0 {
            next = (next / step).rounded() * step
            next = min(range.upperBound, max(range.lowerBound, next))
        }
        value = next
    }
}
