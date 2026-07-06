import SwiftUI
import PhotosUI

// MARK: - Account view

struct AccountView: View {
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @AppStorage("profile_display_name") private var storedDisplayName: String = ""

    @State private var showingFriends = false
    @State private var showingDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isUpdatingPhoto = false
    @ObservedObject private var photoManager = ProfilePhotoManager.shared

    private var earnedBadgeCount: Int {
        AchievementsView.earnedBadgeCount(for: store)
    }

    private var displayName: String {
        let trimmed = storedDisplayName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        let fbName = authService.user?.displayName?.trimmingCharacters(in: .whitespaces)
        if let fbName, !fbName.isEmpty { return fbName }
        return "Guest"
    }

    private var displayInitials: String {
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        let joined = parts.joined().uppercased()
        return joined.isEmpty ? "U" : joined
    }

    private var levelLabel: String {
        let level = store.displayedLevel
        let prestige = store.gamificationProfile.prestige
        if prestige > 0 { return "Lv \(level) • P\(prestige)" }
        return "Level \(level)"
    }

    private var memberSinceString: String {
        guard let first = store.entries.map(\.date).min() else { return "Just now" }
        let df = DateFormatter()
        df.dateFormat = "MMM yyyy"
        return df.string(from: first)
    }

    private var cloudStatusLabel: String {
        authService.isSignedIn ? "Synced" : "Local"
    }

