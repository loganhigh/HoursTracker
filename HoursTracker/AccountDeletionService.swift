import Foundation
import FirebaseAuth

/// Centralised account-deletion flow. Apple App Review Guideline 5.1.1(v)
/// requires apps that offer account creation to also offer in-app account
/// deletion, and that deletion must actually remove (or initiate removal of)
/// the user's account and associated data.
@MainActor
enum AccountDeletionService {

    enum DeletionError: LocalizedError {
        case notSignedIn
        case requiresRecentLogin
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "You are not signed in."
            case .requiresRecentLogin:
                return "For security, please sign out and sign in with Apple again, then retry account deletion."
            case .underlying(let error):
                return error.localizedDescription
            }
        }
    }

    static func deleteAccount(store: HoursStore) async throws {
        guard let user = Auth.auth().currentUser else {
            throw DeletionError.notSignedIn
        }

        // Delete the Firebase Auth user FIRST — if this fails (e.g. requires
        // recent login), nothing has been destroyed yet and the user can retry.
        //
        // Cloud data is purged by the `purgeDeletedUserData` Auth onDelete
        // trigger in functions/index.js, NOT here. It cannot be done from the
        // client: `User.delete()` calls `signOutByForce` before this call even
        // returns, so every subsequent Firestore/Storage request would go out
        // unauthenticated and be rejected — and `publicProfiles/{uid}` and
        // `users/{uid}/stats` are `allow write: if false` for clients in any
        // case. The cleanup that used to live here silently failed on every
        // single deletion, leaving the account's hours, profile, friend links
        // and leaderboard entry live in Firestore forever.
        do {
            try await user.delete()
        } catch {
            let nsError = error as NSError
            if nsError.code == AuthErrorCode.requiresRecentLogin.rawValue {
                throw DeletionError.requiresRecentLogin
            }
            throw DeletionError.underlying(error)
        }

        // Local-only teardown. These need no credentials, so unlike the cloud
        // deletes they do still work after the forced sign-out.
        await ProfilePhotoManager.shared.deleteAllPhotoData()
        store.deleteAllData()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "account_lookup_email")
        defaults.removeObject(forKey: "profile_display_name")
        defaults.removeObject(forKey: "company_name")
        defaults.removeObject(forKey: "company_occupation")
        defaults.removeObject(forKey: "company_employee_id")
        defaults.removeObject(forKey: "company_hourly_rate")
        defaults.removeObject(forKey: "company_start_date_ts")
    }
}
