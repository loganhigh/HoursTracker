import Foundation
import FirebaseAuth
import FirebaseFirestore

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
        let uid = user.uid
        let db = Firestore.firestore()

        // Delete Firebase Auth user FIRST — if this fails (e.g. requires
        // recent login), no Firestore data is lost and user can retry.
        do {
            try await user.delete()
        } catch {
            let nsError = error as NSError
            if nsError.code == AuthErrorCode.requiresRecentLogin.rawValue {
                throw DeletionError.requiresRecentLogin
            }
            throw DeletionError.underlying(error)
        }

        // Auth succeeded — now clean up Firestore data. Failures here are
        // non-fatal since the account is already deleted.
        await removeReciprocalFriendLinks(db: db, uid: uid)
        await deleteBoardPosts(db: db, uid: uid)
        await ProfilePhotoManager.shared.deleteAllPhotoData()
        await deleteSubcollection(db: db, uid: uid, name: "entries")
        await deleteSubcollection(db: db, uid: uid, name: "timeEntries")
        await deleteSubcollection(db: db, uid: uid, name: "paySettings")
        await deleteSubcollection(db: db, uid: uid, name: "friends")
        await deleteSubcollection(db: db, uid: uid, name: "friendRequests")
        await deleteSubcollection(db: db, uid: uid, name: "activity")
        await deleteSubcollection(db: db, uid: uid, name: "shiftNudges")
        await deleteSubcollection(db: db, uid: uid, name: "deviceTokens")
        await deleteSubcollection(db: db, uid: uid, name: "stats")
        await deleteSubcollection(db: db, uid: uid, name: "gamification")
        try? await db.collection("users").document(uid).delete()
        try? await db.collection("publicProfiles").document(uid).delete()

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

    private static func removeReciprocalFriendLinks(db: Firestore, uid: String) async {
        do {
            let friendsSnap = try await db.collection("users").document(uid).collection("friends").getDocuments()
            for doc in friendsSnap.documents {
                let friendUid = doc.documentID
                try? await db.collection("users").document(friendUid).collection("friends").document(uid).delete()
            }
        } catch {
            #if DEBUG
            print("AccountDeletionService: reciprocal friend cleanup error — \(error.localizedDescription)")
            #endif
        }
    }

    private static func deleteBoardPosts(db: Firestore, uid: String) async {
        let postsRef = db.collection("users").document(uid).collection("boardPosts")
        var keepGoing = true
        while keepGoing {
            do {
                let snapshot = try await postsRef.limit(to: 25).getDocuments()
                if snapshot.documents.isEmpty {
                    keepGoing = false
                    break
                }
                for post in snapshot.documents {
                    await deleteSubcollectionAt(post.reference.collection("comments"))
                    try? await post.reference.delete()
                }
                if snapshot.documents.count < 25 {
                    keepGoing = false
                }
            } catch {
                #if DEBUG
                print("AccountDeletionService: boardPosts cleanup error — \(error.localizedDescription)")
                #endif
                return
            }
        }
    }

    private static func deleteSubcollection(db: Firestore, uid: String, name: String) async {
        let ref = db.collection("users").document(uid).collection(name)
        await deleteSubcollectionAt(ref)
    }

    private static func deleteSubcollectionAt(_ ref: CollectionReference) async {
        var keepGoing = true
        while keepGoing {
            do {
                let snapshot = try await ref.limit(to: 100).getDocuments()
                if snapshot.documents.isEmpty {
                    keepGoing = false
                    break
                }
                let batch = ref.firestore.batch()
                for doc in snapshot.documents {
                    batch.deleteDocument(doc.reference)
                }
                try await batch.commit()
                if snapshot.documents.count < 100 {
                    keepGoing = false
                }
            } catch {
                #if DEBUG
                print("AccountDeletionService: subcollection cleanup error — \(error.localizedDescription)")
                #endif
                return
            }
        }
    }
}
