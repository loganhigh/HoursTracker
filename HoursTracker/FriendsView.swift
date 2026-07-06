import SwiftUI

struct FriendsView: View {
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject private var friendsService = FriendsService.shared
    @State private var codeInput = ""
    @State private var actionMessage: String?
    @State private var actionMessageIsError = false
    @State private var copyConfirmation = false
    @State private var isSending = false
    @State private var sendTimeoutTask: Task<Void, Never>?
    @State private var profileFriendUid: String?

    private var myName: String {
        UserDefaults.standard.string(forKey: "profile_display_name") ?? "Worker"
    }

    var body: some View {
        NavigationStack {
            Group {
                if !authService.isSignedIn {
                    signedOutPlaceholder
                } else {
                    friendsContent
                }
            }
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let uid = authService.user?.uid {
                    friendsService.startListening(uid: uid)
                    Task { await friendsService.refreshFriendProfiles() }
                }
                store.syncProfileSnapshotToCloud()
            }
            .onChange(of: authService.user?.uid) { _, uid in
                if let uid {
                    friendsService.startListening(uid: uid)
                } else {
                    friendsService.stopListening()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, let uid = authService.user?.uid {
                    friendsService.startListening(uid: uid)
                    Task { await friendsService.refreshFriendProfiles() }
                }
            }
            .navigationDestination(item: $profileFriendUid) { uid in
                FriendProfileDetailView(
                    friendUid: uid,
                    friendsService: friendsService,
                    onRemoveFriend: { friend in
                        await removeFriend(friend)
                    }
                )
            }
        }
    }

    private var signedOutPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.Colors.subtext.opacity(0.5))
            Text("Sign in to use Friends")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
            Text("Sign in with Apple from Account to add friends and see their stats.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var friendsContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                friendCodeHeroCard
                    .padding(.horizontal, AppTheme.Spacing.md)

                notifyCaption
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppTheme.Spacing.md)

                if let actionMessage {
                    Text(actionMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(actionMessageIsError ? .red : AppTheme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .transition(.opacity)
                }

                // Surface listener/load errors that were previously silent —
                // without this, a permission or network error just looked
                // like "no friends" with no indication anything went wrong.
                if let serviceError = friendsService.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(serviceError)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.text)
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.12)))
                    .padding(.horizontal, AppTheme.Spacing.md)
                }


                if !friendsService.pendingRequests.isEmpty {
                    centeredSectionHeader(title: "Requests", subtitle: nil)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, 4)
                    ForEach(friendsService.pendingRequests) { request in
                        FriendRequestRow(request: request) {
                            Task { await accept(request) }
                        } onDecline: {
                            Task { await decline(request) }
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                    }
                }

                if !friendsService.friends.isEmpty {
                    centeredSectionHeader(title: "Friends", subtitle: "Tap a friend to view their profile")
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, 4)
                    ForEach(friendsService.friends) { friend in
                        FriendStatsRow(
                            friend: friend,
                            onOpenProfile: {
                                profileFriendUid = friend.uid
                            }
                        )
                        .padding(.horizontal, AppTheme.Spacing.md)
                    }
                } else if friendsService.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                } else {
                    emptyFriendsBubble
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 16)
        }
        .refreshable {
            store.syncProfileSnapshotToCloud()
            await friendsService.refreshFriendIds(surfaceErrors: true)
            await friendsService.refreshFriendProfiles()
            await friendsService.refreshPendingRequests(surfaceErrors: true)
        }
    }

    /// Hero card combining the user's shareable code (tap to copy) with the
    /// add-by-code field. Replaces the old plain code row + separate caption.
    private var friendCodeHeroCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("YOUR FRIEND CODE")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(AppTheme.Colors.subtext)

                Button {
                    copyCode()
                } label: {
                    HStack(spacing: 12) {
                        Text(friendsService.myFriendCode ?? "—")
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.text)
                            .monospacedDigit()
                        Image(systemName: copyConfirmation ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(copyConfirmation ? AppTheme.Colors.success : AppTheme.Colors.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(friendsService.myFriendCode == nil)

                Text(copyConfirmation ? "Copied to clipboard" : "Tap to copy your code")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(copyConfirmation ? AppTheme.Colors.success : AppTheme.Colors.faint)
            }

            Rectangle()
                .fill(AppTheme.Colors.stroke)
                .frame(height: 1)
                .opacity(0.7)

            addFriendRow
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.Colors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.Colors.accent.opacity(0.55), AppTheme.Colors.accent.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: AppTheme.Colors.glow.opacity(0.22), radius: 18, y: 8)
        )
    }

    /// Section header with centered title/subtitle for the Friends screen.
    private func centeredSectionHeader(title: String, subtitle: String?) -> some View {
        VStack(spacing: 3) {
            Text(title.uppercased())
                .font(AppDesignSystem.Typography.sectionLabel)
                .tracking(1.2)
                .foregroundStyle(AppTheme.Colors.text.opacity(0.85))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var addFriendRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.subtext)
                TextField("Enter friend code", text: $codeInput)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .foregroundStyle(AppTheme.Colors.text)
                    .onChange(of: codeInput) { _, newValue in
                        let sanitized = newValue
                            .uppercased()
                            .filter { $0.isLetter || $0.isNumber }
                        if sanitized != newValue {
                            codeInput = String(sanitized.prefix(8))
                        } else if sanitized.count > 8 {
                            codeInput = String(sanitized.prefix(8))
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.Colors.card)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                    )
            )

            Button {
                Task { await sendRequest() }
            } label: {
                HStack(spacing: 6) {
                    if isSending {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Add")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.Colors.accentGradient)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(AppTheme.Colors.accentHighlight.opacity(0.6), lineWidth: 1)
                        )
                        .shadow(color: AppTheme.Colors.accent.opacity(0.55), radius: 12, y: 4)
                )
            }
            .buttonStyle(TapBurstButtonStyle())
            .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            .opacity(codeInput.trimmingCharacters(in: .whitespaces).isEmpty ? 0.9 : 1.0)
        }
    }

    private var notifyCaption: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.subtext)
            Text("You'll be connected instantly")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
        }
    }

    private var emptyFriendsBubble: some View {
        Text("No friends yet. Share your code or add someone else's.")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppTheme.Colors.subtext)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.card2)
            )
            .gentleFadeIn()
    }

    // MARK: - Actions

    private func copyCode() {
        guard let code = friendsService.myFriendCode else { return }
        UIPasteboard.general.string = code
        Haptics.lightTap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            copyConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.25)) {
                copyConfirmation = false
            }
        }
    }

    private func sendRequest() async {
        guard let uid = authService.user?.uid else { return }
        let code = codeInput.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty else { return }
        isSending = true
        sendTimeoutTask?.cancel()
        sendTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, isSending else { return }
            isSending = false
            Haptics.error()
            actionMessageIsError = true
            actionMessage = "Request timed out. Check your connection and try again."
        }
        defer {
            sendTimeoutTask?.cancel()
            sendTimeoutTask = nil
            isSending = false
        }
        do {
            try await friendsService.sendFriendRequest(toCode: code, myUid: uid, myName: myName)
            // Always refresh on success, even if our own 15s watchdog already
            // fired and displayed "timed out" — a slow network doesn't mean
            // the call failed, and the friendship may have been created on
            // the server moments after we gave up waiting for it locally.
            let hadAlreadyTimedOut = !isSending
            store.syncProfileSnapshotToCloud()
            await friendsService.refreshFriendIds()
            await friendsService.refreshFriendProfiles()
            Haptics.success()
            actionMessageIsError = false
            actionMessage = hadAlreadyTimedOut
                ? "You're now friends! (That took longer than expected — check your connection.)"
                : "You're now friends!"
            codeInput = ""
            isSending = false
        } catch is CancellationError {
            return
        } catch {
            guard isSending else { return }
            Haptics.error()
            actionMessageIsError = true
            if let friendsError = error as? FriendsError {
                actionMessage = friendsError.errorDescription ?? "Something went wrong. Check your connection and try again."
            } else {
                actionMessage = "Something went wrong. Check your connection and try again."
            }
        }
    }

    private func accept(_ request: FriendRequestItem) async {
        guard let uid = authService.user?.uid else { return }
        do {
            try await friendsService.acceptRequest(fromUid: request.fromUid, myUid: uid)
            // Re-attach listeners so the new friend appears immediately
            friendsService.startListening(uid: uid)
            store.syncProfileSnapshotToCloud()
            actionMessageIsError = false
            actionMessage = "You're now friends with \(request.fromName)"
        } catch {
            actionMessageIsError = true
            actionMessage = error.localizedDescription
        }
    }

    private func decline(_ request: FriendRequestItem) async {
        guard let uid = authService.user?.uid else { return }
        do {
            try await friendsService.declineRequest(fromUid: request.fromUid, myUid: uid)
            actionMessageIsError = false
            actionMessage = "Declined \(request.fromName)'s request"
        } catch {
            actionMessageIsError = true
            actionMessage = error.localizedDescription
        }
    }

    private func removeFriend(_ friend: FriendProfile) async -> Bool {
        guard let uid = authService.user?.uid else { return false }
        do {
            try await friendsService.removeFriend(friendUid: friend.uid, myUid: uid)
            actionMessageIsError = false
            actionMessage = "Removed \(friend.displayName)"
            return true
        } catch {
            actionMessageIsError = true
            actionMessage = error.localizedDescription
            return false
        }
    }

}

