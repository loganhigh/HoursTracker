import SwiftUI

// MARK: - Owl motion
//
// Per-pose idle motion for the flat owl art: the whole image moves (rock,
// hop, pulse, breathe…) since the poses are single drawings. Driven straight
// from the clock, so it never stacks or drifts when a view reappears, and a
// tap adds a quick squash-and-hop. Off under Reduce Motion.

enum OwlMotion {
    case breathe, rock, hop, pulse, shake, ring, peek, doze

    init(pose: OwlPose) {
        switch pose {
        case .wave, .point: self = .rock
        case .cheer, .trophy, .crown, .streak: self = .hop
        case .heart: self = .pulse
        case .oops: self = .shake
        case .bell: self = .ring
        case .peek: self = .peek
        case .sleep: self = .doze
        default: self = .breathe
        }
    }

    struct Frame {
        var dy: CGFloat = 0
        var dx: CGFloat = 0
        var angle: Double = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
    }

    /// The transform at time `t` (seconds), for an owl `height` points tall.
    func frame(at t: Double, height: CGFloat) -> Frame {
        let k = height / 150 // motion scales with the owl's size
        var f = Frame()
        func cycle(_ period: Double) -> Double { (t / period).truncatingRemainder(dividingBy: 1) }
        /// 0→1→0 over the window [start, start+length) of a cycle, else 0.
        func bump(_ u: Double, _ start: Double, _ length: Double) -> Double {
            guard u >= start, u < start + length else { return 0 }
            return sin(.pi * (u - start) / length)
        }
        let breath = (sin(2 * .pi * t / 2.4) + 1) / 2

        switch self {
        case .breathe:
            f.scaleY = 1 + 0.022 * breath
            f.scaleX = 1 - 0.008 * breath
            f.angle = 4 * sin(2 * .pi * cycle(5.2) / 0.16) * bump(cycle(5.2), 0, 0.16)
        case .doze:
            let slow = (sin(2 * .pi * t / 3.6) + 1) / 2
            f.scaleY = 1 + 0.04 * slow
            f.angle = -2 + 2 * slow
        case .rock:
            let u = cycle(3.2)
            f.angle = 7 * sin(2 * .pi * 3 * u / 0.5) * bump(u, 0, 0.5)
            f.scaleY = 1 + 0.015 * breath
        case .hop:
            let u = cycle(2.6)
            f.dy = -10 * k * bump(u, 0.08, 0.22)
            let land = bump(u, 0.30, 0.10), crouch = bump(u, 0.0, 0.08)
            f.scaleY = 1 - 0.08 * land - 0.05 * crouch
            f.scaleX = 1 + 0.06 * land + 0.03 * crouch
        case .pulse:
            let u = cycle(1.6)
            let beat = bump(u, 0, 0.12) + 0.7 * bump(u, 0.18, 0.12)
            f.scaleX = 1 + 0.06 * beat
            f.scaleY = 1 + 0.06 * beat
        case .shake:
            let u = cycle(3.8)
            f.dx = 3 * k * sin(2 * .pi * 4 * u / 0.22) * bump(u, 0, 0.22)
            f.scaleY = 1 + 0.015 * breath
        case .ring:
            let u = cycle(3.0)
            f.angle = 9 * sin(2 * .pi * 5 * u / 0.3) * bump(u, 0, 0.3)
        case .peek:
            let u = cycle(4.0)
            f.dy = -4 * k * bump(u, 0.05, 0.45)
            f.angle = 5 * bump(u, 0.2, 0.25)
        }
        return f
    }
}

/// Applies `OwlMotion` plus the appear pop and tap bounce.
struct OwlMotionModifier: ViewModifier {
    let motion: OwlMotion
    let height: CGFloat
    let enabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var tapTime: Date?
    /// Desynchronises owls that appear together.
    @State private var seed = Double.random(in: 0..<10)

    func body(content: Content) -> some View {
        if enabled && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate + seed
                var f = motion.frame(at: t, height: height)
                let _ = applyTap(&f, now: timeline.date)
                content
                    .scaleEffect(x: f.scaleX, y: f.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(f.angle), anchor: .bottom)
                    .offset(x: f.dx, y: f.dy)
            }
            .scaleEffect(appeared ? 1 : 0.8, anchor: .bottom)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                Haptics.lightTap()
                tapTime = Date()
            })
        } else {
            content
        }
    }

    /// A 0.45 s squash, hop and settle after a tap, layered on the idle frame.
    private func applyTap(_ f: inout OwlMotion.Frame, now: Date) {
        guard let tapTime else { return }
        let e = now.timeIntervalSince(tapTime)
        guard e >= 0, e < 0.45 else { return }
        let u = e / 0.45
        let squash = u < 0.2 ? sin(.pi * u / 0.2) : 0
        let lift = u >= 0.15 && u < 0.75 ? sin(.pi * (u - 0.15) / 0.6) : 0
        let land = u >= 0.75 ? sin(.pi * (u - 0.75) / 0.25) : 0
        f.scaleY *= 1 - 0.12 * squash - 0.06 * land
        f.scaleX *= 1 + 0.08 * squash + 0.04 * land
        f.dy -= 14 * (height / 150) * lift
    }
}
