import SwiftUI

// MARK: - Level-up celebration sections
//
// The rewards list and spark field drawn by LevelUpCelebrationView, split out
// to keep that file under the 500-line limit.

// MARK: - Rewards list

struct LevelRewardView: View {
    let rewards: [LevelUpCoordinator.Reward]
    let tier: PrestigeTheme.Tier

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text("Unlocked")
                .appText(.eyebrow)
                .foregroundStyle(AppColors.subtext)

            ForEach(rewards) { reward in
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: reward.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tier.highlight)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                                .fill(tier.primary.opacity(0.16))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(reward.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.text)
                        Text(reward.detail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.subtext)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .stroke(tier.primary.opacity(0.25), lineWidth: 0.5)
                        )
                )
            }
        }
        .frame(maxWidth: 320)
    }
}

// MARK: - Spark field

/// A restrained falling-spark layer — two dozen small tinted points raining
/// from above the badge down to the Continue button, no confetti, no
/// rainbows. The layer renders beneath the celebration's content stack, so a
/// spark reaching the button's band slips behind it; the terminal fade is for
/// the strays that fall beside the button rather than over it.
struct CelebrationSparkField: View {
    let active: Bool
    let tint: Color

    /// Fall band, as fractions of the field's height. The end sits just past
    /// the Continue button's top edge so sparks are covered by it mid-fade.
    private static let topY: Double = 0.10
    private static let endY: Double = 0.93

    private struct Spark {
        let x: Double       // 0…1 horizontal position
        let phase: Double   // 0…1 offset into the fall cycle
        let duration: Double
        let size: CGFloat
        let drift: Double   // horizontal wander over one fall, in points
    }

    private static let sparks: [Spark] = (0..<24).map { i in
        var generator = SeededRandom(seed: UInt64(i) &* 0x9E3779B97F4A7C15)
        return Spark(
            x: generator.next(in: 0.08...0.92),
            phase: generator.next(in: 0...1),
            duration: generator.next(in: 2.6...4.2),
            size: CGFloat(generator.next(in: 2...4.5)),
            drift: generator.next(in: -26...26)
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !active)) { timeline in
            Canvas { context, size in
                guard active else { return }
                let now = timeline.date.timeIntervalSinceReferenceDate
                for spark in Self.sparks {
                    // Continuous cycle: each spark is somewhere mid-fall at
                    // any moment, so the rain has no synchronized waves.
                    let cycle = (now / spark.duration + spark.phase)
                        .truncatingRemainder(dividingBy: 1)
                    // Slight ease-in so the drop reads as gravity.
                    let progress = pow(cycle, 1.35)

                    let y = size.height * (Self.topY + (Self.endY - Self.topY) * progress)
                    let x = size.width * spark.x + spark.drift * progress

                    // Fade in at release, fade out on arrival at the button.
                    let alpha: Double
                    switch cycle {
                    case ..<0.10: alpha = 0.85 * (cycle / 0.10)
                    case 0.90...: alpha = 0.85 * ((1 - cycle) / 0.10)
                    default:      alpha = 0.85
                    }

                    let rect = CGRect(
                        x: x - spark.size / 2,
                        y: y - spark.size / 2,
                        width: spark.size,
                        height: spark.size
                    )
                    context.fill(Circle().path(in: rect), with: .color(tint.opacity(alpha)))
                }
            }
        }
        // Soft ramp on activation, so mid-fall sparks don't pop in abruptly.
        .opacity(active ? 1 : 0)
        .animation(.easeIn(duration: 0.5), value: active)
    }

    /// Deterministic per-spark randomness — a seeded generator keeps the
    /// field identical across appearances.
    private struct SeededRandom {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
        mutating func next(in range: ClosedRange<Double>) -> Double {
            let unit = Double(next() % 10_000) / 10_000
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }
    }
}