// MARK: - Rows

struct FriendStatsRow: View {
    let friend: FriendProfile
    var onOpenProfile: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatarView(
                        name: friend.displayName,
                        size: 52,
                        photoURL: friend.profilePhotoURL,
                        uid: friend.uid
                    )
                    Text("\(friend.level)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.Colors.accentGradient))
                        .overlay(Capsule().stroke(AppTheme.Colors.card, lineWidth: 2))
                        .offset(x: 5, y: 5)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(friend.displayName)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.text)
                    }
                    Text(friend.levelDisplayLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.faint)
            }

            if friend.privacy.shareHours {
                HStack(spacing: 10) {
                    statChip(
                        icon: "clock.fill",
                        value: AppTheme.Format.hours(friend.chequeHours),
                        label: "this cheque",
                        tint: AppTheme.Colors.accent
                    )
                    statChip(
                        icon: "flame.fill",
                        value: "\(friend.currentStreak)",
                        label: "day streak",
                        tint: .orange
                    )
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Hours hidden")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(AppTheme.Colors.subtext)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.Colors.card2))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.Colors.card)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.Colors.stroke, lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.lightTap()
            onOpenProfile?()
        }
        .accessibilityHint("Opens friend profile")
    }

    private func statChip(icon: String, value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.13)))
    }
}

struct FriendRequestRow: View {
    let request: FriendRequestItem
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(
                name: request.fromName,
                size: 44,
                photoURL: nil,
                uid: request.fromUid
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(request.fromName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                Text("Wants to be friends")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }

            Spacer()

            Button(action: onDecline) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(AppTheme.Colors.card))
            }
            .buttonStyle(.plain)

            Button(action: onAccept) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(AppTheme.Colors.accentGradient))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.Colors.accent.opacity(0.4), lineWidth: 1.5))
        )
    }
}
