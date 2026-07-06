import SwiftUI
import Combine
import os

/// Resets transient state and forces full UI rebuild when app backgrounds/foregrounds.
/// Ensures every foreground entry feels like a clean reboot.
@MainActor
final class AppSessionManager: ObservableObject {
    @Published private(set) var rootResetToken: UUID = UUID()

    private let store: HoursStore
    private let startupCoordinator: StartupCoordinator

    /// Track load task for cancellation on reset
    private var currentLoadTask: Task<Void, Never>?

    /// Debounce rapid background/foreground switches
    private var lastResetTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 1.5

    init(store: HoursStore, startupCoordinator: StartupCoordinator) {
        self.store = store
        self.startupCoordinator = startupCoordinator
    }

    /// Call when app goes to background. Cancels in-flight tasks only. No full UI teardown to avoid freezing/jank.
    func resetSession(reason: ResetReason) {
        let now = Date()
        guard now.timeIntervalSince(lastResetTime) >= debounceInterval else { return }
        lastResetTime = now

        currentLoadTask?.cancel()
        currentLoadTask = nil
        startupCoordinator.cancelLoad()

        // Do NOT reset rootResetToken or startupCoordinator.state — tearing down the whole UI on every
        // background causes freezing and splash on return. User sees content immediately when coming back.
        AppLogger.lifecycle.info("Session tasks cancelled: \(reason.rawValue)")
    }

    /// Call when app becomes active. Starts a fresh session and loads data.
    func startSession() {
        startupCoordinator.start()
    }

    /// Refresh data off main thread. Safe to call after session start.
    func refreshData() async {
        let task = Task { @MainActor in
            await store.refreshData()
        }
        currentLoadTask = task
        await task.value
        currentLoadTask = nil
    }

    enum ResetReason: String {
        case background
        case coldLaunch
    }
}
