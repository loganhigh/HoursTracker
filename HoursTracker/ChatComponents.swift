import SwiftUI

// MARK: - Shared chat pieces
//
// The composer (with @-tag suggestions), message text with highlighted
// tags, and the report flow — used by the board chat and direct messages.

enum ChatFormat {
    /// The text with every @username in the accent colour and bold, and the
    /// viewer's own handle highlighted harder.
    static func attributed(_ text: String, myUsername: String?) -> AttributedString {
        var result = AttributedString(text)
        guard let regex = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_])@[A-Za-z][A-Za-z0-9_]{2,19}") else { return result }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let swiftRange = Range(match.range, in: text),
                  let lower = AttributedString.Index(swiftRange.lowerBound, within: result),
                  let upper = AttributedString.Index(swiftRange.upperBound, within: result) else { continue }
            let handle = String(text[swiftRange].dropFirst()).lowercased()
            let isMe = handle == myUsername?.lowercased()
            result[lower..<upper].foregroundColor = isMe ? AppColors.gold : AppColors.accent
            result[lower..<upper].font = .body.weight(.semibold)
        }
        return result
    }

    static func time(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Text field plus send button. While the last word starts with "@" it
/// offers matching usernames to tag.
struct ChatComposer: View {
    @Binding var text: String
    let placeholder: String
    /// Usernames worth suggesting (people on the board, recent chatters).
    var suggestions: [String] = []
    var isSending: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    private var partialTag: String? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
              last.hasPrefix("@") else { return nil }
        return String(last.dropFirst()).lowercased()
    }

    private var matches: [String] {
        guard let partial = partialTag else { return [] }
        return suggestions
            .filter { partial.isEmpty || $0.lowercased().hasPrefix(partial) }
            .filter { $0.lowercased() != partial }
            .prefix(8)
            .map { $0 }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        VStack(spacing: 6) {
            if !matches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(matches, id: \.self) { name in
                            Button {
                                complete(with: name)
                            } label: {
                                Text("@\(name)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppColors.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(AppColors.accentMuted))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                }
            }

            HStack(alignment: .bottom, spacing: AppSpacing.xs) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused(isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AppColors.card)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(AppColors.stroke, lineWidth: 0.5))
                    )
                    .onChange(of: text) { _, new in
                        if new.count > 500 { text = String(new.prefix(500)) }
                    }

                Button {
                    Haptics.lightTap()
                    onSend()
                } label: {
                    ZStack {
                        Circle().fill(canSend ? AppColors.accent : AppColors.card2)
                        if isSending {
                            ProgressView().tint(AppColors.textOnAccent)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(canSend ? AppColors.textOnAccent : AppColors.faint)
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, AppSpacing.md)
        }
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.bg.opacity(0.96))
    }

    private func complete(with name: String) {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if !words.isEmpty { words.removeLast() }
        words.append("@\(name) ")
        text = words.joined(separator: " ")
        Haptics.lightTap()
    }
}

/// Who and what is being reported, for the reason picker.
struct ChatReportTarget: Identifiable {
    let id = UUID()
    let uid: String
    let username: String
    let text: String
    var messageId: String? = nil
    var threadId: String? = nil
}

extension View {
    /// Reason picker for a report; sending it also offers to block.
    func chatReportDialog(_ target: Binding<ChatReportTarget?>, onReported: @escaping () -> Void = {}) -> some View {
        confirmationDialog(
            "Report @\(target.wrappedValue?.username ?? "")",
            isPresented: Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: target.wrappedValue
        ) { report in
            ForEach(ChatService.reportReasons, id: \.self) { reason in
                Button(reason) {
                    Task {
                        await ChatService.shared.report(
                            uid: report.uid, username: report.username, text: report.text, reason: reason,
                            messageId: report.messageId, threadId: report.threadId
                        )
                        Haptics.success()
                        onReported()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Reports go to the Hour Tracker team. You can also block them so you won't see their messages.")
        }
    }
}
