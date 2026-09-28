import SwiftUI
import UIKit

/// The milestone card design and its static story-ratio share image
/// (milestone only — no other pay details), shared from the Milestones card.
struct MilestoneShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Style

/// Fixed dark palette so the card (and the shared image) look the same in
/// light and dark mode.
enum MilestoneCardStyle {
    static let backdrop = LinearGradient(
        colors: [Color(hex: 0x14102A), Color(hex: 0x07070D)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let cardFill = LinearGradient(
        colors: [Color(hex: 0x2A2150), Color(hex: 0x130F26)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let border = LinearGradient(
        colors: [AppColors.gold.opacity(0.9), AppColors.goldDeep.opacity(0.25), AppColors.gold.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Card face

/// The card itself, as drawn in the share image.
struct IncomeMilestoneCardFace: View {
    let milestone: IncomeMilestone
    let reachedDate: Date?
    let displayValue: Double
    let currencyCode: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("Hour Tracker")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
            }

            Spacer(minLength: 16)

            ZStack {
                Circle()
                    .fill(AppColors.gold.opacity(0.16))
                    .frame(width: 84, height: 84)
                Circle()
                    .stroke(AppColors.goldGradient, lineWidth: 2)
                    .frame(width: 84, height: 84)
                Image(systemName: milestone.icon)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(AppColors.goldGradient)
            }

            Text("MILESTONE UNLOCKED")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundStyle(AppColors.gold)
                .padding(.top, 18)

            Text(IncomeMilestoneFormat.value(displayValue, kind: milestone.kind, currencyCode: currencyCode))
                .font(.system(size: 60, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 6)

            Text(milestone.categoryLabel)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))

            Spacer(minLength: 16)

            if let reachedDate {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text("Reached \(IncomeMilestoneFormat.date(reachedDate))")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.08)))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(MilestoneCardStyle.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(MilestoneCardStyle.border, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Share story (static, 9:16)

struct IncomeMilestoneShareStory: View {
    let milestone: IncomeMilestone
    let reachedDate: Date?
    let currencyCode: String

    /// 1080 x 1920 image of the card for sharing.
    @MainActor
    static func render(row: IncomeMilestoneProgress, currencyCode: String) -> UIImage? {
        let story = IncomeMilestoneShareStory(
            milestone: row.milestone,
            reachedDate: row.reachedDate,
            currencyCode: currencyCode
        )
        .frame(width: 360, height: 640)
        let renderer = ImageRenderer(content: story)
        renderer.scale = 3
        return renderer.uiImage
    }

    var body: some View {
        ZStack {
            MilestoneCardStyle.backdrop
            RadialGradient(
                colors: [AppColors.gold.opacity(0.28), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 320
            )
            VStack(spacing: 22) {
                Spacer(minLength: 0)
                IncomeMilestoneCardFace(
                    milestone: milestone,
                    reachedDate: reachedDate,
                    displayValue: milestone.threshold,
                    currencyCode: currencyCode
                )
                .frame(width: 300, height: 430)
                .shadow(color: AppColors.gold.opacity(0.35), radius: 24)
                Text("Tracked with Hour Tracker")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
            }
        }
    }
}
