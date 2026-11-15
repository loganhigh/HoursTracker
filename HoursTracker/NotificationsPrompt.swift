import SwiftUI
import UIKit
import UserNotifications
import Combine

// MARK: - Notifications ask
//
// Apple shows its "Allow notifications?" alert once per install. It used to
// fire cold right after sign-in, so many people declined it, and a declined
// install gets nothing, update pushes included. Now:
// - Onboarding has a page that explains what they'll get before the alert.
// - Home asks again (at most every 14 days) when notifications are off: the
//   alert if iOS hasn't asked yet, otherwise Hour Tracker's page in Settings.

enum NotificationAskPolicy {
    static let gap: TimeInterval = 14 * 86_400

    static func isOff(_ status: UNAuthorizationStatus) -> Bool {
        status == .denied || status == .notDetermined
    }

    static func shouldAsk(status: UNAuthorizationStatus, lastAskAt: Date?, now: Date) -> Bool {
        guard isOff(status) else { return false }
        guard let lastAskAt else { return true }
        return now.timeIntervalSince(lastAskAt) >= gap
    }
}

@MainActor
final class NotificationPromptCenter: ObservableObject {
    static let shared = NotificationPromptCenter()
    static let lastAskKey = "notifications_ask_last_v1"

    /// Non-nil while the Home card is up: the status it was shown for.
    @Published private(set) var pending: UNAuthorizationStatus?
    /// Sent to Settings: register on the way back if they switched it on.
    private var awaitingSettings = false

    private init() {}

    static var lastAskAt: Date? {
        let ts = UserDefaults.standard.double(forKey: lastAskKey)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    static func stampAsked(_ now: Date = Date()) {
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastAskKey)
    }

    func considerAsking() async {
        guard pending == nil else { return }
        let status = await NotificationManager.shared.authorizationStatus()
        // Never asked before: Apple's own alert is showing at launch right
        // now (registerForPushIfSignedIn), so don't stack a card on it.
        if status == .notDetermined && Self.lastAskAt == nil {
            Self.stampAsked()
            return
        }
        guard NotificationAskPolicy.shouldAsk(status: status, lastAskAt: Self.lastAskAt, now: Date()) else { return }
        Self.stampAsked()
        withAnimation(.easeOut(duration: 0.2)) { pending = status }
    }

    func turnOn() {
        let status = pending
        close()
        if status == .notDetermined {
            Task { await PushNotificationService.shared.registerForPushIfSignedIn(userAsked: true) }
        } else {
            awaitingSettings = true
            AppActions.openNotificationSettings()
        }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.2)) { pending = nil }
    }

    /// Call when the app becomes active.
    func didBecomeActive() {
        guard awaitingSettings else { return }
        awaitingSettings = false
        Task {
            guard await NotificationManager.shared.hasPermission() else { return }
            await PushNotificationService.shared.registerForPushIfSignedIn()
        }
    }
}

extension AppActions {
    /// Hour Tracker's notification settings (falls back to its Settings page).
    static func openNotificationSettings() {
        let url = URL(string: UIApplication.openNotificationSettingsURLString)
            ?? URL(string: UIApplication.openSettingsURLString)
        if let url { UIApplication.shared.open(url) }
    }
}

struct NotificationsAskOverlay: View {
    let status: UNAuthorizationStatus
    @ObservedObject var center: NotificationPromptCenter

    var body: some View {
        HomePromptCard(
            pose: .bell,
            title: "Turn on notifications?",
            message: status == .denied
                ? "Notifications are off for Hour Tracker, so you're missing friends' shifts, Board Chat mentions and new updates. Switch on Allow Notifications in Settings."
                : "Know when friends log a shift, when someone mentions you in Board Chat, and when a new update is out."
        ) {
            Button(status == .denied ? "Open Settings" : "Turn on") {
                Haptics.lightTap()
                center.turnOn()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, AppSpacing.xxs)

            Button("Not Now") {
                Haptics.lightTap()
                center.close()
            }
            .font(AppTypography.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.subtext)
        }
    }
}

/// Last onboarding page, after "Start your shift when you get to work".
struct OnboardingNotificationsPage: View {
    let minHeight: CGFloat
    let onContinue: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var asking = false

    private var isOn: Bool { !NotificationAskPolicy.isOff(status) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: AppSpacing.lg) {
                    OnboardingHeader(
                        pose: .bell,
                        title: "Don't miss a thing",
                        subline: "Turn on notifications so you hear about it when something happens."
                    )

                    VStack(spacing: AppSpacing.sm) {
                        bullet("person.2.fill", "When friends log a shift or pass you on the board.")
                        bullet("bubble.left.and.bubble.right.fill", "When someone mentions you in Board Chat.")
                        bullet("sparkles", "When a new update is out.")
                    }
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity)
                    .onboardingFormCard()

                    if isOn {
                        Label("Notifications are on", systemImage: "checkmark.circle.fill")
                            .appText(.subheadline)
                            .foregroundStyle(AppColors.positive)
                        Button("Continue", action: onContinue)
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button(status == .denied ? "Turn on in Settings" : "Turn on notifications") {
                            Haptics.lightTap()
                            turnOn()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(asking)

                        Button("Maybe later") {
                            NotificationPromptCenter.stampAsked()
                            onContinue()
                        }
                        .appText(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.subtext)
                    }
                }
                .padding(.horizontal, AppSpacing.xl)

                Spacer(minLength: 0)
            }
            .frame(minHeight: minHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private func refresh() async {
        status = await NotificationManager.shared.authorizationStatus()
    }

    private func turnOn() {
        NotificationPromptCenter.stampAsked()
        guard status == .notDetermined else {
            AppActions.openNotificationSettings()
            return
        }
        asking = true
        Task {
            // Signed in by now (sign-in comes before this page): ask and
            // register the device in one go.
            await PushNotificationService.shared.registerForPushIfSignedIn(userAsked: true)
            await refresh()
            asking = false
            if isOn {
                Haptics.success()
                try? await Task.sleep(nanoseconds: 500_000_000)
                onContinue()
            }
        }
    }

    /// Icon inline with the text so each line centers as one unit.
    private func bullet(_ icon: String, _ text: String) -> some View {
        (Text(Image(systemName: icon)).foregroundStyle(AppColors.accent) + Text("  ") + Text(text))
            .appText(.subheadline)
            .foregroundStyle(AppColors.text)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}
