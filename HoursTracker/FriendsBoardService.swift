import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

/// User-authored board post stored at `users/{authorUid}/boardPosts/{postId}`.
struct BoardPost: Identifiable, Equatable, Hashable {
    let id: String
    let authorUid: String
    let authorName: String
    let authorInitials: String
    let text: String
    let createdAt: Date
    let visibility: String
    /// emoji → list of reactor user ids
    let reactions: [String: [String]]
    let commentCount: Int
    let hourContext: String?
    let badgeContext: String?

    var compositeKey: String { "\(authorUid)/\(id)" }

    static func from(authorUid: String, id: String, data: [String: Any]) -> BoardPost? {
        guard
            let authorName = data["authorName"] as? String,
            let text = data["text"] as? String
        else { return nil }

        let initials = data["authorInitials"] as? String
            ?? BoardContentFilter.initials(from: authorName)
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let visibility = data["visibility"] as? String ?? "friendsOnly"
        let reactions = parseReactions(data["reactions"])
        let commentCount = data["commentCount"] as? Int ?? 0
        let hourContext = data["hourContext"] as? String
        let badgeContext = data["badgeContext"] as? String

        return BoardPost(
            id: id,
            authorUid: authorUid,
            authorName: authorName,
            authorInitials: initials,
            text: text,
            createdAt: createdAt,
            visibility: visibility,
            reactions: reactions,
            commentCount: commentCount,
            hourContext: hourContext,
            badgeContext: badgeContext
        )
    }

    private static func parseReactions(_ value: Any?) -> [String: [String]] {
        guard let map = value as? [String: Any] else { return [:] }
        var out: [String: [String]] = [:]
        for (emoji, raw) in map {
            if let ids = raw as? [String] {
                out[emoji] = ids
            }
        }
        return out
    }

    func reactionCount(for emoji: String) -> Int {
        reactions[emoji]?.count ?? 0
    }

    func userReactionEmoji(currentUid: String?) -> String? {
        guard let currentUid else { return nil }
        for emoji in BoardContentFilter.allowedReactionEmojis {
            if reactions[emoji]?.contains(currentUid) == true {
                return emoji
            }
        }
        return nil
    }
}

struct BoardComment: Identifiable, Equatable, Hashable {
    let id: String
    let postAuthorUid: String
    let postId: String
    let authorId: String
    let authorName: String
    let text: String
    let createdAt: Date

    var compositeKey: String { "\(postAuthorUid)/\(postId)/\(id)" }

    static func from(
        postAuthorUid: String,
        postId: String,
        id: String,
        data: [String: Any]
    ) -> BoardComment? {
        guard
            let authorId = data["authorId"] as? String,
            let authorName = data["authorName"] as? String,
            let text = data["text"] as? String
        else { return nil }
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        return BoardComment(
            id: id,
            postAuthorUid: postAuthorUid,
            postId: postId,
            authorId: authorId,
            authorName: authorName,
            text: text,
            createdAt: createdAt
        )
    }
}

// MARK: - Service

/// Fan-in listeners for `users/{uid}/boardPosts` across self + accepted friends.
@MainActor
final class FriendsBoardService: ObservableObject {
    static let shared = FriendsBoardService()

    @Published var posts: [BoardPost] = []
    @Published var commentsByPost: [String: [BoardComment]] = [:]
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var isPosting = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var postListeners: [String: ListenerRegistration] = [:]
    private var commentListeners: [String: ListenerRegistration] = [:]
    private var perAuthorPosts: [String: [BoardPost]] = [:]
    private var currentUid: String?
    private var trackedCommentPosts: Set<String> = []

    private let maxPostsPerAuthor = 25
    private let recentWindow: TimeInterval = 30 * 24 * 3600

    private init() {}

    // MARK: Subscription

    func startListening(uid: String, friendUids: [String]) {
        currentUid = uid
        let wanted = Set([uid] + friendUids)
        let current = Set(postListeners.keys)
        isLoading = current.isEmpty && !wanted.isEmpty

        for removed in current.subtracting(wanted) {
            postListeners[removed]?.remove()
            postListeners.removeValue(forKey: removed)
            perAuthorPosts.removeValue(forKey: removed)
        }
        for added in wanted.subtracting(current) {
            attachPostsListener(authorUid: added)
        }
        rebuildPosts()
    }

    func stopListening() {
        postListeners.values.forEach { $0.remove() }
        postListeners.removeAll()
        commentListeners.values.forEach { $0.remove() }
        commentListeners.removeAll()
        perAuthorPosts.removeAll()
        trackedCommentPosts.removeAll()
        commentsByPost.removeAll()
        currentUid = nil
        posts = []
        isLoading = false
        isRefreshing = false
    }

    func refresh(uid: String, friendUids: [String]) async {
        isRefreshing = true
        stopListening()
        startListening(uid: uid, friendUids: friendUids)
        try? await Task.sleep(nanoseconds: 350_000_000)
        isRefreshing = false
    }

