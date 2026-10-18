import SwiftUI

// MARK: - Owl motion
//
// The body stays still except for the poses where moving it reads as the
// pose itself (cheer/trophy/crown/streak hop, sleep dozes). Elsewhere only
// parts move: the eyes blink and, on wave/bell/point, the wing swings from
// the shoulder. All of it is computed from the clock, so nothing stacks or
// drifts when a view reappears. Off under Reduce Motion.

enum OwlMotion {
    enum Body { case still, hop, doze }
    enum Wing { case wave, ring, nudge }

    static func body(for pose: OwlPose) -> Body {
        switch pose {
        case .cheer, .trophy, .crown, .streak: return .hop
        case .sleep: return .doze
        default: return .still
        }
    }

    static func wing(for pose: OwlPose) -> Wing? {
        switch pose {
        case .wave: return .wave
        case .bell: return .ring
        case .point: return .nudge
        default: return nil
        }
    }

    struct Frame {
        var dy: CGFloat = 0
        var angle: Double = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
    }

    /// 0→1→0 over [start, start + length), else 0.
    static func bump(_ u: Double, _ start: Double, _ length: Double) -> Double {
        guard u >= start, u < start + length else { return 0 }
        return sin(.pi * (u - start) / length)
    }

    static func cycle(_ t: Double, _ period: Double) -> Double {
        let u = (t / period).truncatingRemainder(dividingBy: 1)
        return u < 0 ? u + 1 : u
    }

    /// Whole-body transform (hop / doze), scaled to the owl's height.
    static func bodyFrame(_ motion: Body, at t: Double, height: CGFloat) -> Frame {
        var f = Frame()
        switch motion {
        case .still:
            break
        case .hop:
            let u = cycle(t, 2.6)
            f.dy = -10 * (height / 150) * bump(u, 0.08, 0.22)
            let land = bump(u, 0.30, 0.10), crouch = bump(u, 0.0, 0.08)
            f.scaleY = 1 - 0.08 * land - 0.05 * crouch
            f.scaleX = 1 + 0.06 * land + 0.03 * crouch
        case .doze:
            let slow = (sin(2 * .pi * t / 3.6) + 1) / 2
            f.scaleY = 1 + 0.04 * slow
            f.angle = -2 + 2 * slow
        }
        return f
    }

    /// Wing rotation in degrees around the shoulder.
    static func wingAngle(_ motion: Wing, at t: Double) -> Double {
        switch motion {
        case .wave:
            // Two or three friendly waves, then a rest.
            let u = cycle(t, 3.4)
            return -13 * sin(2 * .pi * 2.5 * u / 0.55) * bump(u, 0, 0.55)
        case .ring:
            // A quick shake of the bell.
            let u = cycle(t, 2.8)
            return 11 * sin(2 * .pi * 5 * u / 0.32) * bump(u, 0, 0.32)
        case .nudge:
            // Two little pokes toward whatever it's pointing at.
            let u = cycle(t, 2.6)
            return -7 * bump(u, 0, 0.12) - 5 * bump(u, 0.16, 0.12)
        }
    }

    /// Eyelid closure 0 (open) … 1 (shut). A blink every ~4 s, a double
    /// blink every third time.
    static func blink(at t: Double) -> Double {
        let period = 4.2
        let u = cycle(t, period)
        let n = Int(floor(t / period))
        var closed = bump(u, 0, 0.036)
        if n % 3 == 0 { closed = max(closed, bump(u, 0.06, 0.036)) }
        return closed
    }
}

// MARK: - Eyelids

/// Eyelids drawn over the iris rects: a face-coloured lid that drops from the
/// top, with a lash line once it's nearly shut.
struct OwlEyelids: View {
    let rig: OwlRig
    let closed: Double

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(rig.eyes.enumerated()), id: \.offset) { _, eye in
                // A little larger than the iris so its dark rim is covered.
                let w = eye.width * geo.size.width * 1.16
                let h = eye.height * geo.size.height * 1.16
                let cx = eye.midX * geo.size.width
                let cy = eye.midY * geo.size.height
                ZStack(alignment: .top) {
                    Ellipse()
                        .fill(Color(hex: rig.lidHex))
                        .frame(width: w, height: h)
                        .scaleEffect(x: 1, y: max(0.001, closed), anchor: .top)
                    if closed > 0.7 {
                        Capsule()
                            .fill(Color(hex: 0x3A2316))
                            .frame(width: w * 0.86, height: max(1.5, h * 0.09))
                            .offset(y: h * 0.5)
                            .opacity((closed - 0.7) / 0.3)
                    }
                }
                .frame(width: w, height: h, alignment: .top)
                .position(x: cx, y: cy)
            }
        }
        .allowsHitTesting(false)
    }
}
