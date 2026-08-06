import Foundation
import Combine
import FirebaseFunctions

// MARK: - Teams (crews) — slice 1
//
// Wraps the `createCrew` / `joinCrewByCode` callables (see functions/index.js)
// the same way FriendsService wraps sendFriendRequest/acceptFriendRequest:
// `Functions.functions(region:)`, an async `.call([...])`, and NSError
// message-substring matching to map server HttpsError text onto a typed,
// LocalizedError enum for quiet inline display.

/// One crew the signed-in user belongs to, as known from the result of a
/// create/join call. A full crews-list read (e.g. for a roster/dashboard
/// screen) isn't needed until a later slice.
struct MyCrew: Identifiable, Equatable {
    let id: String
    let name: String
    let role: String
    /// Only populated for a crew this device just created — the code is
    /// otherwise never re-fetched (no client read of `crewInviteCodes`).
    let inviteCode: String?
}

enum CrewError: LocalizedError {
    case invalidName
    case invalidCode
    case codeNotFound
    case alreadyMember
    case crewFull
    case callableFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Enter a crew name."
        case .invalidCode: return "Enter a valid 6-character invite code."
        case .codeNotFound: return "That invite code wasn't found. Double-check it and try again."
        case .alreadyMember: return "You're already a member of this crew."
        case .crewFull: return "This crew is full."
        case .callableFailed: return "Something went wrong. Check your connection and try again."
        }
    }
}

@MainActor
final class CrewService: ObservableObject {
    static let shared = CrewService()

    /// Crews the signed-in user has created or joined this session.
    @Published var myCrews: [MyCrew] = []

    /// Set by a `join-crew` deep link (see `handleIncomingURL`). Any screen
    /// that can present the Join-a-Crew sheet observes this, pre-fills the
    /// code, and clears it back to nil once consumed.
    @Published var pendingJoinCode: String?

    private lazy var functions = Functions.functions(region: "us-central1")

    private init() {}

    // MARK: - Callables

    func createCrew(name rawName: String) async throws -> MyCrew {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CrewError.invalidName }

        do {
            let result = try await functions.httpsCallable("createCrew").call(["name": name])
            let data = result.data as? [String: Any]
            let crewId = data?["crewId"] as? String ?? ""
            let inviteCode = data?["inviteCode"] as? String ?? ""
            let crew = MyCrew(id: crewId, name: name, role: "manager", inviteCode: inviteCode)
            myCrews.append(crew)
            return crew
        } catch {
            throw Self.mapError(error, fallbackIsJoin: false)
        }
    }

    func joinCrew(code rawCode: String) async throws -> MyCrew {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 6 else { throw CrewError.invalidCode }

        do {
            let result = try await functions.httpsCallable("joinCrewByCode").call(["code": code])
            let data = result.data as? [String: Any]
            let crewId = data?["crewId"] as? String ?? ""
            let crewName = data?["crewName"] as? String ?? ""
            let crew = MyCrew(id: crewId, name: crewName, role: "worker", inviteCode: nil)
            myCrews.append(crew)
            return crew
        } catch {
            throw Self.mapError(error, fallbackIsJoin: true)
        }
    }

    private static func mapError(_ error: Error, fallbackIsJoin: Bool) -> CrewError {
        let message = (error as NSError).localizedDescription
        if message.contains("already a member") || message.contains("already-exists") {
            return .alreadyMember
        } else if message.contains("wasn't found") || message.contains("no longer exists") || message.contains("not-found") {
            return fallbackIsJoin ? .codeNotFound : .callableFailed(error)
        } else if message.contains("full") || message.contains("resource-exhausted") {
            return .crewFull
        } else if message.contains("crew name") || message.contains("invite code") {
            return fallbackIsJoin ? .invalidCode : .invalidName
        }
        return .callableFailed(error)
    }

    // MARK: - Deep link

    /// The custom URL scheme registered in `Info.plist` (`CFBundleURLTypes`).
    /// It's Google Sign-In's reversed-client-id OAuth scheme — the only
    /// scheme this app currently registers. Reused here rather than
    /// registering a second scheme just for crew invites; see the slice-1
    /// report for the UX tradeoff this creates on the shared link text.
    static let deepLinkScheme = "com.googleusercontent.apps.883698344524-mqmpr0spvoqu758103dg63297a4u8gqq"

    static func inviteURL(code: String) -> URL? {
        var components = URLComponents()
        components.scheme = deepLinkScheme
        components.host = "join-crew"
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        return components.url
    }

    /// `<scheme>://join-crew?code=XXXXXX` — pre-fills the Join a Crew sheet
    /// with the shared code. Returns false for any URL it doesn't recognize
    /// so the caller falls through to `AuthService.handleIncomingURL` (the
    /// Google Sign-In OAuth redirect this scheme also carries).
    @discardableResult
    static func handleIncomingURL(_ url: URL) -> Bool {
        guard url.host == "join-crew",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawCode = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !rawCode.isEmpty
        else { return false }

        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        CrewService.shared.pendingJoinCode = code
        return true
    }
}