    private func attachPostsListener(authorUid: String) {
        let query = db.collection("users").document(authorUid).collection("boardPosts")
            .order(by: "createdAt", descending: true)
            .limit(to: maxPostsPerAuthor)

        postListeners[authorUid] = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.perAuthorPosts.removeValue(forKey: authorUid)
                    if authorUid == self.currentUid {
                        self.errorMessage = error.localizedDescription
                    }
                    self.isLoading = false
                    self.rebuildPosts()
                    return
                }
                self.errorMessage = nil
                let parsed = snapshot?.documents.compactMap { doc in
                    BoardPost.from(authorUid: authorUid, id: doc.documentID, data: doc.data())
                } ?? []
                self.perAuthorPosts[authorUid] = parsed
                self.isLoading = false
                self.rebuildPosts()
            }
        }
    }

    private func rebuildPosts() {
        let cutoff = Date().addingTimeInterval(-recentWindow)
        posts = perAuthorPosts.values
            .flatMap { $0 }
            .filter { $0.createdAt >= cutoff && $0.visibility == "friendsOnly" }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Comments subscription

    func startListeningToComments(for post: BoardPost) {
        let key = post.compositeKey
        guard !trackedCommentPosts.contains(key) else { return }
        trackedCommentPosts.insert(key)

        let query = db.collection("users")
            .document(post.authorUid)
            .collection("boardPosts")
            .document(post.id)
            .collection("comments")
            .order(by: "createdAt", descending: false)
            .limit(to: 50)

        commentListeners[key] = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                let parsed = snapshot?.documents.compactMap { doc in
                    BoardComment.from(
                        postAuthorUid: post.authorUid,
                        postId: post.id,
                        id: doc.documentID,
                        data: doc.data()
                    )
                } ?? []
                self.commentsByPost[key] = parsed
            }
        }
    }

    func stopListeningToComments(for post: BoardPost) {
        let key = post.compositeKey
        commentListeners[key]?.remove()
        commentListeners.removeValue(forKey: key)
        trackedCommentPosts.remove(key)
        commentsByPost.removeValue(forKey: key)
    }

    // MARK: Writes

    func createPost(
        text: String,
        hourContext: String? = nil,
        badgeContext: String? = nil
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BoardContentFilter.ValidationError.empty
        }
        let trimmed = try BoardContentFilter.validatePost(text)
        let displayName = UserDefaults.standard.string(forKey: "profile_display_name") ?? "Worker"
        let initials = BoardContentFilter.initials(from: displayName)

        isPosting = true
        defer { isPosting = false }

        let postId = UUID().uuidString
        var payload: [String: Any] = [
            "authorId": uid,
            "authorName": displayName,
            "authorInitials": initials,
            "text": trimmed,
            "createdAt": FieldValue.serverTimestamp(),
            "visibility": "friendsOnly",
            "reactions": [:] as [String: Any],
            "commentCount": 0
        ]
        if let hourContext, !hourContext.isEmpty {
            payload["hourContext"] = hourContext
        }
        if let badgeContext, !badgeContext.isEmpty {
            payload["badgeContext"] = badgeContext
        }

        try await db.collection("users").document(uid).collection("boardPosts").document(postId)
            .setData(payload)
        errorMessage = nil
    }

    func deletePost(_ post: BoardPost) async throws {
        guard let uid = Auth.auth().currentUser?.uid, post.authorUid == uid else { return }

        let postRef = db.collection("users").document(uid).collection("boardPosts").document(post.id)
        let commentsSnap = try await postRef.collection("comments").limit(to: 100).getDocuments()
        let batch = db.batch()
        commentsSnap.documents.forEach { batch.deleteDocument($0.reference) }
        batch.deleteDocument(postRef)
        try await batch.commit()
        stopListeningToComments(for: post)
    }

    func toggleReaction(on post: BoardPost, emoji: String) async throws {
        guard BoardContentFilter.allowedReactionEmojis.contains(emoji) else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let postRef = db.collection("users")
            .document(post.authorUid)
            .collection("boardPosts")
            .document(post.id)

        _ = try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(postRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            guard var data = snapshot.data() else { return nil }

            let reactions = BoardPost.from(authorUid: post.authorUid, id: post.id, data: data)?.reactions ?? [:]
            var updated = reactions

            for key in updated.keys {
                updated[key] = updated[key]?.filter { $0 != uid }
                if updated[key]?.isEmpty == true {
                    updated.removeValue(forKey: key)
                }
            }

            if reactions[emoji]?.contains(uid) != true {
                var ids = updated[emoji] ?? []
                ids.append(uid)
                updated[emoji] = ids
            }

            var firestoreReactions: [String: Any] = [:]
            for (key, ids) in updated {
                firestoreReactions[key] = ids
            }
            data["reactions"] = firestoreReactions
            transaction.updateData(["reactions": firestoreReactions], forDocument: postRef)
            return nil
        }
    }

    func addComment(to post: BoardPost, text: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let trimmed = try BoardContentFilter.validateComment(text)
        let displayName = UserDefaults.standard.string(forKey: "profile_display_name") ?? "Worker"

        let postRef = db.collection("users")
            .document(post.authorUid)
            .collection("boardPosts")
            .document(post.id)
        let commentId = UUID().uuidString
        let commentRef = postRef.collection("comments").document(commentId)

        _ = try await db.runTransaction { transaction, _ in
            transaction.setData([
                "authorId": uid,
                "authorName": displayName,
                "text": trimmed,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: commentRef)
            transaction.updateData([
                "commentCount": FieldValue.increment(Int64(1))
            ], forDocument: postRef)
            return nil
        }
    }

    func deleteComment(_ comment: BoardComment) async throws {
        guard let uid = Auth.auth().currentUser?.uid, comment.authorId == uid else { return }

        let postRef = db.collection("users")
            .document(comment.postAuthorUid)
            .collection("boardPosts")
            .document(comment.postId)
        let commentRef = postRef.collection("comments").document(comment.id)

        _ = try await db.runTransaction { transaction, _ in
            transaction.deleteDocument(commentRef)
            transaction.updateData([
                "commentCount": FieldValue.increment(Int64(-1))
            ], forDocument: postRef)
            return nil
        }
    }
}
