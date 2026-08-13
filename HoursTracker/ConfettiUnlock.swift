import SwiftUI
import Combine

// Stores which badge names were already celebrated, so you only see it once.
final class BadgeUnlockTracker: ObservableObject {
    @AppStorage("celebrated_badges_v1") private var celebratedCSV: String = ""

    func hasCelebrated(_ key: String) -> Bool {
        celebratedSet.contains(key)
    }

    func markCelebrated(_ key: String) {
        var s = celebratedSet
        s.insert(key)
        celebratedCSV = s.sorted().joined(separator: "|")
    }

    private var celebratedSet: Set<String> {
        Set(celebratedCSV.split(separator: "|").map(String.init))
    }
}

struct ConfettiUnlockSheet: View {
    let title: String
    let subtitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false

    var body: some View {
        ZStack {
            AppTheme.Colors.bg.ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()

                BadgeGlowHero(systemImage: "sparkles")

                Text(title)
                    .font(AppTheme.Typography.h1)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(AppTheme.Typography.sub)
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)

                PrimaryButton("Nice 😎", systemImage: "checkmark.circle.fill") {
                    dismiss()
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)

                Spacer()
            }

            if !reduceMotion {
                ConfettiLayer(active: burst)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            Haptics.success()
            if !reduceMotion {
                withAnimation(AppMotion.Spring.smooth) {
                    burst = true
                }
            }
        }
    }
}

struct BadgeUnlockCelebrationSheet: View {
    let badgeName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false

    var body: some View {
        ZStack {
            AppTheme.Colors.bg.ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()

                BadgeGlowHero(systemImage: "medal.fill")

                Text("Badge Unlocked")
                    .font(AppTheme.Typography.h1)
                    .multilineTextAlignment(.center)

                Text(badgeName)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.accent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)

                Text("New achievement added to your collection.")
                    .font(AppTheme.Typography.sub)
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)

                PrimaryButton("Continue", systemImage: "arrow.right.circle.fill") {
                    dismiss()
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)

                Spacer()
            }

            if !reduceMotion {
                ConfettiLayer(active: burst)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            Haptics.success()
            if !reduceMotion {
                withAnimation(AppMotion.Spring.smooth) {
                    burst = true
                }
            }
        }
    }
}

/// A one-shot confetti burst.
///
/// Driven by a timeline rather than per-piece `.animation(value:)`: the old
/// version tied position, spin, and opacity to a single `easeOut` on `active`,
/// which meant the pieces faded 1 → 0 across the *whole* fall. Because easeOut
/// front-loads its progress, they were down to roughly a tenth opacity by the
/// time they reached mid-screen — visible for a fraction of the drop and
/// effectively invisible for the rest of it.
///
/// Driving it from a clock instead separates the fall from the fade, so the
/// pieces stay opaque all the way down and only fade as they exit, and it
/// draws every piece in one Canvas instead of animating N separate views.
struct ConfettiLayer: View {
    let active: Bool
    var palette: [Color]? = nil
    var pieceCount: Int = 42

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [ConfettiPiece] = []
    @State private var startDate: Date?

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation(minimumInterval: nil, paused: startDate == nil)) { timeline in
                Canvas { context, size in
                    guard let startDate else { return }
                    let elapsed = timeline.date.timeIntervalSince(startDate)
                    for piece in pieces {
                        draw(piece, at: elapsed, in: size, context: context)
                    }
                }
            }
            .ignoresSafeArea()
            .onChange(of: active) { _, isActive in
                guard isActive else {
                    startDate = nil
                    return
                }
                launch()
            }
            .onAppear {
                // Covers a layer that is mounted with `active` already true —
                // an onChange alone would never fire and the burst would be
                // silently skipped.
                if active { launch() }
            }
        }
    }

    private func launch() {
        // Re-rolled per burst, so celebrating twice doesn't replay an
        // identical pattern. Built locally and measured before being stored,
        // rather than assigning to @State and reading it straight back.
        let fresh = (0..<pieceCount).map { _ in ConfettiPiece.random(palette: palette) }
        let runtime = (fresh.map { $0.delay + $0.duration }.max() ?? 0) + 0.1

        pieces = fresh
        let launchedAt = Date()
        startDate = launchedAt

        DispatchQueue.main.asyncAfter(deadline: .now() + runtime) {
            // Stops the clock once the burst is spent. Comparing against the
            // date this call launched keeps a newer burst from being cut short.
            if startDate == launchedAt {
                startDate = nil
            }
        }
    }

    private func draw(_ piece: ConfettiPiece, at elapsed: Double, in size: CGSize, context: GraphicsContext) {
        let t = elapsed - piece.delay
        guard t >= 0 else { return }
        let progress = t / piece.duration
        guard progress <= 1 else { return }

        let width = piece.size
        let height = piece.size * 2.2

        // Falling accelerates. The old easeOut decelerated, which read as
        // drifting rather than dropping.
        let fall = pow(progress, 1.4)
        let y = -height + (size.height + height * 2) * fall

        // Drift toward the target column, with a slow sway on the way down.
        let drift = piece.startX + (piece.endX - piece.startX) * progress
        let sway = sin(progress * .pi * 2 * piece.swayCycles) * piece.swayWidth
        let x = drift * size.width + sway

        // Opaque for the fall; a quick fade in on release and out on exit, so
        // pieces never pop in or vanish mid-screen.
        let alpha: Double
        switch progress {
        case ..<0.06: alpha = progress / 0.06
        case 0.85...: alpha = (1 - progress) / 0.15
        default:      alpha = 1
        }

        var ctx = context
        ctx.opacity = alpha
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: .degrees(piece.spin * progress))
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        ctx.fill(
            Path(roundedRect: rect, cornerRadius: 2, style: .continuous),
            with: .color(piece.color)
        )
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let startX: CGFloat
    let endX: CGFloat
    let spin: Double
    let size: CGFloat
    let duration: Double
    let delay: Double
    let color: Color
    /// Horizontal sway while falling, in points and full cycles per drop.
    let swayWidth: CGFloat
    let swayCycles: Double

    static func random(palette: [Color]? = nil) -> ConfettiPiece {
        let defaultPalette: [Color] = [
            .green, .blue, .purple, .yellow, .orange, .pink, .mint, .teal
        ]
        let colors = palette ?? defaultPalette
        return ConfettiPiece(
            startX: CGFloat.random(in: 0.05...0.95),
            endX: CGFloat.random(in: 0.05...0.95),
            spin: Double.random(in: 120...920),
            size: CGFloat.random(in: 6...12),
            duration: Double.random(in: 1.6...2.6),
            // Spread wider than the old 0.25 so the burst reads as a shower
            // rather than one clump.
            delay: Double.random(in: 0.0...0.55),
            color: (colors.randomElement() ?? .purple).opacity(0.95),
            swayWidth: CGFloat.random(in: 6...22),
            swayCycles: Double.random(in: 0.5...1.5)
        )
    }
}
