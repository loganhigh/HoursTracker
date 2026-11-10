import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import StoreKit
import FirebaseFunctions

/// Who has left a tip. Supporters get the shimmer on their username wherever
/// it shows.
///
/// The flag itself is `isSupporter` on the user's own doc, written by their
/// device when a tip goes through; the server copies it onto the public
/// profile the same way it carries the verified badge. Names on screen are
/// usernames (unique), so other people's flags are keyed by name, which is
/// all the shared name view has to go on.
/// Supporter name colours. Raw values are what the server accepts
/// (functions/src/supporter.js COLORS).
enum SupporterColor: String, CaseIterable, Identifiable {
    case blue, purple, emerald, rose

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var gradient: [Color] {
        switch self {
        case .blue: return [Color(hex: 0x5B9BFF), Color(hex: 0x8CC8FF), Color(hex: 0x5B9BFF)]
        case .purple: return [Color(hex: 0xA77BFF), Color(hex: 0xD6C2FF), Color(hex: 0xA77BFF)]
        case .emerald: return [Color(hex: 0x2FCB8F), Color(hex: 0x8DF0C6), Color(hex: 0x2FCB8F)]
        case .rose: return [Color(hex: 0xFF6FA8), Color(hex: 0xFFB8D4), Color(hex: 0xFF6FA8)]
        }
    }

    var solid: Color { gradient[0] }
}

/// What a supporter has unlocked, as published by the server (it checks the
/// tip total, so nothing here can be ahead of what was paid).
struct SupporterStyle: Equatable {
    var color: SupporterColor = .blue
    /// At Legend prestige, show the supporter colour instead of Legend's.
    var prefersColor: Bool = false
    var total: Double = 0

    static let colorUnlockTotal = 4.99 // the $4.99 tip counts

    /// Parses the server's `supporter` map; nil when it isn't one.
    static func parse(_ raw: Any?) -> SupporterStyle? {
        guard let map = raw as? [String: Any] else { return nil }
        return SupporterStyle(
            color: SupporterColor(rawValue: map["color"] as? String ?? "") ?? .blue,
            prefersColor: map["prefersColor"] as? Bool ?? false,
            total: (map["total"] as? NSNumber)?.doubleValue ?? 0
        )
    }
}

@MainActor
final class SupporterRegistry: ObservableObject {
    static let shared = SupporterRegistry()

    private static let selfKey = "is_supporter"

    @Published private(set) var names: Set<String> = []
    @Published private(set) var selfIsSupporter: Bool
    /// Perk styles by name key and by uid (avatars know the uid).
    @Published private(set) var styles: [String: SupporterStyle] = [:]
    @Published private(set) var uidStyles: [String: SupporterStyle] = [:]
    @Published private(set) var selfStyle = SupporterStyle()

    private init() {
        selfIsSupporter = UserDefaults.standard.bool(forKey: Self.selfKey)
        TipLedger.start()
    }

    func contains(_ name: String) -> Bool {
        let key = Self.key(name)
        guard !key.isEmpty else { return false }
        if names.contains(key) { return true }
        return selfIsSupporter && ownKeys().contains(key)
    }

    /// Called wherever another person's profile is parsed. `supporter` is
    /// the server's perk map when the source carries one.
    func record(name: String, isSupporter: Bool, uid: String? = nil, supporter: Any? = nil) {
        let key = Self.key(name)
        let style = isSupporter ? SupporterStyle.parse(supporter) : nil
        if !key.isEmpty {
            if isSupporter {
                if !names.contains(key) { names.insert(key) }
                if let style, styles[key] != style { styles[key] = style }
            } else {
                if names.contains(key) { names.remove(key) }
                if styles[key] != nil { styles[key] = nil }
            }
        }
        if let uid, !uid.isEmpty {
            if let style {
                if uidStyles[uid] != style { uidStyles[uid] = style }
            } else if !isSupporter, uidStyles[uid] != nil {
                uidStyles[uid] = nil
            }
        }
    }

    /// The style to draw a supporter's name/avatar with (nil = not a supporter).
    func style(name: String, uid: String? = nil) -> SupporterStyle? {
        if let uid, uid == Auth.auth().currentUser?.uid {
            return selfIsSupporter ? selfStyle : nil
        }
        if let uid, let style = uidStyles[uid] { return style }
        let key = Self.key(name)
        if let style = styles[key] { return style }
        if selfIsSupporter, ownKeys().contains(key) { return selfStyle }
        return contains(name) ? SupporterStyle() : nil
    }

    /// Our own published perks (from our public profile).
    func adoptSelfStyle(_ raw: Any?) {
        guard let style = SupporterStyle.parse(raw), style != selfStyle else { return }
        selfStyle = style
    }

    /// Saves our perk choices; the server publishes them (after checking
    /// they're unlocked) on the recompute this kicks off.
    func saveChoices(color: SupporterColor? = nil, prefersColor: Bool? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var data: [String: Any] = [:]
        if let color {
            data["supporterColor"] = color.rawValue
            selfStyle.color = color
        }
        if let prefersColor {
            data["supporterNameStyle"] = prefersColor ? "supporter" : "legend"
            selfStyle.prefersColor = prefersColor
        }
        guard !data.isEmpty else { return }
        Firestore.firestore().collection("users").document(uid).setData(data, merge: true) { _ in
            Task { _ = try? await Functions.functions(region: "us-central1")
                .httpsCallable("recomputeUserStatsCallable").call([:]) }
        }
    }

    /// A tip went through on this device (now, or finishing later through
    /// Transaction.updates): flip the supporter flag and add it to the
    /// ledger, which keeps the running total (see TipLedger).
    func recordTip(transaction: StoreKit.Transaction, productName: String? = nil) {
        guard TipLedger.isTip(transaction.productID), transaction.revocationDate == nil else { return }
        setSelf(true)
        if let uid = Auth.auth().currentUser?.uid {
            Firestore.firestore().collection("users").document(uid)
                .setData(["isSupporter": true], merge: true)
        }
        TipLedger.record(transaction, productName: productName)
    }

    /// Our own published profile says we are a supporter (a new device, or a
    /// reinstall). Only ever turns the flag on.
    func adoptServerValue(_ isSupporter: Bool) {
        if isSupporter { setSelf(true) }
    }

    /// Account switch: the flag belonged to the account that signed out.
    func resetSelf() { setSelf(false) }

    private func setSelf(_ value: Bool) {
        guard selfIsSupporter != value else { return }
        selfIsSupporter = value
        UserDefaults.standard.set(value, forKey: Self.selfKey)
    }

    private func ownKeys() -> Set<String> {
        var keys: Set<String> = []
        if let name = UserDefaults.standard.string(forKey: "profile_display_name") {
            keys.insert(Self.key(name))
        }
        if let username = FriendsService.shared.myUsername {
            keys.insert(Self.key(username))
        }
        return keys
    }

    /// Chat shows handles as "@name" — the @ is display only, so it's
    /// dropped here (it kept every chat name from matching).
    private static func key(_ name: String) -> String {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") { trimmed.removeFirst() }
        return trimmed.lowercased()
    }
}
