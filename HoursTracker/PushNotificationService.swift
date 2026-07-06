import Foundation
import UIKit
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
        return true
    }

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
            try await db.collection("users").document(uid).setData([
                "friendShiftAlerts": SmartNotifier.shared.friendShiftNotificationsEnabled,
                "pushSettingsUpdatedAt": FieldValue.serverTimestamp()
            ], merge: true)
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