    private var currentYearString: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    private var currentYearHours: Double {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        return store.entries
            .filter { !$0.isOffDay && cal.component(.year, from: $0.date) == year }
            .reduce(0) { $0 + $1.paidHours }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    heroProfileCard

                    SectionCard(
                        title: "Profile",
                        subtitle: "Career progress and milestones",
                        trailing: nil,
                        centerHeader: true
                    ) {
                        VStack(spacing: 10) {
                            NavigationLink(destination: CareerView(store: store)) {
                                profileActionRow(
                                    icon: "chart.line.uptrend.xyaxis",
                                    title: "Career",
                                    subtitle: "View lifetime hours and career stats"
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: AchievementsView(store: store)) {
                                profileActionRow(
                                    icon: "rosette",
                                    title: "Badges",
                                    subtitle: "\(earnedBadgeCount) badges earned"
                                )
                            }
                            .buttonStyle(.plain)

                        }
                        .padding(.vertical, 8)
                    }

                    SectionCard(
                        title: "Account stats",
                        subtitle: "Your profile at a glance",
                        trailing: nil,
                        centerHeader: true
                    ) {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            AccountStatTile(
                                label: "Badges",
                                value: "\(earnedBadgeCount)",
                                icon: "rosette"
                            )
                            AccountStatTile(
                                label: "Level",
                                value: "\(store.displayedLevel)",
                                icon: "star.fill"
                            )
                            AccountStatTile(
                                label: "Member Since",
                                value: memberSinceString,
                                icon: "calendar"
                            )
                            AccountStatTile(
                                label: "\(currentYearString) Hours",
                                value: AppTheme.Format.hours(currentYearHours),
                                icon: "clock.fill"
                            )
                        }
                        .padding(.vertical, 8)
                    }

                    SectionCard(
                        title: nil,
                        subtitle: authService.isSignedIn
                            ? "Signed in with Apple"
                            : "Sign in to sync across devices",
                        trailing: nil,
                        centerHeader: true
                    ) {
                        cloudSyncBody
                    }

                    SectionCard(
                        title: "Friends",
                        subtitle: "Connect with coworkers",
                        trailing: nil,
                        centerHeader: true
                    ) {
                        Button {
                            guard authService.isSignedIn else { return }
                            showingFriends = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.Colors.accent.opacity(0.18))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(AppTheme.Colors.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Manage friends")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppTheme.Colors.text)
                                    Text(authService.isSignedIn
                                        ? "Add friends with your code"
                                        : "Sign in to add friends")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppTheme.Colors.subtext)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(AppTheme.Colors.subtext)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppTheme.Colors.card2)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!authService.isSignedIn)
                        .opacity(authService.isSignedIn ? 1 : 0.55)
                    }

                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingFriends) {
                FriendsView(store: store)
                    .environmentObject(authService)
            }
            .onAppear {
                Task {
                    await photoManager.uploadLocalPhotoIfNeeded()
                    if authService.isSignedIn {
                        store.syncProfileSnapshotToCloud()
                    }
                }
            }
        }
    }

    // MARK: - Hero

    private var heroProfileCard: some View {
        let currentUserUid = authService.user?.uid

        return VStack(spacing: 10) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatarView(
                        name: displayName,
                        size: 84,
                        uid: currentUserUid,
                        showsAccentRing: true
                    )
                    .shadow(color: AppTheme.Colors.accent.opacity(0.35), radius: 12, y: 6)

                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.card)
                            .frame(width: 28, height: 28)
                        if isUpdatingPhoto {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.accent)
                        }
                    }
                    .overlay(Circle().stroke(AppTheme.Colors.bg, lineWidth: 2))
                    .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)
            .disabled(!authService.isSignedIn || isUpdatingPhoto)
            .onChange(of: photoPickerItem) { _, item in
                guard let item else { return }
                Task { await updateProfilePhoto(from: item) }
            }
            .padding(.bottom, 2)

            if authService.isSignedIn {
                Text("Tap photo to update")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.faint)
            }

            Text(displayName)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)

            if let userEmail = authService.user?.email, !userEmail.isEmpty {
                Text(userEmail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
            } else {
                Text(authService.isSignedIn ? "No email on file" : "Not signed in")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }

            HStack(spacing: 6) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(levelLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppTheme.Colors.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(AppTheme.Colors.accent.opacity(0.15))
            )
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func profileActionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.text)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.Colors.subtext)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.card2)
        )
    }

    // MARK: - Cloud sync body

    @ViewBuilder
    private var cloudSyncBody: some View {
        if authService.isSignedIn {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected to iCloud")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.text)
                    Text("Your data is backed up automatically")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
                Spacer()
                Button(role: .destructive) {
                    try? authService.signOut()
                } label: {
                    Text("Sign Out")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(AppTheme.Colors.danger.opacity(0.18))
                        )
                        .foregroundStyle(AppTheme.Colors.danger)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.Colors.card2)
            )

            // Account deletion — required by App Store Review Guideline 5.1.1(v)
            deleteAccountRow

            LegalLinksSection()
                .padding(.top, 4)
        } else {
            VStack(spacing: 12) {
                Text("Sign in to sync your hours across devices and add friends.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                AuthSignInOptionsView()
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var deleteAccountRow: some View {
        Button(role: .destructive) {
            Haptics.warning()
            showingDeleteAccountConfirm = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.danger.opacity(0.18))
                        .frame(width: 40, height: 40)
                    if isDeletingAccount {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppTheme.Colors.danger)
                    } else {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDeletingAccount ? "Deleting account…" : "Delete account")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.text)
                    Text("Permanently removes your account and synced data")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .lineLimit(2)
                }
                Spacer()
                if !isDeletingAccount {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.Colors.card2)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDeletingAccount)
        .alert("Delete account?", isPresented: $showingDeleteAccountConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await performAccountDeletion() }
            }
        } message: {
            Text("This permanently removes your Hour Tracker account, all synced hours, friends, and badges. This cannot be undone.")
        }
        .alert("Couldn't delete account", isPresented: Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
    }

    private func performAccountDeletion() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await AccountDeletionService.deleteAccount(store: store)
            Haptics.success()
        } catch {
            Haptics.error()
            deleteAccountError = error.localizedDescription
        }
    }

    private func updateProfilePhoto(from item: PhotosPickerItem) async {
        guard authService.isSignedIn else { return }
        isUpdatingPhoto = true
        defer {
            isUpdatingPhoto = false
            photoPickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            try await photoManager.setPhoto(image)
            store.syncProfileSnapshotToCloud()
            Haptics.success()
        } catch {
            Haptics.error()
            deleteAccountError = error.localizedDescription
        }
    }

    // MARK: - Save

    private func saveChanges() {
        // Profile-details fields were removed; nothing to persist when the user
        // taps Done. Kept as a hook so future settings can plug in.
        store.save()
    }
}

// MARK: - Account stat tile

private struct AccountStatTile: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.accent)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                )
        )
    }
}
