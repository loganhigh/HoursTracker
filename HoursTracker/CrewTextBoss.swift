import SwiftUI
import UIKit
import MessageUI
import ContactsUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Crew "Text your boss"
//
// After someone logs today's work shift in Add Shift, Messages opens with
// their boss and "Just leaving the yard now" already filled in; they tap Send.
// iOS never lets an app send a text on its own, so the tap is required.
//
// Crew only: the admin switches it on per user (users/{uid}.clockOutShortcut,
// server-written, blocked for clients in firestore.rules). The field name is
// left over from an earlier Shortcuts version; it is the same switch.

@MainActor
final class CrewFeatures {
    static let shared = CrewFeatures()
    static let enabledKey = "crew_clock_out_shortcut"

    private init() {}

    var textBossEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Reads the admin flag for the signed-in user and caches it. Signed out
    /// clears it; a failed read keeps the last known value.
    func refresh() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return
        }
        guard let snap = try? await Firestore.firestore().collection("users").document(uid).getDocument() else { return }
        UserDefaults.standard.set(snap.data()?["clockOutShortcut"] as? Bool ?? false, forKey: Self.enabledKey)
    }
}

enum CrewTextBoss {
    static let defaultMessage = "Just leaving the yard now"

    enum Key {
        static let on = "crew_text_boss_on_v1"
        static let phone = "crew_text_boss_phone_v1"
        static let name = "crew_text_boss_name_v1"
        static let message = "crew_text_boss_message_v1"
    }

    /// Ask only for a work shift dated today: back-filled or future shifts
    /// aren't "leaving the yard".
    static func shouldOffer(for saved: [WorkEntry], enabled: Bool, on: Bool, phone: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        enabled && on
            && !phone.trimmingCharacters(in: .whitespaces).isEmpty
            && saved.contains { !$0.isOffDay && calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// Opens Messages if this save qualifies; `then` runs once it closes
    /// (or right away when nothing was shown).
    @MainActor
    static func offerIfNeeded(after saved: [WorkEntry], then: @escaping () -> Void) {
        let d = UserDefaults.standard
        let phone = d.string(forKey: Key.phone) ?? ""
        guard shouldOffer(for: saved,
                          enabled: CrewFeatures.shared.textBossEnabled,
                          on: d.object(forKey: Key.on) as? Bool ?? true,
                          phone: phone),
              MFMessageComposeViewController.canSendText(),
              let presenter = UIApplication.topViewController() else {
            then()
            return
        }
        let message = (d.string(forKey: Key.message) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        MessageComposer.shared.present(
            from: presenter,
            to: phone,
            body: message.isEmpty ? defaultMessage : message,
            completion: then
        )
    }
}

/// Holds the composer's delegate while it's on screen.
@MainActor
final class MessageComposer: NSObject, MFMessageComposeViewControllerDelegate {
    static let shared = MessageComposer()
    private var completion: (() -> Void)?

    func present(from presenter: UIViewController, to phone: String, body: String, completion: @escaping () -> Void) {
        let vc = MFMessageComposeViewController()
        vc.recipients = [phone]
        vc.body = body
        vc.messageComposeDelegate = self
        self.completion = completion
        presenter.present(vc, animated: true)
    }

    nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        Task { @MainActor in
            controller.dismiss(animated: true) {
                let done = self.completion
                self.completion = nil
                done?()
            }
        }
    }
}

/// CNContactPickerViewController misbehaves inside a SwiftUI sheet, so it's
/// presented from the top view controller instead.
@MainActor
final class BossContactPicker: NSObject, CNContactPickerDelegate {
    static let shared = BossContactPicker()
    private var onPick: ((String, String) -> Void)?

    func present(onPick: @escaping (_ name: String, _ phone: String) -> Void) {
        guard let presenter = UIApplication.topViewController() else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        // One number: pick the contact. Several: the user picks the number.
        picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
        self.onPick = onPick
        presenter.present(picker, animated: true)
    }

    nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? phone
        Task { @MainActor in self.finish(name, phone) }
    }

    nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
        let phone = (contactProperty.value as? CNPhoneNumber)?.stringValue ?? ""
        let name = CNContactFormatter.string(from: contactProperty.contact, style: .fullName) ?? phone
        Task { @MainActor in self.finish(name, phone) }
    }

    nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        Task { @MainActor in self.onPick = nil }
    }

    private func finish(_ name: String, _ phone: String) {
        guard !phone.isEmpty else { return }
        onPick?(name, phone)
        onPick = nil
    }
}

extension UIApplication {
    static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

/// Settings → Text your boss. Only listed for crew the admin switched on.
struct CrewTextBossSettingsView: View {
    @AppStorage(CrewTextBoss.Key.on) private var on = true
    @AppStorage(CrewTextBoss.Key.phone) private var phone = ""
    @AppStorage(CrewTextBoss.Key.name) private var name = ""
    @AppStorage(CrewTextBoss.Key.message) private var message = CrewTextBoss.defaultMessage

    var body: some View {
        List {
            Section {
                Toggle(isOn: $on) {
                    SettingsRowLabel(icon: "message.fill", title: "Text after I log today's shift")
                }
                .tint(AppColors.accent)

                Button {
                    BossContactPicker.shared.present { pickedName, pickedPhone in
                        name = pickedName
                        phone = pickedPhone
                    }
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        SettingsRowLabel(
                            icon: "person.crop.circle.fill",
                            title: phone.isEmpty ? "Choose your boss" : name,
                            subtitle: phone.isEmpty ? "From your contacts" : phone
                        )
                        Spacer(minLength: AppSpacing.xs)
                        SettingsChevron()
                    }
                }
                .buttonStyle(.plain)
            } header: {
                SectionEyebrow("Text your boss")
            } footer: {
                Text("When you log a shift for today, Messages opens with your boss and this text filled in. Just tap Send.")
            }

            Section {
                TextField(CrewTextBoss.defaultMessage, text: $message, axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                SectionEyebrow("Message")
            }
        }
        .navigationTitle("Text your boss")
        .navigationBarTitleDisplayMode(.inline)
    }
}
