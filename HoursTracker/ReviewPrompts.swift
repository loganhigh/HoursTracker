import SwiftUI
import Combine

// MARK: - Review prompts
//
// Asks for App Store reviews at happy moments instead of once at shift #5:
// - Prestige: a pop-up whose button opens the write-a-review page directly
//   (a written review, not just stars).
// - 30th work shift: the same pop-up, once ("Enjoying Hour Tracker?").
// - Level-ups (10+ shifts): Apple's star sheet, at most every 120 days.
//   Apple caps that sheet at 3 a year per person anyway.
// The 30th-shift pop-up is the last ask: once it has shown, or once someone
// taps "Write a review" (or has the verified reviewer badge), nothing asks again.

enum ReviewAskReason: Equatable {
    case prestige(Int)
    case milestone

    var title: String {
        switch self {
        case .prestige(let p): return "Prestige \(p)! Enjoying Hour Tracker?"
        case .milestone: return "Enjoying Hour Tracker?"
        }
    }

    var message: String {
        "Help Logan with a written review! It helps new users find the app."
    }
}

/// When to ask. Pure so it can be tested without UserDefaults.
enum ReviewAskPolicy {
    static let milestoneShifts = 30
    static let levelUpMinShifts = 10
    static let starSheetCooldown: TimeInterval = 120 * 86_400
    /// Never two asks of any kind within this window.
    static let anyAskGap: TimeInterval = 7 * 86_400

    static func askedRecently(_ lastAskAt: Date?, now: Date) -> Bool {
        guard let lastAskAt else { return false }
        return now.timeIntervalSince(lastAskAt) < anyAskGap
    }

    /// `reviewed`: tapped "Write a review" before, or has the verified
    /// reviewer badge. Either way, never ask again.
    static func shouldAskAfterPrestige(reviewed: Bool) -> Bool {
        !reviewed
    }

    static func shouldAskAtMilestone(workShifts: Int, alreadyAsked: Bool, reviewed: Bool, lastAskAt: Date?, now: Date) -> Bool {
        workShifts >= milestoneShifts && !alreadyAsked
            && !reviewed && !askedRecently(lastAskAt, now: now)
    }

    static func shouldShowStarSheet(workShifts: Int, lastStarAt: Date?, reviewed: Bool, lastAskAt: Date?, now: Date) -> Bool {
        guard workShifts >= levelUpMinShifts,
              !reviewed,
              !askedRecently(lastAskAt, now: now) else { return false }
        guard let lastStarAt else { return true }
        return now.timeIntervalSince(lastStarAt) >= starSheetCooldown
    }
}

@MainActor
final class ReviewPromptCenter: ObservableObject {
    static let shared = ReviewPromptCenter()

    @Published var pending: ReviewAskReason?

    private let defaults = UserDefaults.standard
    private enum Key {
        static let wroteAt = "review_wrote_at_v1"
        static let lastAskAt = "review_last_ask_at_v1"
        static let lastStarAt = "review_last_star_at_v1"
        static let milestoneAsked = "review_milestone_asked_v1"
    }

    private func date(_ key: String) -> Date? {
        let t = defaults.double(forKey: key)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// Done asking for good: tapped "Write a review", holds the verified
    /// reviewer badge, or has already seen the 30th-shift pop-up (the last
    /// ask anyone gets).
    private var reviewed: Bool {
        date(Key.wroteAt) != nil || VerifiedStatusService.shared.isVerified
            || defaults.bool(forKey: Key.milestoneAsked)
    }

    private func stamp(_ key: String, _ now: Date) {
        defaults.set(now.timeIntervalSince1970, forKey: key)
    }

    func afterPrestige(_ prestige: Int, now: Date = Date()) {
        guard ReviewAskPolicy.shouldAskAfterPrestige(reviewed: reviewed) else { return }
        present(.prestige(prestige), now: now)
    }

    func considerMilestone(workShifts: Int, now: Date = Date()) {
        guard pending == nil, ReviewAskPolicy.shouldAskAtMilestone(
            workShifts: workShifts,
            alreadyAsked: defaults.bool(forKey: Key.milestoneAsked),
            reviewed: reviewed,
            lastAskAt: date(Key.lastAskAt),
            now: now
        ) else { return }
        defaults.set(true, forKey: Key.milestoneAsked)
        present(.milestone, now: now)
    }

    func afterLevelUp(workShifts: Int, now: Date = Date()) {
        guard pending == nil, ReviewAskPolicy.shouldShowStarSheet(
            workShifts: workShifts,
            lastStarAt: date(Key.lastStarAt),
            reviewed: reviewed,
            lastAskAt: date(Key.lastAskAt),
            now: now
        ) else { return }
        stamp(Key.lastStarAt, now)
        stamp(Key.lastAskAt, now)
        AppActions.rateApp()
    }

    private func present(_ reason: ReviewAskReason, now: Date) {
        stamp(Key.lastAskAt, now)
        withAnimation(.easeOut(duration: 0.2)) { pending = reason }
    }

    func writeReview() {
        stamp(Key.wroteAt, Date())
        close()
        AppActions.openAppStoreWriteReview()
    }

    func close() {
        withAnimation(.easeOut(duration: 0.2)) { pending = nil }
    }
}

struct ReviewAskOverlay: View {
    let reason: ReviewAskReason
    @ObservedObject var center: ReviewPromptCenter

    var body: some View {
        HomePromptCard(
            pose: reason == .milestone ? .heart : .crown,
            title: reason.title,
            message: reason.message
        ) {
            Button("Write a review") {
                Haptics.lightTap()
                center.writeReview()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, AppSpacing.xxs)

            Button("Not Now") {
                Haptics.lightTap()
                center.close()
            }
            .font(AppTypography.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.subtext)
        }
    }
}
