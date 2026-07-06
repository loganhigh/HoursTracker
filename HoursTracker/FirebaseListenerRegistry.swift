import Foundation
import FirebaseFirestore
import os.log

/// Identifies which service owns a Firestore snapshot listener.
enum ListenerOwner: String, Sendable {
    case cloudSync
    case friendsService
    case statsListener
    case activityFeed
    case friendsBoard
    case shiftNudge
    case leaderboard
}

/// Central registry for Firestore snapshot listeners — attach/detach logging
/// and coordinated teardown on sign-out.
final class FirebaseListenerRegistry {
    static let shared = FirebaseListenerRegistry()

    private struct Registration {
        let owner: ListenerOwner
        let purpose: String
        let uid: String?
        let registration: ListenerRegistration
    }

    private var registrations: [String: Registration] = [:]
    private let lock = NSLock()
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HoursTracker", category: "firebase.listeners")

    private init() {}

    @discardableResult
    func register(
        owner: ListenerOwner,
        purpose: String,
        uid: String? = nil,
        registration: ListenerRegistration
    ) -> String {
        let key = makeKey(owner: owner, purpose: purpose, uid: uid)
        lock.lock()
        registrations[key]?.registration.remove()
        registrations[key] = Registration(owner: owner, purpose: purpose, uid: uid, registration: registration)
        lock.unlock()
        log.info("attach owner=\(owner.rawValue, privacy: .public) purpose=\(purpose, privacy: .public) uid=\(uid ?? "global", privacy: .public)")
        return key
    }

    func remove(key: String) {
        lock.lock()
        guard let reg = registrations.removeValue(forKey: key) else {
            lock.unlock()
            return
        }
        lock.unlock()
        reg.registration.remove()
        log.info("detach owner=\(reg.owner.rawValue, privacy: .public) purpose=\(reg.purpose, privacy: .public)")
    }

    func stopAll(for uid: String) {
        lock.lock()
        let keys = registrations.filter { $0.value.uid == uid }.map(\.key)
        let toRemove = keys.compactMap { registrations.removeValue(forKey: $0) }
        lock.unlock()
        for reg in toRemove { reg.registration.remove() }
        if !keys.isEmpty {
            log.info("stopAll uid=\(uid, privacy: .public) count=\(keys.count)")
        }
    }

    func stopAll(owner: ListenerOwner) {
        lock.lock()
        let keys = registrations.filter { $0.value.owner == owner }.map(\.key)
        let toRemove = keys.compactMap { registrations.removeValue(forKey: $0) }
        lock.unlock()
        for reg in toRemove { reg.registration.remove() }
    }

    private func makeKey(owner: ListenerOwner, purpose: String, uid: String?) -> String {
        "\(owner.rawValue).\(purpose).\(uid ?? "global")"
    }
}
