import Foundation
import UIKit
import Combine
import UserNotifications
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

// MARK: - App delegate (APNs + FCM)

final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories([Self.chatReplyCategory])
        return true
    }

    /// "Reply" on @mention and direct-message pushes (the server sets the
    /// category). Answering doesn't open the app — and works from the Apple
    /// Watch too, since it mirrors the phone's notifications.
    static let chatReplyCategoryID = "CHAT_REPLY"
    static let chatReplyActionID = "CHAT_REPLY_ACTION"
    private static let chatReplyCategory = UNNotificationCategory(
        identifier: chatReplyCategoryID,
        actions: [UNTextInputNotificationAction(identifier: chatReplyActionID, title: "Reply",
                                                options: [], textInputButtonTitle: "Send",
                                                textInputPlaceholder: "Message")],
        intentIdentifiers: []
    )

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        Task { @MainActor in
            await PushNotificationService.shared.handleFCMToken(fcmToken)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if response.actionIdentifier == Self.chatReplyActionID,
           let reply = (response as? UNTextInputNotificationResponse)?.userText {
            let kind = userInfo["kind"] as? String
            let fromUid = userInfo["fromUid"] as? String
            let fromUsername = userInfo["fromUsername"] as? String ?? ""
            Task { @MainActor in
                let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    if kind == "directMessage", let fromUid {
                        _ = try? await ChatService.shared.sendDirect(text, toUid: fromUid, toUsername: fromUsername)
                    } else if kind == "chatMention" {
                        // Replying to a tag tags them back so they hear about it.
                        let tagged = fromUsername.isEmpty ? text : "@\(fromUsername) \(text)"
                        try? await ChatService.shared.sendGlobal(tagged)
                    }
                }
                completionHandler()
            }
            return
        }
        if let kind = userInfo["kind"] as? String, kind == "leaderboardRank" {
            Task { @MainActor in
                NotificationRouter.shared.openGlobalLeaderboard = true
            }
        }
        if let kind = userInfo["kind"] as? String, kind == "chatMention" || kind == "directMessage" {
            let fromUid = userInfo["fromUid"] as? String
            let title = response.notification.request.content.title
            Task { @MainActor in
                let router = NotificationRouter.shared
                if kind == "chatMention" {
                    router.openGlobalChat = true
                } else if let fromUid {
                    // The push title is the sender's "@handle".
                    let handle = title.hasPrefix("@") ? String(title.dropFirst()) : title
                    router.openDirectThread = DirectThreadTarget(otherUid: fromUid, otherUsername: handle)
                }
                router.openGlobalLeaderboard = true
            }
        }
        if let kind = userInfo["kind"] as? String, kind == "prestigeReady" {
            // "Level 25 complete" — the Prestige button is on the You tab.
            Task { @MainActor in
                NotificationRouter.shared.openYouTab = true
            }
        }
        if let kind = userInfo["kind"] as? String, kind == "appUpdate" {
            // "New Update Available!" — straight to the App Store listing.
            Task { @MainActor in
                AppActions.openAppStoreListing()
            }
        }
        completionHandler()
    }
}

// MARK: - Notification routing

/// Where a tapped push should land. Views observe and consume the flags; the
/// delegate above only ever raises them.
@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()
    /// Raised by a leaderboard-rank push; HoursHomeView presents the global
    /// board and lowers it.
    @Published var openGlobalLeaderboard = false
    /// Raised with the board by a chat-mention push; the board opens the chat.
    @Published var openGlobalChat = false
    /// Set with the board by a direct-message push; the board opens the thread.
    @Published var openDirectThread: DirectThreadTarget?
    /// Raised by a "you can Prestige" push; AppTabView selects the You tab
    /// (where the Prestige button lives) and lowers it.
    @Published var openYouTab = false
    private init() {}
}

// MARK: - Push notification service

@MainActor
final class PushNotificationService {
    static let shared = PushNotificationService()

    private lazy var db = Firestore.firestore()
    private var configured = false

    private var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
    }

    private init() {}

    /// Call after Firebase is configured and the user may be signed in.
    func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        Task { await registerForPushIfSignedIn() }
    }

    func registerForPushIfSignedIn() async {
        guard Auth.auth().currentUser != nil else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }

        let granted = await NotificationManager.shared.requestPermission()
        guard granted else { return }

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }

        if let token = Messaging.messaging().fcmToken {
            await handleFCMToken(token)
        }
    }

    func handleFCMToken(_ token: String) async {
        await uploadToken(token)
    }

    func syncAlertPreferenceToCloud() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).setData([
                "friendShiftAlerts": SmartNotifier.shared.friendShiftNotificationsEnabled,
                "leaderboardAlerts": SmartNotifier.shared.leaderboardAlertsEnabled,
                "pushSettingsUpdatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            #if DEBUG
            print("PushNotificationService.syncAlertPreference error: \(error.localizedDescription)")
            #endif
        }
    }

    func clearTokenOnSignOut(uid: String) async {
        do {
            try await db.collection("users").document(uid)
                .collection("deviceTokens").document(deviceId)
                .delete()
            // Legacy field cleanup for older app versions.
            try await db.collection("users").document(uid).updateData([
                "fcmTokens.\(deviceId)": FieldValue.delete()
            ])
        } catch {
            #if DEBUG
            print("PushNotificationService.clearToken error: \(error.localizedDescription)")
            #endif
        }
    }

    private func uploadToken(_ token: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid)
                .collection("deviceTokens").document(deviceId)
                .setData([
                    "token": token,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            // Alert preferences are written ONLY when the user flips a toggle
            // (syncAlertPreferenceToCloud). This used to push this device's
            // local values on every foreground, so merely opening the app on
            // a second device (or reinstalling) silently re-enabled alerts the
            // user had turned off elsewhere. Adopt the cloud values instead.
            if let data = try? await db.collection("users").document(uid).getDocument().data() {
                SmartNotifier.shared.adoptCloudAlertPreferences(
                    friendShift: data["friendShiftAlerts"] as? Bool,
                    leaderboard: data["leaderboardAlerts"] as? Bool
                )
            }
            #if DEBUG
            print("FCM token synced for device \(deviceId.prefix(8))…")
            #endif
        } catch {
            #if DEBUG
            print("PushNotificationService.uploadToken error: \(error.localizedDescription)")
            #endif
        }
    }
}
