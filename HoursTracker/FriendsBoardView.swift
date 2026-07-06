import SwiftUI

/// Friends-only message board: short posts, emoji reactions, and comments.
struct FriendsBoardView: View {
    @ObservedObject var board: FriendsBoardService
    @ObservedObject var friendsService: FriendsService
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var authService: AuthService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.semanticColors) private var theme

    @State private var composerText = ""
    @State private var composerError: String?
    @State private var expandedPosts: Set<String> = []
    @State private var commentDrafts: [String: String] = [:]
    @State private var actionError: String?

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var currentUid: String? { authService.user?.uid }

    private var todayHours: Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return store.entries
            .filter { !$0.isOffDay && $0.date >= start }
            .reduce(0) { $0 + $1.paidHours }
    }

    private var weeklyHours: Double {
        WeeklyStatsCalculator.weeklyHours(store.entries)
    }

    private var equippedTitle: String {
        store.displayedEquippedTitle
    }

    var body: some View {
        NavigationStack {
            content
                .background(AppTheme.Colors.bg.ignoresSafeArea())
                .navigationTitle("Friends Board")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .buttonStyle(PremiumPressStyle())
                    }
                }
                .onAppear { refreshSubscription() }
                .onChange(of: authService.user?.uid) { _, _ in refreshSubscription() }
                .onChange(of: friendsService.friends.count) { _, _ in refreshSubscription() }
                .onDisappear {
                    for post in board.posts where expandedPosts.contains(post.compositeKey) {
                        board.stopListeningToComments(for: post)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = board.errorMessage, board.posts.isEmpty {
            errorState(error)
        } else if board.isLoading && board.posts.isEmpty {
            SoftLoadingIndicator(title: "Loading the crew board…")
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    composerCard
                        .padding(.bottom, 4)

                    if let actionError {
                        Text(actionError)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if board.posts.isEmpty {
                        emptyState
                    } else {
                        ForEach(board.posts) { post in
                            postCard(post)
                        }
                    }
                }
                .animation(nil, value: board.posts.map(\.compositeKey))
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
            }
            .refreshable {
                guard let uid = currentUid else { return }
                await board.refresh(
                    uid: uid,
                    friendUids: friendsService.friends.map(\.uid)
                )
            }
        }
    }

    // MARK: - Composer

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                avatarCircle(
                    initials: BoardContentFilter.initials(from: myDisplayName),
                    tint: theme.accent
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share with your crew")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    if todayHours > 0 || weeklyHours > 0 {
                        Text(contextSummary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            quickPromptRow

            ZStack(alignment: .topLeading) {
                if composerText.isEmpty {
                    Text("What's the grind looking like?")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 10)
                }
                TextEditor(text: $composerText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72, maxHeight: 120)
                    .onChange(of: composerText) { _, newValue in
                        if newValue.count > BoardContentFilter.maxPostLength {
                            composerText = String(newValue.prefix(BoardContentFilter.maxPostLength))
                        }
                        composerError = nil
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                    .fill(theme.cardSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                    .stroke(theme.border, lineWidth: 0.5)
            )

            HStack {
                Text("\(composerText.count)/\(BoardContentFilter.maxPostLength)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Button {
                    Task { await submitPost() }
                } label: {
                    HStack(spacing: 6) {
                        if board.isPosting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Post")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppTheme.Colors.accentGradient)
                    )
                }
                .buttonStyle(TapBurstButtonStyle())
                .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || board.isPosting)
                .opacity(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }

            if let composerError {
                Text(composerError)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.danger)
            }
        }
        .padding(14)
        .background(glassCardBackground)
    }

    private var quickPromptRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if todayHours > 0 {
                    quickChip("Just logged \(AppTheme.Format.hours(todayHours)) today")
                }
                if weeklyHours > 0 {
                    quickChip("Hit \(AppTheme.Format.hours(weeklyHours)) this week")
                }
                quickChip("Grinding Saturday OT")
                quickChip("Who else is working late?")
            }
        }
    }

    private func quickChip(_ text: String) -> some View {
        Button {
            Haptics.lightTap()
            composerText = text
        } label: {
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(theme.accent.opacity(0.12))
                )
        }
        .buttonStyle(PremiumPressStyle())
    }

    private var contextSummary: String {
        var parts: [String] = []
        if todayHours > 0 { parts.append("\(AppTheme.Format.hours(todayHours)) today") }
        if weeklyHours > 0 { parts.append("\(AppTheme.Format.hours(weeklyHours)) this week") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Post card

    private func postCard(_ post: BoardPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                avatarCircle(initials: post.authorInitials, tint: avatarTint(for: post.authorUid))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(post.authorName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                        if let badge = post.badgeContext, !badge.isEmpty {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(theme.accent.opacity(0.14)))
                        }
                    }
                    HStack(spacing: 6) {
                        Text(relativeFormatter.localizedString(for: post.createdAt, relativeTo: Date()))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                        if let hour = post.hourContext, !hour.isEmpty {
                            Text("·")
                                .foregroundStyle(theme.textTertiary)
                            Text(hour)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }

                Spacer(minLength: 0)

                if post.authorUid == currentUid {
                    Menu {
                        Button(role: .destructive) {
                            Task { await deletePost(post) }
                        } label: {
                            Label("Delete post", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                            .frame(width: 28, height: 28)
                    }
                }
            }

            Text(post.text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            reactionBar(for: post)

            commentsSection(for: post)
        }
        .padding(14)
        .background(glassCardBackground)
    }

    private func reactionBar(for post: BoardPost) -> some View {
        HStack(spacing: 6) {
            ForEach(BoardContentFilter.allowedReactionEmojis, id: \.self) { emoji in
                reactionButton(post: post, emoji: emoji)
            }
            Spacer(minLength: 0)
            Button {
                toggleComments(for: post)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text(post.commentCount == 0 ? "Comment" : "\(post.commentCount)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(expandedPosts.contains(post.compositeKey) ? theme.accent : theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(theme.cardSecondary)
                )
            }
            .buttonStyle(PremiumPressStyle())
        }
    }

    private func reactionButton(post: BoardPost, emoji: String) -> some View {
        let count = post.reactionCount(for: emoji)
        let isMine = post.userReactionEmoji(currentUid: currentUid) == emoji
        return Button {
            Haptics.lightTap()
            Task {
                do {
                    try await board.toggleReaction(on: post, emoji: emoji)
                } catch {
                    actionError = error.localizedDescription
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(emoji)
                    .font(.system(size: 15))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isMine ? theme.accent : theme.textSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(isMine ? theme.accent.opacity(0.18) : theme.cardSecondary)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isMine ? theme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PremiumPressStyle())
    }

    @ViewBuilder
    private func commentsSection(for post: BoardPost) -> some View {
        if expandedPosts.contains(post.compositeKey) {
            let key = post.compositeKey
            let comments = board.commentsByPost[key] ?? []

            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(theme.border)

                if comments.isEmpty {
                    Text("No comments yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                } else {
                    ForEach(comments) { comment in
                        commentRow(comment)
                    }
                }

                HStack(spacing: 8) {
                    TextField("Add a comment…", text: binding(for: key))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(theme.cardSecondary)
                        )
                    Button {
                        Task { await submitComment(on: post) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(PremiumPressStyle())
                    .disabled((commentDrafts[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.top, 2)
        }
    }

    private func commentRow(_ comment: BoardComment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text(relativeFormatter.localizedString(for: comment.createdAt, relativeTo: Date()))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                }
                Text(comment.text)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
            if comment.authorId == currentUid {
                Button(role: .destructive) {
                    Task { await deleteComment(comment) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Shared UI

    private var glassCardBackground: some View {
        RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
            .fill(theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                    .stroke(theme.border, lineWidth: 0.5)
            )
    }

    private func avatarCircle(initials: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 40, height: 40)
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
    }

    private func avatarTint(for uid: String) -> Color {
        if uid == currentUid { return theme.accent }
        let hash = abs(uid.hashValue)
        let hues: [Color] = [.purple, .blue, .orange, .pink, .teal, .mint]
        return hues[hash % hues.count]
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text("No posts yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text("Be the first to post your grind — share hours, OT, badges, or ask who's still on the clock.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .gentleFadeIn()
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppTheme.Colors.danger)
            Text("Couldn't load the board")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Try again") {
                Haptics.lightTap()
                refreshSubscription()
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.Colors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gentleFadeIn()
    }

    // MARK: - Actions

    private var myDisplayName: String {
        UserDefaults.standard.string(forKey: "profile_display_name") ?? "Worker"
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { commentDrafts[key, default: ""] },
            set: { commentDrafts[key] = $0 }
        )
    }

    private func refreshSubscription() {
        guard let uid = currentUid else {
            board.stopListening()
            return
        }
        board.startListening(uid: uid, friendUids: friendsService.friends.map(\.uid))
    }

    private func submitPost() async {
        composerError = nil
        actionError = nil
        var hourContext: String?
        if todayHours > 0 || weeklyHours > 0 {
            hourContext = contextSummary
        }
        var badgeContext: String?
        if !equippedTitle.isEmpty {
            badgeContext = equippedTitle
        }
        do {
            try await board.createPost(
                text: composerText,
                hourContext: hourContext,
                badgeContext: badgeContext
            )
            Haptics.success()
            composerText = ""
        } catch {
            Haptics.error()
            composerError = error.localizedDescription
        }
    }

    private func deletePost(_ post: BoardPost) async {
        do {
            try await board.deletePost(post)
            expandedPosts.remove(post.compositeKey)
            Haptics.lightTap()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func toggleComments(for post: BoardPost) {
        Haptics.lightTap()
        let key = post.compositeKey
        if expandedPosts.contains(key) {
            expandedPosts.remove(key)
            board.stopListeningToComments(for: post)
        } else {
            expandedPosts.insert(key)
            board.startListeningToComments(for: post)
        }
    }

    private func submitComment(on post: BoardPost) async {
        let key = post.compositeKey
        let draft = commentDrafts[key, default: ""]
        actionError = nil
        do {
            try await board.addComment(to: post, text: draft)
            commentDrafts[key] = ""
            Haptics.lightTap()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteComment(_ comment: BoardComment) async {
        do {
            try await board.deleteComment(comment)
            Haptics.lightTap()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
