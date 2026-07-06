import SwiftUI
import Combine
import os

/// Coordinates app startup: loads data off main thread, shows splash until ready.
@MainActor
final class StartupCoordinator: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var retryCount = 0

    private let store: HoursStore

    init(store: HoursStore) {
        self.store = store
    }

    private let loadTimeout: TimeInterval = 7.0
    private var timeoutWorkItem: DispatchWorkItem?

    /// Cancel in-flight load. Call on session reset.
    func cancelLoad() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    /// Reset to loading state. Call when session resets so UI shows splash again.
    func resetToLoading() {
        state = .loading
    }

    /// Call from app entry to begin async load.
    func start() {
        let signpostID = OSSignpostID(log: .default)
        os_signpost(.begin, log: .default, name: "Startup", signpostID: signpostID)
        AppLogger.lifecycle.info("Startup: begin")
        state = .loading

        let startTime = CFAbsoluteTimeGetCurrent()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, case .loading = self.state else { return }
            AppLogger.lifecycle.warning("Startup: timeout after 7s")
            os_signpost(.end, log: .default, name: "Startup", signpostID: signpostID)
            Task { @MainActor in
                self.state = .error("Loading took too long. Try again or reset cache.")
            }
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + loadTimeout, execute: workItem)

        store.ensureDataLoaded { [weak self] in
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            workItem.cancel()
            self?.timeoutWorkItem = nil
            AppLogger.lifecycle.info("Startup: data loaded in \(String(format: "%.2f", elapsed))s")
            os_signpost(.end, log: .default, name: "Startup", signpostID: signpostID)
            Task { @MainActor in
                self?.state = .ready
                AppLogger.lifecycle.info("Startup: ready")
            }
        }
    }

    func retry() {
        retryCount += 1
        state = .loading
        start()
    }

    func resetCacheAndRetry() {
        clearDerivedCachesOnly()
        retryCount = 0
        state = .loading
        start()
    }

    /// Clears temp/derived caches only. Does NOT delete user shift data.
    private func clearDerivedCachesOnly() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        if let contents = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for url in contents {
                let name = url.lastPathComponent
                if name.hasPrefix("hours_") && (name.hasSuffix(".csv") || name.hasSuffix(".pdf")) {
                    try? fm.removeItem(at: url)
                }
            }
        }
        // Clear non-essential UserDefaults (derived/cache only)
        let keysToClear = ["last_checked_week_start"]
        for key in keysToClear {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
