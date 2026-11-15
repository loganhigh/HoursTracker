import Foundation

/// Invite badge copy, mirroring functions/src/social/referrals.js. The server
/// awards the Recruiter badge (referralCount is server-owned).
enum ReferralTier {
    static let badgeName = "Recruiter"

    /// "Invite a friend to earn the Recruiter badge" or
    /// "2 friends joined from your invites".
    static func progressLine(count: Int) -> String {
        if count <= 0 { return "Invite a friend to earn the \(badgeName) badge" }
        let joined = count == 1 ? "1 friend joined" : "\(count) friends joined"
        return "\(joined) from your invites"
    }
}
