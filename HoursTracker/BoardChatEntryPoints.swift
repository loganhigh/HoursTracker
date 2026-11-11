import SwiftUI

// MARK: - Board Chat entry points
//
// Board Chat used to be reachable only from an icon on the full leaderboard,
// two screens in. These put it on Home (newest message + unread dot) and
// introduce it once on the board.

/// Home row under the Top 5: the newest message, an unread dot, one tap in.
struct BoardChatHomeRow: View {
    @ObservedObject private var chat = ChatService.shared

    private var preview: String {
        guard let latest = chat.latestGlobal, !chat.blockedUids.contains(latest.uid) else {
            return "Talk with everyone on the leaderboard"
        }
        return "@\(latest.username): \(latest.text)"
    }

    var body: some View {
        NavigationLink {
            GlobalChatView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppColors.accent.opacity(0.14)))
                    .overlay(alignment: .topTrailing) {
                        if chat.hasUnreadGlobal { UnreadDot().offset(x: 2, y: -2) }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Board Chat")
                            .appText(.headline)
                            .foregroundStyle(AppColors.text)
                        if let at = chat.latestGlobal?.createdAt {
                            Text(at, format: .relative(presentation: .named))
                                .appText(.caption)
                                .foregroundStyle(AppColors.subtext)
                        }
                    }
                    Text(preview)
                        .appText(.subheadline)
                        .foregroundStyle(chat.hasUnreadGlobal ? AppColors.text : AppColors.subtext)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.subtext)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 12)
            .homeCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chat.hasUnreadGlobal ? "Board Chat, new messages" : "Board Chat")
        .onAppear { chat.startLatestGlobal() }
        .onDisappear { chat.stopLatestGlobal() }
    }
}

/// Small accent dot for "new since you last looked".
struct UnreadDot: View {
    var body: some View {
        Circle()
            .fill(AppColors.accent)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(AppColors.bg, lineWidth: 2))
            .accessibilityHidden(true)
    }
}

/// Shown once at the top of the full leaderboard.
struct BoardChatIntroBanner: View {
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("New: Board Chat")
                    .appText(.headline)
                    .foregroundStyle(AppColors.text)
                Text("Talk with everyone on the leaderboard. Tag someone with their @username to let them know.")
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.lightTap()
                    onOpen()
                } label: {
                    Text("Open chat")
                        .appText(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.subtext)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(AppSpacing.md)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppColors.card))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.accent.opacity(0.3), lineWidth: 1)
        )
    }
}
