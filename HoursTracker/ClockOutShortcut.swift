import AppIntents
import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Crew "Clock Out" shortcut
//
// A Shortcuts action that ends the running live shift right now, so a
// personal shortcut can clock out and then text the boss ("Just leaving the
// yard now") in one go, or run on a "Leave the yard" automation.
//
// Crew only: the admin switches it on per user (users/{uid}.clockOutShortcut,
// server-written, blocked for clients in firestore.rules). Anyone can see the
// action in the Shortcuts app (iOS has no per-user way to hide it), but it
// does nothing unless their account has it turned on. It never stops the
// shortcut, so the text that follows it still sends.

@MainActor
final class CrewFeatures {
    static let shared = CrewFeatures()
    private static let clockOutKey = "crew_clock_out_shortcut"

    private init() {}

    var clockOutShortcutEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.clockOutKey)
    }

    /// Reads the admin flag for the signed-in user and caches it. Signed out
    /// clears it; a failed read keeps the last known value.
    func refresh() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            UserDefaults.standard.set(false, forKey: Self.clockOutKey)
            return
        }
        guard let snap = try? await Firestore.firestore().collection("users").document(uid).getDocument() else { return }
        UserDefaults.standard.set(snap.data()?["clockOutShortcut"] as? Bool ?? false, forKey: Self.clockOutKey)
    }
}

struct ClockOutIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock Out"
    static var description = IntentDescription("Ends your live shift in Hour Tracker now. Crew feature: only works when it's turned on for your account.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await CrewFeatures.shared.refresh()
        guard CrewFeatures.shared.clockOutShortcutEnabled else {
            return .result(dialog: "Clock Out isn't turned on for your account.")
        }
        guard let store = HoursStore.current else {
            return .result(dialog: "Open Hour Tracker once, then try again.")
        }
        let live = LiveShiftManager.shared
        guard live.activeShift != nil else {
            return .result(dialog: "You're not clocked in.")
        }
        guard let entry = live.clockOut(at: Date(), into: store) else {
            return .result(dialog: "Couldn't clock out. Open Hour Tracker to finish your shift.")
        }
        return .result(dialog: "Clocked out. \(AppTheme.Format.hours(entry.paidHours)) logged.")
    }
}
