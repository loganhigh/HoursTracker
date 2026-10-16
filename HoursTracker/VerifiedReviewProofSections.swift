import SwiftUI

// MARK: - Verified proof sheet sections
//
// The loading card, screenshot preview and sent confirmation drawn by
// VerifiedReviewProofSheet, split out to keep that file under 500 lines.

// MARK: - Loading card

/// A shimmering placeholder in the shape of the preview it's about to become,
/// so the layout doesn't jump when the real screenshot lands.
struct LoadingScreenshotCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat = 190

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            .fill(AppColors.card.opacity(0.55))
            .frame(height: height)
            .overlay { shimmer }
            .overlay {
                VStack(spacing: AppSpacing.xs) {
                    ProgressView()
                        .tint(AppColors.accent)
                    Text("Preparing your screenshot…")
                        .font(AppTypography.metricLabel.weight(.semibold))
                        .foregroundStyle(AppColors.subtext)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColors.stroke, lineWidth: 0.5)
            )
            .accessibilityLabel("Loading screenshot")
    }

    @ViewBuilder
    private var shimmer: some View {
        if !reduceMotion {
            TimelineView(.animation) { timeline in
                let cycle = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.6) / 1.6
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, AppColors.text.opacity(0.07), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.45)
                    .offset(x: -geo.size.width * 0.45 + geo.size.width * 1.45 * cycle)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Preview of the picked shot

struct ScreenshotPreview: View {
    let image: UIImage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        // Color.clear sets the size and the photo rides on top: an overlay
        // never grows its parent, so a tall screenshot can't stretch the sheet.
        Color.clear
            .frame(height: 190)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColors.stroke, lineWidth: 0.5)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColors.accent)
                    .background(Circle().fill(AppColors.bg))
                    .padding(8)
                    .scaleEffect(appeared ? 1 : 0.2)
                    .opacity(appeared ? 1 : 0)
            }
            .onAppear {
                withAnimation(AppMotion.animation(AppMotion.Spring.celebratory, reduceMotion: reduceMotion).delay(0.08)) {
                    appeared = true
                }
            }
    }
}

// MARK: - Sent

/// The badge pops in and pulses once. Deliberately does NOT claim the mark is
/// live — it's granted by hand after the screenshot is read.
struct SentConfirmation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            VerifiedBadgeView(variant: .shimmer, size: 44)
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)

            Text("Sent!")
                .font(.title3.weight(.heavy))
                .foregroundStyle(AppColors.text)

            Text("Your screenshot is in our review queue. Once it's approved the mark shows up on its own — no need to check back.")
                .font(AppTypography.metricLabel.weight(.medium))
                .foregroundStyle(AppColors.subtext)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColors.accent.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(AppColors.accent.opacity(0.3), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(AppMotion.animation(AppMotion.Spring.celebratory, reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
    }
}
