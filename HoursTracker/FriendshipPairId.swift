import Foundation

enum FriendshipPairId {
    /// Canonical friendship document id: `min(uidA,uidB)_max(uidA,uidB)`.
    static func make(_ uidA: String, _ uidB: String) -> String {
        let sorted = [uidA, uidB].sorted()
        return "\(sorted[0])_\(sorted[1])"
    }

    static func otherUid(in data: [String: Any], myUid: String) -> String? {
        let userA = data["userA"] as? String
        let userB = data["userB"] as? String
        if userA == myUid { return userB }
        if userB == myUid { return userA }
        return nil
    }
}
