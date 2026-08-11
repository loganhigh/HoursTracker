import SwiftUI

// MARK: - Nudge button (friend profile)

/// Quiet full-width "Nudge" entry point on a friend's profile. The sending /
/// cooldown logic lives in `FriendShiftNudgeService`; this is presentation only.
struct FriendShiftNudgeButton: View {
    let friendUid: String
    let isSending: Bool
    let didSend: Bool
    var tint: Color = AppTheme.Colors.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView()
                        .tint(tint)
                } else if didSend {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Image(systemName: "hand.wave")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(didSend ? "Nudge sent" : "Nudge")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(didSend ? AppTheme.Colors.success : tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(tint.opacity(0.25), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSending || didSend)
        .accessibilityLabel(didSend ? "Reminder sent" : "Remind to log shifts")
    }
}

// MARK: - Nudge picker (sender)

/// Sheet the sender picks a nudge from. Grouped by tone so encouragement and
/// trash talk read as two deliberate choices rather than one long list.
struct FriendShiftNudgePicker: View {
    let friendName: String
    let isSending: Bool
    let onPick: (NudgeKind) -> Void
    let onCancel: () -> Void

    @State private var pickedID: String?

    private var firstName: String {
        friendName.split(separator: " ").first.map(String.init) ?? friendName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(NudgeKind.Tone.allCases, id: \.self) { tone in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tone.sectionTitle)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.faint)
                                .tracking(0.8)

                            ForEach(NudgeKind.kinds(tone: tone)) { kind in
                                nudgeRow(kind)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("Nudge \(firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .disabled(isSending)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func nudgeRow(_ kind: NudgeKind) -> some View {
        Button {
            guard !isSending else { return }
            pickedID = kind.id
            Haptics.lightTap()
            onPick(kind)
        } label: {
            HStack(spacing: 14) {
                Text(kind.emoji)
                    .font(.system(size: 26))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(AppTheme.Colors.card2)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.text)
                    // Show exactly what they'll receive, with their name in it.
                    Text(kind.message(recipientFirstName: firstName))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if isSending && pickedID == kind.id {
                    ProgressView().tint(AppTheme.Colors.accent)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppTheme.Colors.card.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ReactionPopButtonStyle())
        .disabled(isSending)
    }
}

// MARK: - Emoji response sheet (recipient)

struct FriendShiftNudgeResponseSheet: View {
    let nudge: FriendShiftNudge
    let onRespond: (String) async -> Bool
    let onNudgeBack: () -> Void
    let onDismiss: () -> Void

    @State private var selectedEmoji: String?
    @State private var isSending = false

    /// The sheet renders the same message the push did, so opening the app
    /// shows what they were actually sent rather than a generic restatement.
    private var myFirstName: String {
        let full = UserDefaults.standard.string(forKey: "profile_display_name") ?? ""
        return full.split(separator: " ").first.map(String.init) ?? ""
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text(nudge.kind.emoji)
                        .font(.system(size: 44))

                    Text("\(nudge.fromName) nudged you")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.text)
                        .multilineTextAlignment(.center)

                    Text(nudge.kind.message(recipientFirstName: myFirstName))
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

                // Returning fire is the point — without this the exchange ends
                // at one emoji. Sends bypass the daily cooldown (see
                // FriendShiftNudgeService.sendNudge) so the volley can happen.
                Button {
                    Haptics.lightTap()
                    onNudgeBack()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Nudge \(nudge.fromName.split(separator: " ").first.map(String.init) ?? nudge.fromName) back")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(AppTheme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(AppTheme.Colors.accent.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                    .stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSending)

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
        // Expandable: the nudge-back button pushes the emoji grid close to the
        // bottom of a medium detent on shorter devices.
        .presentationDetents([.medium, .large])
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
    /// Set while the response sheet is closing, then promoted to
    /// `nudgeBackTarget` in its `onDismiss`. Presenting the picker before the
    /// first sheet finishes dismissing drops it silently.
    @State private var queuedNudgeBack: FriendShiftNudge?
    @State private var nudgeBackTarget: FriendShiftNudge?
    @State private var isSendingNudgeBack = false

    func body(content: Content) -> some View {
        content
            .onAppear { syncListening() }
            .onChange(of: authService.user?.uid) { _, _ in syncListening() }
            .onChange(of: nudgeService.pendingNudge?.id) { _, newId in
                showingNudgeResponse = newId != nil
            }
            .sheet(isPresented: $showingNudgeResponse, onDismiss: {
                if let queued = queuedNudgeBack {
                    queuedNudgeBack = nil
                    nudgeBackTarget = queued
                }
            }) {
                if let nudge = nudgeService.pendingNudge {
                    FriendShiftNudgeResponseSheet(
                        nudge: nudge,
                        onRespond: { emoji in
                            await respond(to: nudge, emoji: emoji)
                        },
                        onNudgeBack: {
                            queuedNudgeBack = nudge
                            showingNudgeResponse = false
                            nudgeService.dismissPendingNudge()
                        },
                        onDismiss: {
                            showingNudgeResponse = false
                            nudgeService.dismissPendingNudge()
                        }
                    )
                }
            }
            .sheet(item: $nudgeBackTarget) { nudge in
                FriendShiftNudgePicker(
                    friendName: nudge.fromName,
                    isSending: isSendingNudgeBack,
                    onPick: { kind in sendNudgeBack(to: nudge, kind: kind) },
                    onCancel: { nudgeBackTarget = nil }
                )
            }
    }

    private func sendNudgeBack(to nudge: FriendShiftNudge, kind: NudgeKind) {
        guard let uid = authService.user?.uid, !isSendingNudgeBack else { return }
        isSendingNudgeBack = true
        Task {
            defer { isSendingNudgeBack = false }
            do {
                try await nudgeService.sendNudge(
                    to: nudge.fromUid,
                    myUid: uid,
                    myName: UserDefaults.standard.string(forKey: "profile_display_name") ?? "",
                    kind: kind,
                    // They nudged first; the daily cooldown must not eat the reply.
                    bypassCooldown: true
                )
                Haptics.success()
            } catch {
                Haptics.error()
            }
            nudgeBackTarget = nil
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
