import SwiftUI
import FirebaseFirestore

// MARK: - Direct messages
//
// Inbox of one-to-one threads (newest first, unread counts) and the thread
// itself. Anyone with a username can be messaged by their @handle; every
// message pushes the recipient. Blocking either way stops new messages.

/// Who a thread is with — enough to open it before it exists.
struct DirectThreadTarget: Hashable, Identifiable {
    let otherUid: String?
    let otherUsername: String
    var id: String { otherUid ?? "@\(otherUsername)" }
}

struct DirectInboxView: View {
    @ObservedObject private var chat = ChatService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var openThread: DirectThreadTarget?
    @State private var newHandle = ""
    @State private var showingNew = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.sm) {
                headerButton("chevron.left", label: "Back") { dismiss() }
                Text("Messages")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.text)
                Spacer(minLength: 0)
                headerButton("square.and.pencil", label: "New message") { showingNew = true }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            Divider().overlay(AppColors.stroke)

            if chat.visibleThreads.isEmpty {
                AppEmptyState(icon: "paperplane", owl: .search, title: "No messages yet")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.xs) {
                        ForEach(chat.visibleThreads) { thread in
                            Button {
                                openThread = DirectThreadTarget(otherUid: thread.otherUid, otherUsername: thread.otherUsername)
                            } label: {
                                threadRow(thread)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(AppSpacing.md)
                }
            }
        }
        .background(AppColors.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openThread) { DirectThreadView(target: $0) }
        .alert("New message", isPresented: $showingNew) {
            TextField("@username", text: $newHandle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Start") {
                let name = Username.normalize(newHandle)
                newHandle = ""
                guard !name.isEmpty else { return }
                openThread = DirectThreadTarget(otherUid: nil, otherUsername: name)
            }
            Button("Cancel", role: .cancel) { newHandle = "" }
        } message: {
            Text("Who do you want to message?")
        }
        .onAppear { chat.startInbox() }
    }

    private func headerButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func threadRow(_ thread: DirectThread) -> some View {
        HStack(spacing: AppSpacing.sm) {
            ProfileAvatarView(name: thread.otherUsername, size: 44, uid: thread.otherUid)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    // Same name styling as Board Chat: supporter blue,
                    // owner gold.
                    PrestigeNameText(name: "@\(thread.otherUsername)", prestige: 0,
                                     font: .subheadline.weight(.bold), uid: thread.otherUid)
                        .lineLimit(1)
                    SupporterHeart(name: thread.otherUsername, uid: thread.otherUid)
                    Spacer()
                    Text(ChatFormat.time(thread.lastAt))
                        .font(.caption2)
                        .foregroundStyle(AppColors.faint)
                }
                HStack {
                    Text((thread.lastSenderUid == thread.otherUid ? "" : "You: ") + thread.lastText)
                        .font(.subheadline)
                        .foregroundStyle(thread.unread > 0 ? AppColors.text : AppColors.subtext)
                        .lineLimit(1)
                    Spacer()
                    if thread.unread > 0 {
                        Circle().fill(AppColors.accent).frame(width: 9, height: 9)
                    }
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous).fill(AppColors.card))
    }
}

struct DirectThreadView: View {
    let target: DirectThreadTarget

    @ObservedObject private var chat = ChatService.shared
    @ObservedObject private var friends = FriendsService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var resolvedUid: String?
    @State private var messages: [DirectMessage] = []
    @State private var listener: ListenerRegistration?
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var reportTarget: ChatReportTarget?
    @State private var confirmingBlock = false
    @FocusState private var composerFocused: Bool
    @AppStorage("chat_rules_accepted_v1") private var acceptedRules = false
    @State private var showingRules = false

