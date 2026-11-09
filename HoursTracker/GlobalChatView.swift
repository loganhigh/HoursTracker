import SwiftUI

// MARK: - Board chat
//
// The room everyone on the global board shares: cheer each other on, tag
// someone with their @username (that pushes them — nothing else in here
// does), double-tap a message to react with an emoji, or long-press it to
// reply, message them privately, report or block. Newest messages sit at the bottom, like any chat.

struct GlobalChatView: View {
    @ObservedObject private var chat = ChatService.shared
    @ObservedObject private var friends = FriendsService.shared
    @ObservedObject private var topTrackers = TopTrackersService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var reportTarget: ChatReportTarget?
    @State private var blockTarget: ChatMessage?
    @State private var dmTarget: DirectThreadTarget?
    @State private var showingInbox = false
    /// The message whose emoji picker is open (double-tap or long-press).
    @State private var reactingTo: String?
    @FocusState private var composerFocused: Bool
    /// One-time agreement to the chat rules (App Review expects one for
    /// user-generated content).
    @AppStorage("chat_rules_accepted_v1") private var acceptedRules = false
    @State private var showingRules = false

    private var myUid: String? { AuthService.shared.user?.uid }
    private var myUsername: String? { friends.myUsername }

    /// Board names plus anyone who has chatted recently, most recent first.
    private var tagSuggestions: [String] {
        var seen = Set<String>()
        let names = chat.visibleGlobalMessages.reversed().map(\.username)
            + topTrackers.allTrackers.map { Username.normalize($0.name) }
        return names.filter { name in
            guard !name.isEmpty, name != myUsername, Username.problem(with: name, moderation: { _ in false }) == nil else { return false }
            return seen.insert(name).inserted
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppColors.stroke)
            messages
            if myUsername == nil {
                Text("Pick a username in Friends to join the chat.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.subtext)
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.md)
            } else if !acceptedRules {
                Button("Join the chat") { showingRules = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(AppSpacing.md)
            } else {
                if let errorText {
                    Text(errorText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.negative)
                        .padding(.horizontal, AppSpacing.md)
                        .transition(.opacity)
                }
                ChatComposer(text: $draft, placeholder: "Network with others! Use @ to tag",
                             suggestions: tagSuggestions, isSending: isSending,
                             isFocused: $composerFocused, onSend: send)
            }
        }
        .background(AppColors.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $dmTarget) { DirectThreadView(target: $0) }
        .navigationDestination(isPresented: $showingInbox) { DirectInboxView() }
        .chatReportDialog($reportTarget)
        .alert("Board Chat rules", isPresented: $showingRules) {
            Button("I agree") { acceptedRules = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keep it encouraging. No harassment, hate, sexual content, spam or sharing personal info. Messages that break these rules are removed and the sender can lose chat access. Long-press any message to report or block someone.")
        }
        .confirmationDialog("Block @\(blockTarget?.username ?? "")?", isPresented: Binding(
            get: { blockTarget != nil }, set: { if !$0 { blockTarget = nil } }
        ), titleVisibility: .visible, presenting: blockTarget) { message in
            Button("Block", role: .destructive) {
                Task { await chat.block(uid: message.uid, username: message.username) }
            }
        } message: { _ in
            Text("You won't see their messages, and they can't message you or notify you with a tag.")
        }
        .onAppear {
            chat.startGlobal()
            chat.startInbox()
        }
        .onDisappear { chat.stopGlobal() }
        .task { await topTrackers.ensureFullLeaderboardLoaded() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            circleButton("chevron.left", label: "Back") { dismiss() }
            VStack(alignment: .leading, spacing: 1) {
                Text("Board Chat")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.text)
                Text("Everyone on the global board")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.subtext)
            }
            Spacer(minLength: 0)
            circleButton("paperplane", label: "Direct messages", badge: chat.unreadDirectCount) {
                showingInbox = true
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
    }

    private func circleButton(_ icon: String, label: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.lightTap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppColors.text)
                .frame(width: 40, height: 40)
                .background(Circle().fill(AppColors.card.opacity(0.7))
                    .overlay(Circle().stroke(AppColors.stroke, lineWidth: 0.5)))
                .overlay(alignment: .topTrailing) { UnreadBadge(count: badge) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(label), \(badge) unread" : label)
    }

    // MARK: Messages

    @ViewBuilder
    private var messages: some View {
        if !chat.hasLoadedGlobal {
            AppLoadingState(message: "Loading chat…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if chat.visibleGlobalMessages.isEmpty {
            AppEmptyState(icon: "bubble.left.and.bubble.right", owl: .search, title: "Say hi to the board")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(chat.visibleGlobalMessages) { message in
                            ChatMessageRow(message: message, isMine: message.uid == myUid, myUid: myUid,
                                           myUsername: myUsername,
                                           seenCount: chat.seenCount(message),
                                           hasReacted: { chat.hasReacted($0, to: message) },
                                           onReact: { react($0, to: message) })
                                .id(message.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { openPicker(for: message) }
                                .contextMenu { menu(for: message) }
                                .popover(isPresented: Binding(
                                    get: { reactingTo == message.id },
                                    set: { if !$0 { reactingTo = nil } }
                                )) {
                                    ChatReactionPicker(isChosen: { chat.hasReacted($0, to: message) }) { reaction in
                                        reactingTo = nil
                                        react(reaction, to: message)
                                    }
                                    .presentationCompactAdaptation(.popover)
                                }
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: chat.visibleGlobalMessages.last?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .bottom) }
                    chat.markGlobalRead()
                }
                .onAppear { chat.markGlobalRead() }
            }
        }
    }

