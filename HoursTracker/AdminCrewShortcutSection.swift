import SwiftUI
import FirebaseFunctions

/// Edit-user sheet section: turns the crew-only "Text your boss" feature
/// on or off for this user. Applies immediately.
struct AdminCrewShortcutSection: View {
    let uid: String
    let passcode: String
    var onSaved: (Bool) -> Void = { _ in }

    @State private var enabled: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let functions = Functions.functions(region: "us-central1")

    init(uid: String, passcode: String, enabled: Bool, onSaved: @escaping (Bool) -> Void = { _ in }) {
        self.uid = uid
        self.passcode = passcode
        self.onSaved = onSaved
        _enabled = State(initialValue: enabled)
    }

    var body: some View {
        Section {
            Toggle("Text your boss", isOn: $enabled)
                .disabled(isSaving)
                .onChange(of: enabled) { old, new in
                    guard old != new else { return }
                    Task { await save(new) }
                }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.danger)
            }
        } header: {
            Text("Crew")
        } footer: {
            Text("Adds Settings → Text your boss. After they log today's shift, Messages opens with their boss and \"Just leaving the yard now\" filled in. Off for everyone else.")
        }
    }

    private func save(_ value: Bool) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await functions.httpsCallable("adminSetClockOutShortcut")
                .call(["passcode": passcode, "targetUid": uid, "enabled": value])
            Haptics.success()
            onSaved(value)
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
            enabled = !value
        }
    }
}