    private var myUid: String? { AuthService.shared.user?.uid }
    private var otherUid: String? { target.otherUid ?? resolvedUid }
    private var threadId: String? { otherUid.flatMap { chat.threadId(with: $0) } }
    private var isBlocked: Bool { otherUid.map(chat.isBlocked) ?? false }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppColors.stroke)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if messages.isEmpty {
                            Text("Say hi to @\(target.otherUsername). They'll get a notification.")
                                .font(AppTypography.subheadline)
                                .foregroundStyle(AppColors.subtext)
                                .multilineTextAlignment(.center)
                                .padding(.top, AppSpacing.xl)
                        }
                        ForEach(messages) { message in
                            bubble(message).id(message.id)
                            if message.id == lastMineID {
                                receipt(for: message)
                            }
                        }
                    }
                    .padding(AppSpacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: messages.last?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .bottom) }
                    if let threadId { chat.markRead(threadId) }
                }
            }
            if isBlocked {
                Button("Unblock @\(target.otherUsername)") {
                    if let otherUid { Task { await chat.unblock(uid: otherUid) } }
                }
                .font(AppTypography.subheadline)
                .padding(AppSpacing.md)
            } else if friends.myUsername == nil {
                Text("Pick a username in Friends to send messages.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.subtext)
                    .padding(AppSpacing.md)
            } else if !acceptedRules {
                Button("Start messaging") { showingRules = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(AppSpacing.md)
            } else {
                if let errorText {
                    Text(errorText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.negative)
                        .padding(.horizontal, AppSpacing.md)
                }
                ChatComposer(text: $draft, placeholder: "Message @\(target.otherUsername)",
                             isSending: isSending, isFocused: $composerFocused, onSend: send)
            }
        }
        .background(AppColors.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .chatReportDialog($reportTarget)
        .alert("Messaging rules", isPresented: $showingRules) {
            Button("I agree") { acceptedRules = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keep it respectful. No harassment, hate, sexual content, spam or scams. Anyone breaking these rules can lose messaging. Use the ••• menu to report or block someone.")
        }
        .confirmationDialog("Block @\(target.otherUsername)?", isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                if let otherUid { Task { await chat.block(uid: otherUid, username: target.otherUsername) } }
            }
        } message: {
            Text("They won't be able to message you or notify you with a tag, and you won't see their chat messages.")
        }
        .onAppear {
            chat.startInbox()
            startListening()
        }
        .task {
            // Started by handle: find who it is so earlier messages show.
            guard target.otherUid == nil, resolvedUid == nil else { return }
            resolvedUid = await chat.uid(forUsername: target.otherUsername)
            startListening()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                Haptics.lightTap()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.text)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(AppColors.card.opacity(0.7)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            ProfileAvatarView(name: target.otherUsername, size: 32, uid: otherUid)
            PrestigeNameText(name: "@\(target.otherUsername)", prestige: 0,
                             font: AppTypography.headline, uid: otherUid)
                .lineLimit(1)
            SupporterHeart(name: target.otherUsername, uid: otherUid)
            Spacer(minLength: 0)
            if let otherUid {
                Menu {
                    Button {
                        reportTarget = ChatReportTarget(uid: otherUid, username: target.otherUsername,
                                                        text: messages.last { $0.uid == otherUid }?.text ?? "",
                                                        threadId: threadId)
                    } label: { Label("Report", systemImage: "flag") }
                    if isBlocked {
                        Button { Task { await chat.unblock(uid: otherUid) } } label: {
                            Label("Unblock", systemImage: "hand.raised.slash")
                        }
                    } else {
                        Button(role: .destructive) { confirmingBlock = true } label: {
                            Label("Block", systemImage: "hand.raised")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColors.text)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(AppColors.card.opacity(0.7)))
                }
                .accessibilityLabel("More")
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
    }

    /// Receipt goes under your newest message only, iMessage-style, and
    /// only while it's the latest thing in the thread.
    private var lastMineID: String? {
        guard let last = messages.last, last.uid == myUid else { return nil }
        return last.id
    }

    private func receipt(for message: DirectMessage) -> some View {
        let seenAt = threadId.flatMap { chat.thread($0)?.otherLastReadAt }
        let seen = seenAt.map { $0 >= message.createdAt } ?? false
        return HStack {
            Spacer(minLength: 0)
            Text(seen ? "Seen \(ChatFormat.time(seenAt ?? message.createdAt))" : "Sent")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(seen ? AppColors.accent : AppColors.faint)
                .accessibilityLabel(seen ? "Seen" : "Sent, not seen yet")
        }
        .padding(.top, -2)
    }

    private func bubble(_ message: DirectMessage) -> some View {
        let mine = message.uid == myUid
        return HStack {
            if mine { Spacer(minLength: 48) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(mine ? AppColors.textOnAccent : AppColors.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(mine ? AppColors.accent : AppColors.card)
                    )
                    .textSelection(.enabled)
                Text(ChatFormat.time(message.createdAt))
                    .font(.caption2)
                    .foregroundStyle(AppColors.faint)
            }
            if !mine { Spacer(minLength: 48) }
        }
    }

    private func startListening() {
        guard listener == nil, let threadId else { return }
        listener = chat.listenToThread(threadId) { messages = $0 }
        chat.markRead(threadId)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        errorText = nil
        Task {
            do {
                let id = try await chat.sendDirect(text, toUid: otherUid, toUsername: target.otherUsername)
                draft = ""
                // A thread started by handle: now we know who it's with.
                if resolvedUid == nil, target.otherUid == nil, let myUid {
                    resolvedUid = id.split(separator: "_").map(String.init).first { $0 != myUid }
                    startListening()
                }
            } catch {
                errorText = error.localizedDescription
                Haptics.error()
            }
            isSending = false
        }
    }
}
