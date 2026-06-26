import SwiftUI

struct FriendsView: View {
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var friendsService = FriendsService.shared
    @ObservedObject private var nudgeService = FriendShiftNudgeService.shared
    @State private var codeInput = ""
    @State private var actionMessage: String?
    @State private var actionMessageIsError = false
    @State private var copyConfirmation = false
    @State private var isSending = false
    @State private var sendTimeoutTask: Task<Void, Never>?
    @State private var showingLeaderboard = false
    @State private var profileFriendUid: String?
    @State private var nudgingFriendUid: String?
    @State private var showingNudgeResponse = false

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
                    nudgeService.startListening(uid: uid)
                    Task { await friendsService.refreshFriendProfiles() }
                }
                store.syncProfileSnapshotToCloud()
            }
            .onChange(of: nudgeService.pendingNudge?.id) { _, newId in
                showingNudgeResponse = newId != nil
            }
            .onChange(of: authService.user?.uid) { _, uid in
                if let uid {
                    friendsService.startListening(uid: uid)
                    nudgeService.startListening(uid: uid)
                } else {
                    friendsService.stopListening()
                    nudgeService.stopListening()
                }
            }
            .sheet(isPresented: $showingNudgeResponse) {
                if let nudge = nudgeService.pendingNudge {
                    FriendShiftNudgeResponseSheet(
                        nudge: nudge,
                        onRespond: { emoji in
                            await respondToNudge(nudge, emoji: emoji)
                        },
                        onDismiss: {
                            showingNudgeResponse = false
                            nudgeService.dismissPendingNudge()
                        }
                    )
                }
            }
            .sheet(isPresented: $showingLeaderboard) {
                FriendsLeaderboardView(store: store, friendsService: friendsService)
                    .environmentObject(authService)
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

    /// Shortcut above the friend-code section for the weekly leaderboard.
    private var socialShortcutRow: some View {
        socialShortcutButton(
            title: "Leaderboard",
            systemImage: "rosette",
            accent: AppTheme.Colors.accent
        ) {
            Haptics.lightTap()
            showingLeaderboard = true
        }
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    private func socialShortcutButton(
        title: String,
        systemImage: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), accent.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: accent.opacity(0.3), radius: 6, y: 2)
            )
        }
        .buttonStyle(ReactionPopButtonStyle())
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
            VStack(alignment: .leading, spacing: 18) {
                socialShortcutRow

                Text("Add friends by code")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .padding(.horizontal, AppTheme.Spacing.md)

                myCodeRow
                    .padding(.horizontal, AppTheme.Spacing.md)

                addFriendRow
                    .padding(.horizontal, AppTheme.Spacing.md)

                notifyCaption
                    .padding(.horizontal, AppTheme.Spacing.md)

                if let actionMessage {
                    Text(actionMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(actionMessageIsError ? .red : AppTheme.Colors.accent)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .transition(.opacity)
                }

                if !friendsService.pendingRequests.isEmpty {
                    SectionHeader(title: "Requests", subtitle: nil)
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
                    SectionHeader(title: "Friends", subtitle: "Tap a friend to view their profile")
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, 4)
                    ForEach(friendsService.friends) { friend in
                        FriendStatsRow(
                            friend: friend,
                            onOpenProfile: {
                                profileFriendUid = friend.uid
                            },
                            onNudge: {
                                Task { await sendNudge(to: friend) }
                            },
                            isNudgeSending: nudgingFriendUid == friend.uid,
                            didSendNudge: nudgeService.lastSentFriendUid == friend.uid
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
            await friendsService.refreshFriendProfiles()
        }
    }

    private var myCodeRow: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Code:")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                Text(friendsService.myFriendCode ?? "—")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                copyCode()
            } label: {
                Image(systemName: copyConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(copyConfirmation ? AppTheme.Colors.accent : AppTheme.Colors.subtext)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(friendsService.myFriendCode == nil)
        }
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
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.Colors.accentGradient)
                )
            }
            .buttonStyle(TapBurstButtonStyle())
            .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            .opacity(codeInput.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1.0)
        }
    }

    private var notifyCaption: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.subtext)
            Text("Friend will be notified of your request")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
        }
    }

    private var emptyFriendsBubble: some View {
        Text("No friends yet. Share your code or add someone else's.")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppTheme.Colors.subtext)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            guard isSending else { return }
            store.syncProfileSnapshotToCloud()
            Haptics.success()
            actionMessageIsError = false
            actionMessage = "Request sent!"
            codeInput = ""
        } catch {
            guard isSending else { return }
            Haptics.error()
            actionMessageIsError = true
            actionMessage = error.localizedDescription
        }
    }

    private func accept(_ request: FriendRequestItem) async {
        guard let uid = authService.user?.uid else { return }
        do {
            try await friendsService.acceptRequest(fromUid: request.fromUid, myUid: uid)
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

    private func sendNudge(to friend: FriendProfile) async {
        guard let uid = authService.user?.uid else { return }
        nudgingFriendUid = friend.uid
        defer { nudgingFriendUid = nil }
        do {
            try await nudgeService.sendNudge(to: friend.uid, myUid: uid, myName: myName)
            Haptics.success()
            actionMessageIsError = false
            actionMessage = "Reminder sent to \(friend.displayName)"
        } catch {
            Haptics.error()
            actionMessageIsError = true
            actionMessage = error.localizedDescription
        }
    }

    private func respondToNudge(_ nudge: FriendShiftNudge, emoji: String) async -> Bool {
        guard let uid = authService.user?.uid else { return false }
        do {
            try await nudgeService.respond(to: nudge, emoji: emoji, myUid: uid)
            Haptics.success()
            showingNudgeResponse = false
            actionMessageIsError = false
            actionMessage = "Replied \(emoji) to \(nudge.fromName)"
            return true
        } catch {
            Haptics.error()
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
    var onNudge: (() -> Void)? = nil
    var isNudgeSending: Bool = false
    var didSendNudge: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ProfileAvatarView(
                name: friend.displayName,
                size: 50,
                photoURL: friend.profilePhotoURL,
                uid: friend.uid
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(friend.displayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.text)

                    if onNudge != nil {
                        FriendShiftNudgeButton(
                            friendUid: friend.uid,
                            isSending: isNudgeSending,
                            didSend: didSendNudge,
                            action: { onNudge?() }
                        )
                    }
                }
                Text(friend.levelDisplayLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if friend.privacy.shareHours {
                    Text(AppTheme.Format.hours(friend.chequeHours))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("this cheque")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.subtext)
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text("\(friend.currentStreak)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.subtext)
                    }
                } else {
                    Text("Hours hidden")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.Colors.faint)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.Colors.card)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.Colors.stroke, lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.lightTap()
            onOpenProfile?()
        }
        .accessibilityHint("Opens friend profile")
    }
}

struct FriendRequestRow: View {
    let request: FriendRequestItem
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.fromName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                Text("Wants to be friends")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
            Spacer()
            Button("Decline", action: onDecline)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.subtext)
            Button("Accept", action: onAccept)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.Colors.accent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.Colors.accent.opacity(0.35), lineWidth: 1))
        )
    }
}
