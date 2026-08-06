import SwiftUI

// MARK: - Friends hub (Phase 6)
//
// Friend-code card, pending requests, then the friends list. Rows and cards
// live in FriendsSections.swift.

struct FriendsView: View {
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        Group {
            if !authService.isSignedIn {
                signedOutPlaceholder
            } else {
                friendsContent
            }
        }
        .background(AppColors.bg.ignoresSafeArea())
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
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

    private var signedOutPlaceholder: some View {
        AppEmptyState(
            icon: "person.2",
            title: "Sign in to use Friends",
            message: "Sign in with Apple from Account to add friends and see their stats."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var friendsContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                FriendCodeCard(
                    code: friendsService.myFriendCode,
                    codeInput: $codeInput,
                    isSending: isSending,
                    copyConfirmation: copyConfirmation,
                    onCopy: { copyCode() },
                    onAdd: { Task { await sendRequest() } }
                )

                notifyCaption
                    .frame(maxWidth: .infinity)

                if let actionMessage {
                    Text(actionMessage)
                        .appText(.caption)
                        .foregroundStyle(actionMessageIsError ? AppColors.negative : AppColors.accent)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                // Surface listener/load errors that were previously silent —
                // without this, a permission or network error just looked
                // like "no friends" with no indication anything went wrong.
                if let serviceError = friendsService.errorMessage {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColors.warning)
                        Text(serviceError)
                            .appText(.caption)
                            .foregroundStyle(AppColors.text)
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(AppSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(AppColors.warning.opacity(0.12))
                    )
                }

                if !friendsService.pendingRequests.isEmpty {
                    SectionEyebrow("Requests")
                        .padding(.top, AppSpacing.xxs)
                    ForEach(friendsService.pendingRequests) { request in
                        FriendRequestRow(request: request) {
                            Task { await accept(request) }
                        } onDecline: {
                            Task { await decline(request) }
                        }
                    }
                }

                friendsList
                    .padding(.top, AppSpacing.xxs)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.md)
        }
        .refreshable {
            store.syncProfileSnapshotToCloud()
            await friendsService.refreshFriendIds(surfaceErrors: true)
            await friendsService.refreshFriendProfiles()
            await friendsService.refreshPendingRequests(surfaceErrors: true)
        }
    }

    // MARK: - Friends list

    private var friendsList: some View {
        let maxWeekly = friendsService.friends
            .filter { $0.privacy.shareHours }
            .map(\.weeklyHours)
            .max() ?? 0

        return VStack(spacing: AppSpacing.sm) {
            if !friendsService.friends.isEmpty {
                ForEach(friendsService.friends) { friend in
                    FriendStatsRow(
                        friend: friend,
                        maxWeeklyHours: maxWeekly,
                        onOpenProfile: {
                            profileFriendUid = friend.uid
                        }
                    )
                }
            } else if friendsService.isLoading {
                AppLoadingState(message: "Loading friends…")
                    .frame(minHeight: 160)
            } else {
                AppEmptyState(
                    icon: "person.2",
                    title: "No friends yet",
                    message: "Share your code or add someone else's to compare weeks."
                )
            }
        }
    }

    private var notifyCaption: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "bell")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.subtext)
            Text("You'll be connected instantly")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
        }
    }

    // MARK: - Actions

    private func copyCode() {
        guard let code = friendsService.myFriendCode else { return }
        UIPasteboard.general.string = code
        Haptics.lightTap()
        withAnimation(AppMotion.animation(AppMotion.Spring.snappy, reduceMotion: reduceMotion)) {
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
