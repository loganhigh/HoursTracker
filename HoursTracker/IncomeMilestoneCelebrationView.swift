import SwiftUI
import UIKit

/// Full-screen milestone moment: the card springs in, the number counts up,
/// a glow breathes behind it and confetti falls. Share renders a static
/// story-ratio copy of the card (milestone only — no other pay details).
struct IncomeMilestoneCelebrationView: View {
    let row: IncomeMilestoneProgress
    let currencyCode: String
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cardScale: CGFloat = 0.6
    @State private var cardOpacity: Double = 0
    @State private var countValue: Double = 0
    @State private var glowPulse = false
    @State private var confetti = false
    @State private var buttonsVisible = false
    @State private var shareImage: MilestoneShareImage?

    var body: some View {
        ZStack {
            MilestoneCardStyle.backdrop.ignoresSafeArea()

            RadialGradient(
                colors: [AppColors.gold.opacity(glowPulse ? 0.34 : 0.18), .clear],
                center: .center,
                startRadius: 10,
                endRadius: glowPulse ? 420 : 320
            )
            .ignoresSafeArea()
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                value: glowPulse
            )

            VStack(spacing: 28) {
                Spacer(minLength: 12)

                IncomeMilestoneCardFace(
                    milestone: row.milestone,
                    reachedDate: row.reachedDate,
                    displayValue: countValue,
                    currencyCode: currencyCode
                )
                .frame(maxWidth: 360)
                .aspectRatio(9.0 / 13.0, contentMode: .fit)
                .shadow(color: AppColors.gold.opacity(0.35), radius: glowPulse ? 36 : 22)
                .scaleEffect(cardScale)
                .opacity(cardOpacity)
                .padding(.horizontal, 28)

                Spacer(minLength: 12)

                HStack(spacing: 12) {
                    Button {
                        share()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        Haptics.lightTap()
                        onDismiss()
                    } label: {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .opacity(buttonsVisible ? 1 : 0)
                .offset(y: buttonsVisible ? 0 : 18)
            }

            ConfettiLayer(
                active: confetti,
                palette: [AppColors.gold, AppColors.goldDeep, AppColors.positive, .white, AppColors.accent],
                pieceCount: 60
            )
            .allowsHitTesting(false)
        }
        .sheet(item: $shareImage) { item in
            ShareSheet(items: [item.image]) { shareImage = nil }
        }
        .onAppear(perform: runEntrance)
    }

    private func runEntrance() {
        Haptics.success()
        let target = row.milestone.threshold
        guard !reduceMotion else {
            cardScale = 1
            cardOpacity = 1
            countValue = target
            buttonsVisible = true
            return
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.68)) {
            cardScale = 1
            cardOpacity = 1
        }
        withAnimation(.easeOut(duration: 1.6).delay(0.25)) {
            countValue = target
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.9)) {
            buttonsVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            confetti = true
            glowPulse = true
        }
    }

    private func share() {
        Haptics.lightTap()
        let card = IncomeMilestoneShareStory(
            milestone: row.milestone,
            reachedDate: row.reachedDate,
            currencyCode: currencyCode
        )
        .frame(width: 360, height: 640)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3 // 1080 x 1920
        if let image = renderer.uiImage {
            shareImage = MilestoneShareImage(image: image)
        }
    }
}

private struct MilestoneShareImage: Identifiable {
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

/// The card itself. `displayValue` is animatable so the headline number
/// counts up; the static share copy just passes the threshold.
struct IncomeMilestoneCardFace: View, Animatable {
    let milestone: IncomeMilestone
    let reachedDate: Date?
    var displayValue: Double
    let currencyCode: String

    var animatableData: Double {
        get { displayValue }
        set { displayValue = newValue }
    }

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
