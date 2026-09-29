import FirebaseAuth
import FirebaseFirestore
import SwiftUI

/// "What should we add next?" box on Home, under Top 5 Hour Trackers.
/// Each idea is written to `featureSuggestions` (create-only for clients;
/// see firestore.rules) and pushed to the developer by
/// `notifyAdminOnSuggestion`.
struct FeatureSuggestionCard: View {
    var username: String?

    @State private var text = ""
    @State private var state: SendState = .idle
    @FocusState private var focused: Bool

    private enum SendState: Equatable { case idle, sending, sent, failed }

    static let maxLength = 500
    /// Minimum gap between sends from one device, so the box can't be
    /// used to flood the developer's notifications.
    private static let cooldown: TimeInterval = 60
    private static let lastSentKey = "feature_suggestion_last_sent_at"

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { trimmed.count >= 3 && state != .sending }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("WHAT SHOULD WE ADD NEXT?")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(AppTheme.Colors.subtext)
                Text("Your ideas shape Hour Tracker")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.faint)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                if state == .sent {
                    sentView
                } else {
                    editor
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.Colors.card.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
                    )
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("A feature, a fix, anything that would make the app better for you…")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.Colors.faint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.Colors.text)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(minHeight: 88, maxHeight: 140)
                    .onChange(of: text) { _, newValue in
                        if newValue.count > Self.maxLength { text = String(newValue.prefix(Self.maxLength)) }
                        if state == .failed { state = .idle }
                    }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.card2)
            )
            // A tap anywhere in the box starts typing, not just on the
            // first line of the editor.
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { focused = true }

            HStack {
                Text(state == .failed ? "Couldn't send — check your connection." : "\(text.count)/\(Self.maxLength)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(state == .failed ? AppColors.negative : AppTheme.Colors.faint)
                Spacer()
                Button(action: send) {
                    HStack(spacing: 6) {
                        if state == .sending {
                            ProgressView().controlSize(.small).tint(AppColors.textOnAccent)
                        }
                        Text("Send idea")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textOnAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(AppTheme.Colors.accent))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
            }
        }
    }

    private var sentView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.Colors.success)
            Text("Thanks — every idea gets read.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.text)
            Button("Send another") {
                text = ""
                state = .idle
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func send() {
        guard canSend, let uid = Auth.auth().currentUser?.uid else {
            state = .failed
            Haptics.error()
            return
        }
        let last = UserDefaults.standard.double(forKey: Self.lastSentKey)
        if last > 0, Date().timeIntervalSince1970 - last < Self.cooldown {
            // Treat a rapid resend as delivered rather than nagging.
            state = .sent
            return
        }
        focused = false
        state = .sending
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let data: [String: Any] = [
            "uid": uid,
            "username": String((username ?? "").prefix(40)),
            "text": trimmed,
            "appVersion": String(version.prefix(20)),
            "createdAt": FieldValue.serverTimestamp(),
        ]
        Task {
            do {
                try await Firestore.firestore().collection("featureSuggestions").addDocument(data: data)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSentKey)
                state = .sent
                Haptics.success()
            } catch {
                state = .failed
                Haptics.error()
            }
        }
    }
}
