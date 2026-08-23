import SwiftUI

/// Pick or change the username. One sheet, two entrances: the first-time
/// prompt existing accounts see after updating (pre-filled from their name,
/// dismissable with "Later"), and the Account screen editor.
struct UsernameSheet: View {
    enum Mode { case firstTime, edit }

    let mode: Mode
    let currentUsername: String?
    let suggestedFrom: String
    @ObservedObject var friendsService: FriendsService
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var availability: Availability = .idle
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var checkTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    private enum Availability: Equatable {
        case idle, checking, available, taken, invalid(String)
    }

    private var canonical: String { Username.normalize(draft) }
    private var isUnchanged: Bool { canonical == currentUsername }
    private var canSave: Bool {
        !isSaving && !isUnchanged && availability == .available
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.lg) {
                VStack(spacing: AppSpacing.sm) {
                    Text(mode == .firstTime ? "Pick your username" : "Change your username")
                        .appText(.title)
                        .foregroundStyle(AppColors.text)
                        .multilineTextAlignment(.center)
                    Text("Friends add you by your username. It's shown on the global leaderboard; your friends see your name.")
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppSpacing.xl)

                HStack(spacing: 2) {
                    Text("@")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(AppColors.subtext)
                    TextField("username", text: $draft)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .focused($fieldFocused)
                        .onSubmit { if canSave { save() } }
                        .onChange(of: draft) { _, _ in
                            // Never rewritten while typing (any rewrite drops
                            // keystrokes under fast input); the status line
                            // explains bad characters instead.
                            scheduleAvailabilityCheck()
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .fill(AppColors.card2.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                .stroke(AppColors.stroke.opacity(0.5), lineWidth: 1)
                        )
                )
                .padding(.horizontal, AppSpacing.xl)

                statusLine
                    .padding(.horizontal, AppSpacing.xl)

                Spacer(minLength: 0)
            }
            .padding(.top, AppSpacing.xl)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle(mode == .firstTime ? "" : "Username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mode == .firstTime ? "Later" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(mode == .firstTime ? "Claim" : "Save") { save() }
                            .fontWeight(.bold)
                            .disabled(!canSave)
                    }
                }
            }
            .onAppear {
                draft = currentUsername ?? Username.suggestion(from: suggestedFrom)
                fieldFocused = true
                scheduleAvailabilityCheck()
            }
            .onDisappear { checkTask?.cancel() }
        }
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let errorMessage {
            Text(errorMessage)
                .appText(.caption)
                .foregroundStyle(AppColors.negative)
                .multilineTextAlignment(.center)
        } else {
            switch availability {
            case .idle:
                Text(" ").appText(.caption)
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").appText(.caption).foregroundStyle(AppColors.subtext)
                }
            case .available:
                Label(isUnchanged ? "That's your current username" : "\(Username.display(canonical)) is available",
                      systemImage: "checkmark.circle.fill")
                    .appText(.caption)
                    .foregroundStyle(isUnchanged ? AppColors.subtext : AppColors.positive)
            case .taken:
                Label("\(Username.display(canonical)) is taken", systemImage: "xmark.circle.fill")
                    .appText(.caption)
                    .foregroundStyle(AppColors.negative)
            case .invalid(let reason):
                Text(reason)
                    .appText(.caption)
                    .foregroundStyle(AppColors.negative)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Format problems show instantly; the network check is debounced so a
    /// fast typist doesn't fire a read per keystroke.
    private func scheduleAvailabilityCheck() {
        errorMessage = nil
        checkTask?.cancel()
        let name = canonical
        if let problem = Username.problem(with: name) {
            availability = name.isEmpty ? .idle : .invalid(problem)
            return
        }
        if name == currentUsername {
            availability = .available
            return
        }
        availability = .checking
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let free = await friendsService.isUsernameAvailable(name)
            guard !Task.isCancelled, canonical == name else { return }
            availability = free ? .available : .taken
        }
    }

    private func save() {
        let name = canonical
        guard canSave else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await friendsService.claimUsername(name)
                Haptics.success()
                dismiss()
            } catch {
                Haptics.error()
                errorMessage = (error as? FriendsError)?.errorDescription ?? error.localizedDescription
                if case .usernameTaken = error as? FriendsError { availability = .taken }
            }
        }
    }
}
