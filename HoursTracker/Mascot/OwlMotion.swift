import SwiftUI

// MARK: - Owl motion
//
// The body stays still except for the poses where moving it reads as the
// pose itself (cheer/trophy/streak hop, sleep dozes, peek pops up from
// behind the edge). Elsewhere only parts move: the eyes blink, the wing
// swings from the shoulder on wave/bell/point, the crown wobbles and the
// map pin bounces. All of it is computed from the clock, so nothing stacks or
// drifts when a view reappears. Off under Reduce Motion.

enum OwlMotion {
    enum Body { case still, hop, doze, peekaboo }
    enum Wing { case wave, ring, nudge }
    enum Prop { case wobble, bounce, scribble, sweep, sparkle }

    static func body(for pose: OwlPose) -> Body {
        switch pose {
        case .cheer, .trophy, .streak: return .hop
        case .sleep: return .doze
        case .peek: return .peekaboo
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

    static func prop(for pose: OwlPose) -> Prop? {
        switch pose {
        case .crown: return .wobble
        case .pin: return .bounce
        case .clipboard: return .scribble
        case .search: return .sweep
        case .buddies: return .sparkle
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
        case .still, .peekaboo:
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

    /// Prop transform (crown wobble, map-pin bounce) around its pivot.
    static func propFrame(_ motion: Prop, at t: Double) -> Frame {
        var f = Frame()
        switch motion {
        case .wobble:
            let u = cycle(t, 3.2)
            f.angle = 7 * sin(2 * .pi * 2 * u / 0.4) * bump(u, 0, 0.4)
        case .bounce:
            let u = cycle(t, 2.6)
            let stretch = bump(u, 0, 0.14), land = bump(u, 0.14, 0.1)
            f.scaleY = 1 + 0.1 * stretch - 0.08 * land
            f.scaleX = 1 - 0.05 * stretch + 0.06 * land
            f.angle = 5 * sin(2 * .pi * 2 * u / 0.25) * bump(u, 0.24, 0.25)
        case .scribble:
            // The pencil writes a few quick strokes, then pauses.
            let u = cycle(t, 2.4)
            f.angle = 6 * sin(2 * .pi * 6 * u / 0.5) * bump(u, 0, 0.5)
        case .sweep:
            // The magnifying glass slowly scans side to side.
            f.angle = 5 * sin(2 * .pi * t / 3.0)
        case .sparkle:
            // The high-five "!" marks pop with each clap.
            let u = cycle(t, 1.8)
            let pop = bump(u, 0, 0.16) + 0.6 * bump(u, 0.2, 0.14)
            f.scaleX = 1 + 0.35 * pop
            f.scaleY = 1 + 0.35 * pop
        }
        return f
    }

    /// How far below its edge the peek owl is, as a fraction of its height,
    /// `t` seconds after it appeared: hidden, pops up with a little
    /// overshoot, looks around, ducks back down.
    static func peekOffset(sinceAppear t: Double) -> Double {
        let u = cycle(t, 7)
        func backOut(_ x: Double) -> Double {
            let c1 = 1.70158, c3 = c1 + 1
            return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
        }
        switch u {
        case ..<0.12: return 1
        case ..<0.2: return 1 - backOut((u - 0.12) / 0.08)
        case ..<0.84: return 0
        case ..<0.9:
            let x = (u - 0.84) / 0.06
            return x * x
        default: return 1
        }
    }

    /// Eyelid closure 0 (open) … 1 (shut). A blink every ~4 s, a double
    /// blink every third time.
    static func blink(at t: Double) -> Double {
        let period = 3.4
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

// MARK: - Floating hearts (heart pose)

/// Two small hearts drifting up from the heart the owl is holding, so the
/// pose has life without moving the body.
struct FloatingHearts: View {
    let t: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<2, id: \.self) { i in
                let u = OwlMotion.cycle(t + Double(i) * 1.3, 2.6)
                if u < 0.6 {
                    let p = u / 0.6
                    Image(systemName: "heart.fill")
                        .font(.system(size: max(10, height * 0.16), weight: .bold))
                        .foregroundStyle(Color(hex: 0xEF5A5A))
                        .opacity(sin(.pi * p))
                        .scaleEffect(0.6 + 0.4 * p)
                        .position(x: geo.size.width * (i == 0 ? 0.62 : 0.4) + CGFloat(sin(p * 6)) * 3,
                                  y: geo.size.height * (0.5 - 0.42 * p))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
