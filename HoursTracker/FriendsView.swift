import SwiftUI

// MARK: - Friends hub
//
// A competitive board: header, weekly podium, metric switcher, ranked rows
// (the signed-in user among their friends), then the crew summary. Adding a
// friend moved into a sheet behind the header's + button so the board owns the
// screen. Board types live in FriendsLeaderboardModel.swift, the podium in
// FriendsPodiumSections.swift, rows in FriendsLeaderboardSections.swift, and
// the friend-code card and request rows remain in FriendsSections.swift.

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
    @State private var nudgeTarget: FriendProfile?
    @State private var isSendingNudge = false
    @State private var nudgeResultMessage: String?
    @State private var metric: LeaderboardMetric = .thisWeek
    @State private var showingSearch = false
    @State private var searchText = ""
    @State private var showingAddFriend = false

    private var myName: String {
        UserDefaults.standard.string(forKey: "profile_display_name") ?? "Worker"
    }

    // MARK: - Board

    /// The signed-in user plus every friend, ranked by the selected metric.
    /// Construction lives on `LeaderboardEntry` — see FriendsLeaderboardModel.
    private var board: [LeaderboardEntry] {
        LeaderboardEntry.board(
            myUid: authService.user?.uid,
            myName: myName,
            myProfile: store.displayedGamificationProfile(),
            myWeeklyHours: WeeklyStatsCalculator.weeklyHours(store.entries),
            myPhotoURL: ProfilePhotoManager.shared.remotePhotoURL,
            friends: friendsService.friends,
            metric: metric
        )
    }

    /// You can't nudge yourself, so your own row gets no nudge action at all
    /// rather than a disabled one.
    private func nudgeAction(for entry: LeaderboardEntry) -> (() -> Void)? {
        guard !entry.isMe else { return nil }
        return { nudgeTarget = friendsService.friends.first { $0.uid == entry.id } }
    }

    private func visibleEntries(from entries: [LeaderboardEntry]) -> [LeaderboardEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.isMe || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var searchField: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.faint)
            TextField("Search friends", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.text)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(AppColors.card.opacity(0.55))
                .overlay(Capsule().stroke(AppColors.stroke, lineWidth: 0.5))
        )
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
        // The screen draws its own large "Friends" header, so the nav bar's
        // would be a second copy of the same word.
        .toolbar(.hidden, for: .navigationBar)
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
        .sheet(isPresented: $showingAddFriend) {
            NavigationStack {
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
                        if let actionMessage {
                            Text(actionMessage)
                                .appText(.caption)
                                .foregroundStyle(actionMessageIsError ? AppColors.negative : AppColors.accent)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(AppSpacing.md)
                }
                .background(AppColors.bg.ignoresSafeArea())
                .navigationTitle("Add a friend")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingAddFriend = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $nudgeTarget) { friend in
            FriendShiftNudgePicker(
                friendName: friend.displayName,
                isSending: isSendingNudge,
                onPick: { kind in sendNudge(to: friend, kind: kind) },
                onCancel: { nudgeTarget = nil }
            )
        }
        .overlay(alignment: .bottom) {
            if let nudgeResultMessage {
                Text(nudgeResultMessage)
                    .appText(.caption)
                    .foregroundStyle(AppColors.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(AppColors.card)
                            .overlay(Capsule().stroke(AppColors.stroke, lineWidth: 0.5))
                    )
                    .padding(.bottom, 18)
                    .transition(.opacity)
            }
        }
    }

    /// Sends from the list row. Mirrors the profile's flow, but the confirmation
    /// is a transient toast — there is no row-level space to keep it around.
    private func sendNudge(to friend: FriendProfile, kind: NudgeKind) {
        guard let uid = authService.user?.uid, !isSendingNudge else { return }
        isSendingNudge = true
        Task {
            defer { isSendingNudge = false }
            let message: String
            do {
                try await FriendShiftNudgeService.shared.sendNudge(
                    to: friend.uid,
                    myUid: uid,
                    myName: UserDefaults.standard.string(forKey: "profile_display_name") ?? "",
                    kind: kind
                )
                Haptics.success()
                message = "Sent \(kind.emoji) \(kind.label) to \(friend.displayName)."
            } catch {
                Haptics.error()
                message = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't send the nudge. Try again later."
            }
            nudgeTarget = nil
            withAnimation { nudgeResultMessage = message }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { nudgeResultMessage = nil }
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
        // Bound once: `board` sorts the full list and reads the rank snapshot,
        // and the body touches it four times. Recomputing per access also risks
        // two call sites disagreeing mid-render.
        let entries = board
        let visible = visibleEntries(from: entries)
        return ScrollView {
            VStack(spacing: AppSpacing.md) {
                FriendsHeroHeader(
                    onSearch: {
                        withAnimation { showingSearch.toggle() }
                        if !showingSearch { searchText = "" }
                    },
                    onAddFriend: { showingAddFriend = true }
                )

                if showingSearch {
                    searchField
                }

                if !entries.isEmpty {
                    WeeklyPodiumCard(
                        entries: entries,
                        metric: metric,
                        resetsAt: WeeklyStatsCalculator.currentWeekInterval().end
                    )

                    LeaderboardMetricPicker(selection: $metric)
                }

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

                friendsList(visible)
                    .padding(.top, AppSpacing.xxs)

                if entries.count > 1 {
                    CrewSummaryCard(entries: entries, onOpen: nil)
                }
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

    private func friendsList(_ visible: [LeaderboardEntry]) -> some View {
        VStack(spacing: AppSpacing.xs) {
            if !friendsService.friends.isEmpty {
                ForEach(visible) { entry in
                    LeaderboardRankRow(
                        entry: entry,
                        metric: metric,
                        onOpen: {
                            // Tapping your own row has nowhere useful to go —
                            // the You tab already is your profile.
                            guard !entry.isMe else { return }
                            profileFriendUid = entry.id
                        },
                        onNudge: nudgeAction(for: entry)
                    )
                }
                if visible.isEmpty {
                    Text("No one matches \u{201C}\(searchText)\u{201D}")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.lg)
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
