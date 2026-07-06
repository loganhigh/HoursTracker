import Foundation
import FirebaseFirestore
import os.log

/// Structured, uid-scoped Firestore operation logging (latency + error codes).
enum FirestoreOperationLog {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HoursTracker", category: "firebase.ops")

    static func read<T>(
        operation: String,
        uid: String? = nil,
        block: () async throws -> T
    ) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let value = try await block()
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            log.info("read op=\(operation, privacy: .public) uid=\(uid ?? "-", privacy: .public) ms=\(ms)")
            return value
        } catch {
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            let code = (error as NSError).code
            log.error("read op=\(operation, privacy: .public) uid=\(uid ?? "-", privacy: .public) ms=\(ms) code=\(code) err=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    static func write(
        operation: String,
        uid: String? = nil,
        block: (@escaping (Error?) -> Void) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let start = CFAbsoluteTimeGetCurrent()
        block { error in
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if let error {
                let code = (error as NSError).code
                log.error("write op=\(operation, privacy: .public) uid=\(uid ?? "-", privacy: .public) ms=\(ms) code=\(code) err=\(error.localizedDescription, privacy: .public)")
                completion(.failure(error))
            } else {
                log.info("write op=\(operation, privacy: .public) uid=\(uid ?? "-", privacy: .public) ms=\(ms)")
                completion(.success(()))
            }
        }
    }

    static func listenerAttached(owner: ListenerOwner, purpose: String, uid: String?) {
        log.debug("listener attach owner=\(owner.rawValue, privacy: .public) purpose=\(purpose, privacy: .public) uid=\(uid ?? "-", privacy: .public)")
    }

    static func listenerError(owner: ListenerOwner, purpose: String, uid: String?, error: Error) {
        let code = (error as NSError).code
        log.error("listener owner=\(owner.rawValue, privacy: .public) purpose=\(purpose, privacy: .public) uid=\(uid ?? "-", privacy: .public) code=\(code) err=\(error.localizedDescription, privacy: .public)")
    }
}
