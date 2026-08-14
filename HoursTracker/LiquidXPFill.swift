import SwiftUI

// MARK: - Liquid XP fill
//
// The XP bar's fill as liquid instead of a stiff capsule. The view owns its
// own motion: hand it a target progress and the fill pours toward it on a
// slightly under-damped spring — overshooting, sloshing against the far edge,
// and settling — while the leading edge ripples with an amplitude tied to how
// fast the liquid is actually moving. A settled bar pauses its clock and
// renders one static frame, so idle Home/You screens burn nothing.
//
// Reduce Motion renders the plain flat fill, exactly as the bars used to.

struct LiquidXPFill: View {
    /// Target fill 0…1. Set it and the liquid chases it; no external
    /// withAnimation needed (or wanted — the physics IS the animation).
    let progress: Double
    /// Fill colors, leading → trailing.
    var colors: [Color] = [AppColors.accent, AppColors.accent.opacity(0.75)]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Spring state, integrated per frame. Displacement chases `progress`;
    // velocity feeds the wave amplitude so a big pour makes big waves.
    @State private var displayed: Double = 0
    @State private var velocity: Double = 0
    /// Slosh energy: spiked by arriving motion, decays exponentially.
    @State private var energy: Double = 0
    @State private var lastTick: TimeInterval?
    @State private var settled = true
    @State private var seeded = false

    var body: some View {
        if reduceMotion {
            flatFill
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: settled)) { timeline in
                Canvas { context, size in
                    draw(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                }
                .onChange(of: timeline.date) { _, _ in
                    step(now: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            .onAppear {
                if !seeded {
                    seeded = true
                    // First sight of the bar starts at the real value — the
                    // pour is for CHANGES, not for every appearance.
                    displayed = progress
                }
                nudgeIfNeeded()
            }
            .onChange(of: progress) { _, _ in nudgeIfNeeded() }
        }
    }

    private var flatFill: some View {
        GeometryReader { geo in
            Capsule()
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(width: max(0, geo.size.width * progress))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Physics

    private func nudgeIfNeeded() {
        guard abs(progress - displayed) > 0.0005 || energy > 0.001 else { return }
        lastTick = nil
        settled = false
    }

    private func step(now: TimeInterval) {
        let dt = min(max(now - (lastTick ?? now), 0), 1.0 / 20.0)
        lastTick = now
        guard dt > 0 else { return }

        // Under-damped spring: stiffness high enough to feel like pouring,
        // damping low enough to overshoot once and slosh back.
        let stiffness = 42.0
        let damping = 7.5
        let accel = (progress - displayed) * stiffness - velocity * damping
        velocity += accel * dt
        displayed += velocity * dt

        // Motion feeds the waves; stillness starves them.
        energy = max(energy * pow(0.18, dt), min(abs(velocity) * 2.2, 1))

        if abs(progress - displayed) < 0.0008, abs(velocity) < 0.004, energy < 0.004 {
            displayed = progress
            velocity = 0
            energy = 0
            settled = true
        }
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let level = CGFloat(min(max(displayed, 0), 1))
        guard level > 0.001, size.width > 1, size.height > 1 else { return }

        let fillX = size.width * level
        // Wave amplitude scales with bar height and live slosh energy, so the
        // 6pt Home strip ripples subtly while the 10pt You bar rolls more.
        let amplitude = min(size.height * 0.30, 1 + size.height * 0.28 * CGFloat(energy))
        let clip = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
        context.clip(to: clip)

        // Two waves, out of phase and at different frequencies, along the
        // liquid's leading edge — one reads as a line, two read as water.
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        let steps = max(6, Int(size.height / 2))
        for i in 0...steps {
            let y = size.height * CGFloat(i) / CGFloat(steps)
            let w1 = sin((y / size.height) * .pi * 2.1 + time * 7.0)
            let w2 = sin((y / size.height) * .pi * 3.7 - time * 4.6 + 1.3)
            let x = fillX + amplitude * (0.65 * w1 + 0.35 * w2)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: 0))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.closeSubpath()

        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: colors),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: 0)
            )
        )

        // A faint crest along the surface while the liquid is moving.
        if energy > 0.02 {
            var crest = Path()
            for i in 0...steps {
                let y = size.height * CGFloat(i) / CGFloat(steps)
                let w1 = sin((y / size.height) * .pi * 2.1 + time * 7.0)
                let w2 = sin((y / size.height) * .pi * 3.7 - time * 4.6 + 1.3)
                let x = fillX + amplitude * (0.65 * w1 + 0.35 * w2)
                if i == 0 { crest.move(to: CGPoint(x: x, y: 0)) }
                else { crest.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(
                crest,
                with: .color(.white.opacity(0.35 * Double(energy))),
                lineWidth: 1
            )
        }
    }
}
