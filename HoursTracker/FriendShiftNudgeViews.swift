import SwiftUI

// MARK: - Nudge button (beside friend name)

struct FriendShiftNudgeButton: View {
    let friendUid: String
    let isSending: Bool
    let didSend: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isSending {
                    ProgressView()
                        .scaleEffect(0.75)
                } else if didSend {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(AppTheme.Colors.accent)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(didSend ? "Reminder sent" : "Remind to log shifts")
    }
}

// MARK: - Emoji response sheet (recipient)

struct FriendShiftNudgeResponseSheet: View {
    let nudge: FriendShiftNudge
    let onRespond: (String) async -> Bool
    let onDismiss: () -> Void

    @State private var selectedEmoji: String?
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text("Shift reminder")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.faint)
                        .tracking(0.8)

                    Text("\(nudge.fromName) nudged you")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.text)
                        .multilineTextAlignment(.center)

                    Text("Don't forget to log your shifts!")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                Text("Tap an emoji to respond")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.subtext)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                    ForEach(FriendShiftNudgeService.responseEmojis, id: \.self) { emoji in
                        Button {
                            respond(with: emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 36))
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(selectedEmoji == emoji
                                              ? AppTheme.Colors.accent.opacity(0.25)
                                              : AppTheme.Colors.card2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(
                                            selectedEmoji == emoji
                                                ? AppTheme.Colors.accent.opacity(0.6)
                                                : AppTheme.Colors.stroke,
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(ReactionPopButtonStyle())
                        .disabled(isSending)
                    }
                }
                .padding(.horizontal, 8)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") {
                        onDismiss()
                    }
                    .disabled(isSending)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func respond(with emoji: String) {
        guard !isSending else { return }
        isSending = true
        selectedEmoji = emoji
        Haptics.lightTap()
        Task {
            let success = await onRespond(emoji)
            if !success {
                isSending = false
                selectedEmoji = nil
            }
        }
    }
}

// MARK: - App-wide nudge listener + response sheet

private struct FriendShiftNudgeHost: ViewModifier {
    @ObservedObject private var nudgeService = FriendShiftNudgeService.shared
    @EnvironmentObject private var authService: AuthService
    @State private var showingNudgeResponse = false

    func body(content: Content) -> some View {
        content
            .onAppear { syncListening() }
            .onChange(of: authService.user?.uid) { _, _ in syncListening() }
            .onChange(of: nudgeService.pendingNudge?.id) { _, newId in
                showingNudgeResponse = newId != nil
            }
            .sheet(isPresented: $showingNudgeResponse) {
                if let nudge = nudgeService.pendingNudge {
                    FriendShiftNudgeResponseSheet(
                        nudge: nudge,
                        onRespond: { emoji in
                            await respond(to: nudge, emoji: emoji)
                        },
                        onDismiss: {
                            showingNudgeResponse = false
                            nudgeService.dismissPendingNudge()
                        }
                    )
                }
            }
    }

    private func syncListening() {
        if let uid = authService.user?.uid {
            nudgeService.startListening(uid: uid)
        } else {
            nudgeService.stopListening()
        }
    }

    private func respond(to nudge: FriendShiftNudge, emoji: String) async -> Bool {
        guard let uid = authService.user?.uid else { return false }
        do {
            try await nudgeService.respond(to: nudge, emoji: emoji, myUid: uid)
            Haptics.success()
            showingNudgeResponse = false
            return true
        } catch {
            Haptics.error()
            return false
        }
    }
}

extension View {
    func friendShiftNudgeHost() -> some View {
        modifier(FriendShiftNudgeHost())
    }
}
