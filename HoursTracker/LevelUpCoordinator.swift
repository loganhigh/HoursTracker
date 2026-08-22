import SwiftUI
import Combine

// MARK: - Level-up coordinator
//
// Owns the decision "a celebration is on screen" and everything the
// celebration needs to render: the level span, the tier, dynamic reward lines,
// and the preloaded cinematic player. RootView's existing high-water-mark
// ratchet decides WHEN a level-up is real (it already absorbs the
// challenge-XP resets that produce phantom level dips); this coordinator only
// presents what the ratchet reports. XP math, prestige logic, and Firestore
// are untouched.

@MainActor
final class LevelUpCoordinator: ObservableObject {

    /// Everything one celebration needs, captured at trigger time so a
    /// mid-animation profile refresh can't mutate the show.
    struct Celebration: Identifiable {
        let id = UUID()
        let fromLevel: Int
        let toLevel: Int
        let tier: PrestigeTheme.Tier
        /// Title of the level landed on, from the existing rank-title table.
        let rankTitle: String
        /// Dynamic unlock lines for the reward stage; empty when the span
        /// unlocked nothing worth announcing.
        let rewards: [Reward]
        /// XP display for the bar: where the bar sat before the final level.
        let xpIntoLevel: Int
        let xpForNextLevel: Int

        var levelsGained: Int { max(1, toLevel - fromLevel) }
    }

    struct Reward: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    @Published var current: Celebration?
    /// The cinematic player for the current celebration; created just before
    /// presentation, torn down on dismiss so no video stays loaded.
    private(set) var animationPlayer: LevelAnimationPlayer?

    private var onDismiss: (() -> Void)?

    // MARK: Triggering

    /// Presents the level-up celebration. `fromLevel` is the last celebrated
    /// level (the ratchet's previous high-water mark), `profile` the already
    /// updated progression state — rewards are derived, never hardcoded.
    func presentLevelUp(
        fromLevel: Int,
        profile: GamificationProfile,
        onDismiss: (() -> Void)? = nil
    ) {
        guard current == nil else { return }
        let tier = PrestigeTheme.tier(for: profile.prestige)
        let toLevel = profile.level

        let celebration = Celebration(
            fromLevel: fromLevel,
            toLevel: toLevel,
            tier: tier,
            rankTitle: GamificationLevelCalculator.rankTitle(
                forLevel: toLevel,
                prestige: profile.prestige
            ),
            rewards: Self.rewards(for: profile, fromLevel: fromLevel),
            xpIntoLevel: profile.xpIntoCurrentLevel,
            xpForNextLevel: profile.xpForNextLevel
        )

        self.onDismiss = onDismiss
        animationPlayer = LevelAnimationPlayer(cinematic: .levelUp(tier: tier))
        current = celebration
    }

    func dismiss() {
        animationPlayer?.teardown()
        animationPlayer = nil
        current = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }

    // MARK: Rewards

    /// Derives what the gained span actually unlocked from existing
    /// progression rules. Works for any span (4→5, 24→25, 24→27 …).
    private static func rewards(
        for profile: GamificationProfile,
        fromLevel: Int
    ) -> [Reward] {
        var rewards: [Reward] = []

        // New rank title — compare against the departed level's title so a
        // multi-level jump reports the title actually landed on.
        let oldTitle = GamificationLevelCalculator.rankTitle(
            forLevel: max(1, fromLevel),
            prestige: profile.prestige
        )
        let newTitle = GamificationLevelCalculator.rankTitle(
            forLevel: profile.level,
            prestige: profile.prestige
        )
        if newTitle != oldTitle {
            rewards.append(Reward(
                icon: "medal.fill",
                title: "New rank",
                detail: newTitle
            ))
        }

        // Prestige availability — the run's terminal unlock.
        if profile.canPrestige {
            let nextTier = PrestigeTheme.tier(for: min(profile.prestige + 1, 10))
            rewards.append(Reward(
                icon: "crown.fill",
                title: "Prestige available",
                detail: "\(nextTier.name) rank is waiting"
            ))
        }

        return rewards
    }
}


// MARK: - Per-account celebration ratchet

/// Highest level already celebrated with a Level Up card, per prestige run —
/// keyed by account. It used to be one device-wide @AppStorage pair, so after
/// signing out and into another account (or deleting an account, or signing in
/// after local-only use) the ratchet belonged to the wrong person: either no
/// Level Up card for many levels, or a phantom "Level 2 → 12" on sign-in.
enum LevelUpRatchet {
    static let localScope = "local"
    private static let hwmPrefix = "level_up_celebrated_hwm_v2"
    private static let prestigePrefix = "level_up_celebrated_prestige_v2"

    static func celebratedLevelHWM(scope: String) -> Int {
        UserDefaults.standard.integer(forKey: "\(hwmPrefix)_\(scope)")
    }

    static func setCelebratedLevelHWM(_ value: Int, scope: String) {
        UserDefaults.standard.set(value, forKey: "\(hwmPrefix)_\(scope)")
    }

    /// -1 until the scope has been baselined, so the first evaluation for a
    /// new account re-baselines silently instead of celebrating.
    static func celebratedPrestige(scope: String) -> Int {
        let key = "\(prestigePrefix)_\(scope)"
        return UserDefaults.standard.object(forKey: key) == nil ? -1 : UserDefaults.standard.integer(forKey: key)
    }

    static func setCelebratedPrestige(_ value: Int, scope: String) {
        UserDefaults.standard.set(value, forKey: "\(prestigePrefix)_\(scope)")
    }

    static func resetAll() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(hwmPrefix) || key.hasPrefix(prestigePrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
