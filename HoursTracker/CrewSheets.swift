import SwiftUI

// MARK: - Teams (crews) sheets — slice 1
//
// Same grouped-list language as the rest of Settings: quiet card rows,
// centered eyebrow headers, icon squares. Errors surface as a quiet inline
// caption under the action button (never a disruptive alert) — same
// treatment as FriendsView's add-by-code flow.

// MARK: - Create a Crew

struct CreateCrewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var crewService = CrewService.shared

    @State private var name = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var createdCrew: MyCrew?
    @State private var copyConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                if let createdCrew {
                    successSection(for: createdCrew)
                } else {
                    formSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Create a Crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(createdCrew == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    private var formSection: some View {
        Section {
            TextField("Crew name", text: $name)
                .textInputAutocapitalization(.words)
                .onChange(of: name) { _, newValue in
                    if newValue.count > 60 { name = String(newValue.prefix(60)) }
                }

            Button {
                Task { await create() }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    if isCreating {
                        ProgressView().controlSize(.small)
                    }
                    Text(isCreating ? "Creating…" : "Create")
                        .appText(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)

            if let errorMessage {
                Text(errorMessage)
                    .appText(.caption)
                    .foregroundStyle(AppColors.negative)
            }
        } header: {
            SectionEyebrow("Crew Name")
        } footer: {
            Text("You'll be the crew's manager. Share the invite code with your team once it's created.")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
        }
        .listRowBackground(AppColors.card.opacity(0.55))
        .listRowSeparatorTint(AppColors.stroke)
    }

    private func successSection(for crew: MyCrew) -> some View {
        Section {
            VStack(spacing: AppSpacing.md) {
                VStack(spacing: AppSpacing.xs) {
                    Text(crew.name)
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                        .multilineTextAlignment(.center)
                    Text("Crew created")
                        .appText(.caption)
                        .foregroundStyle(AppColors.positive)
                }

                if let code = crew.inviteCode {
                    VStack(spacing: AppSpacing.xs) {
                        Text("Invite Code")
                            .appText(.eyebrow)
                            .foregroundStyle(AppColors.subtext)

                        Button {
                            copyCode(code)
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Text(code)
                                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                                    .foregroundStyle(AppColors.text)
                                    .monospacedDigit()
                                Image(systemName: copyConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                                    .foregroundStyle(copyConfirmation ? AppColors.positive : AppColors.accent)
                            }
                        }
                        .buttonStyle(.plain)

                        Text(copyConfirmation ? "Copied to clipboard" : "Tap to copy")
                            .appText(.caption)
                            .foregroundStyle(copyConfirmation ? AppColors.positive : AppColors.faint)
                    }

                    if let url = CrewService.inviteURL(code: code) {
                        ShareLink(item: url) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share invite link")
                                    .appText(.headline)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
        }
        .listRowBackground(AppColors.card.opacity(0.55))
        .listRowSeparatorTint(AppColors.stroke)
    }

    private func copyCode(_ code: String) {
        UIPasteboard.general.string = code
        Haptics.lightTap()
        withAnimation(AppMotion.animation(AppMotion.Spring.snappy, reduceMotion: reduceMotion)) {
            copyConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.25)) { copyConfirmation = false }
        }
    }

    private func create() async {
        errorMessage = nil
        isCreating = true
        defer { isCreating = false }
        do {
            let crew = try await crewService.createCrew(name: name)
            Haptics.success()
            withAnimation(AppMotion.animation(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
                createdCrew = crew
            }
        } catch {
            Haptics.error()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Join a Crew

struct JoinCrewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var crewService = CrewService.shared

    @State private var code: String
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var joinedCrew: MyCrew?

    init(initialCode: String = "") {
        _code = State(initialValue: initialCode)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let joinedCrew {
                    successSection(for: joinedCrew)
                } else {
                    formSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Join a Crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(joinedCrew == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    private var formSection: some View {
        Section {
            TextField("6-character code", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .onChange(of: code) { _, newValue in
                    let sanitized = newValue.uppercased().filter { $0.isLetter || $0.isNumber }
                    if sanitized != newValue || sanitized.count > 6 {
                        code = String(sanitized.prefix(6))
                    }
                }

            Button {
                Task { await join() }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    if isJoining {
                        ProgressView().controlSize(.small)
                    }
                    Text(isJoining ? "Joining…" : "Join")
                        .appText(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(code.count != 6 || isJoining)

            if let errorMessage {
                Text(errorMessage)
                    .appText(.caption)
                    .foregroundStyle(AppColors.negative)
            }
        } header: {
            SectionEyebrow("Invite Code")
        } footer: {
            Text("Ask your crew manager for the 6-character invite code, or open the link they shared.")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
        }
        .listRowBackground(AppColors.card.opacity(0.55))
        .listRowSeparatorTint(AppColors.stroke)
    }

    private func successSection(for crew: MyCrew) -> some View {
        Section {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(AppColors.positive)
                Text("You joined \(crew.name)")
                    .appText(.headline)
                    .foregroundStyle(AppColors.text)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
        }
        .listRowBackground(AppColors.card.opacity(0.55))
        .listRowSeparatorTint(AppColors.stroke)
    }

    private func join() async {
        errorMessage = nil
        isJoining = true
        defer { isJoining = false }
        do {
            let crew = try await crewService.joinCrew(code: code)
            Haptics.success()
            withAnimation(AppMotion.animation(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
                joinedCrew = crew
            }
        } catch {
            Haptics.error()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