    private var canReact: Bool { myUsername != nil && acceptedRules }

    private func openPicker(for message: ChatMessage) {
        guard canReact else {
            if myUsername != nil { showingRules = true }
            return
        }
        Haptics.lightTap()
        reactingTo = message.id
    }

    private func react(_ reaction: ChatReaction, to message: ChatMessage) {
        guard canReact else { return }
        Haptics.lightTap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            chat.toggleReaction(reaction, on: message)
        }
    }

    @ViewBuilder
    private func menu(for message: ChatMessage) -> some View {
        if canReact {
            Button {
                // Let the context menu finish closing before the popover opens.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { reactingTo = message.id }
            } label: { Label("Add reaction", systemImage: "face.smiling") }
        }
        if message.uid != myUid {
            Button {
                draft = draft.isEmpty ? "@\(message.username) " : draft + " @\(message.username) "
                composerFocused = true
            } label: { Label("Reply with @\(message.username)", systemImage: "arrowshape.turn.up.left") }
            Button {
                dmTarget = DirectThreadTarget(otherUid: message.uid, otherUsername: message.username)
            } label: { Label("Message privately", systemImage: "paperplane") }
        }
        Button {
            UIPasteboard.general.string = message.text
        } label: { Label("Copy", systemImage: "doc.on.doc") }
        if message.uid != myUid {
            Button {
                reportTarget = ChatReportTarget(uid: message.uid, username: message.username,
                                                text: message.text, messageId: message.id)
            } label: { Label("Report", systemImage: "flag") }
            Button(role: .destructive) {
                blockTarget = message
            } label: { Label("Block @\(message.username)", systemImage: "hand.raised") }
        }
        if chat.canDelete(message) {
            Button(role: .destructive) {
                Task { await chat.delete(message) }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        errorText = nil
        Task {
            do {
                try await chat.sendGlobal(text)
                draft = ""
            } catch {
                withAnimation { errorText = error.localizedDescription }
                Haptics.error()
            }
            isSending = false
        }
    }
}

/// One chat line: avatar, prestige-styled handle, time, and the text.
struct ChatMessageRow: View {
    let message: ChatMessage
    let isMine: Bool
    let myUid: String?
    let myUsername: String?
    /// Other people who've opened Board Chat since this was posted.
    var seenCount: Int = 0
    var hasReacted: (ChatReaction) -> Bool = { _ in false }
    var onReact: (ChatReaction) -> Void = { _ in }

    private var mentionsMe: Bool { myUid.map { message.mentions.contains($0) } ?? false }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            ProfileAvatarView(name: message.username, size: 34,
                              photoURL: message.photoURL.isEmpty ? nil : message.photoURL,
                              uid: message.uid)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    PrestigeNameText(name: "@\(message.username)", prestige: message.prestige,
                                     font: .subheadline.weight(.bold), uid: message.uid)
                        .lineLimit(1)
                    SupporterHeart(name: message.username, uid: message.uid)
                    if isMine {
                        Text("You")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppColors.accent)
                    }
                    Text(ChatFormat.time(message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(AppColors.faint)
                    if seenCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "eye")
                            Text("\(seenCount)")
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .foregroundStyle(AppColors.faint)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Seen by \(seenCount)")
                    }
                }
                Text(ChatFormat.attributed(message.text, myUsername: myUsername))
                    .font(.body)
                    .foregroundStyle(AppColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                // No .textSelection: it swallows the double-tap that opens
                // reactions (Copy is in the long-press menu).
                if !message.activeReactions.isEmpty {
                    reactionChips
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(mentionsMe ? AppColors.gold.opacity(0.12) : AppColors.card)
                .overlay(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(mentionsMe ? AppColors.gold.opacity(0.5) : AppColors.stroke, lineWidth: 0.5))
        )
    }
}

extension ChatMessageRow {
    /// One chip per emoji with its count; yours are tinted. Tap to toggle.
    private var reactionChips: some View {
        HStack(spacing: 6) {
            ForEach(message.activeReactions, id: \.reaction) { item in
                let mine = hasReacted(item.reaction)
                Button { onReact(item.reaction) } label: {
                    HStack(spacing: 4) {
                        Text(item.reaction.emoji).font(.system(size: 14))
                        Text("\(item.uids.count)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(mine ? AppColors.accent : AppColors.subtext)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(mine ? AppColors.accentMuted : AppColors.card2)
                            .overlay(Capsule().stroke(mine ? AppColors.accent.opacity(0.6) : AppColors.stroke, lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.reaction.emoji) \(item.uids.count)\(mine ? ", you reacted" : "")")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.top, 2)
    }
}

/// The emoji bar a double-tap opens over a message.
struct ChatReactionPicker: View {
    let isChosen: (ChatReaction) -> Bool
    let onPick: (ChatReaction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChatReaction.allCases) { reaction in
                Button { onPick(reaction) } label: {
                    Text(reaction.emoji)
                        .font(.system(size: 28))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(isChosen(reaction) ? AppColors.accentMuted : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("React \(reaction.emoji)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

/// Small red count bubble for unread direct messages.
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(AppColors.negative))
                .offset(x: 6, y: -6)
        }
    }
}
