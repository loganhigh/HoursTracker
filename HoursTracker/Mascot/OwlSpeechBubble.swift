import SwiftUI

// MARK: - OwlSpeechBubble
//
// One short line from Otto. Quiet-card recipe: bubble fill, hairline stroke,
// no glow. The tail points at the owl. VoiceOver reads the text; the owl
// itself stays hidden.

struct OwlSpeechBubble: View {
    // `nonisolated`: a plain value type nested in a main-actor view would
    // otherwise get a main-actor-isolated Equatable conformance (warning).
    nonisolated enum Tail: Equatable {
        /// Owl sits to the left of the bubble.
        case leading
        /// Owl sits to the right of the bubble.
        case trailing
        /// Owl sits below the bubble.
        case bottom
    }

    let text: String
    var tail: Tail = .leading

    var body: some View {
        let shape = BubbleShape(tail: tail)
        Text(text)
            .appText(.subheadline)
            .foregroundStyle(AppColors.text)
            .multilineTextAlignment(tail == .bottom ? .center : .leading)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .padding(edgeForTail, BubbleShape.tailDepth)
            .background(shape.fill(AppColors.bubble))
            .overlay(shape.stroke(AppColors.stroke, lineWidth: 1))
    }

    private var edgeForTail: Edge.Set {
        switch tail {
        case .leading: return .leading
        case .trailing: return .trailing
        case .bottom: return .bottom
        }
    }
}

/// Rounded rectangle with a small triangular tail, drawn as one outline so the
/// hairline stroke runs continuously around the tail.
private struct BubbleShape: Shape {
    static let tailDepth: CGFloat = 6
    static let tailHalfWidth: CGFloat = 6

    let tail: OwlSpeechBubble.Tail

    func path(in rect: CGRect) -> Path {
        let d = Self.tailDepth
        let hw = Self.tailHalfWidth
        var body = rect
        switch tail {
        case .leading: body.origin.x += d; body.size.width -= d
        case .trailing: body.size.width -= d
        case .bottom: body.size.height -= d
        }
        let r = min(AppRadius.sm, body.height / 2, body.width / 2)
        let minX = body.minX, maxX = body.maxX, minY = body.minY, maxY = body.maxY

        var p = Path()
        p.move(to: CGPoint(x: minX + r, y: minY))
        p.addLine(to: CGPoint(x: maxX - r, y: minY))
        p.addQuadCurve(to: CGPoint(x: maxX, y: minY + r), control: CGPoint(x: maxX, y: minY))
        if tail == .trailing {
            let midY = body.midY
            p.addLine(to: CGPoint(x: maxX, y: midY - hw))
            p.addLine(to: CGPoint(x: maxX + d, y: midY))
            p.addLine(to: CGPoint(x: maxX, y: midY + hw))
        }
        p.addLine(to: CGPoint(x: maxX, y: maxY - r))
        p.addQuadCurve(to: CGPoint(x: maxX - r, y: maxY), control: CGPoint(x: maxX, y: maxY))
        if tail == .bottom {
            let midX = body.midX
            p.addLine(to: CGPoint(x: midX + hw, y: maxY))
            p.addLine(to: CGPoint(x: midX, y: maxY + d))
            p.addLine(to: CGPoint(x: midX - hw, y: maxY))
        }
        p.addLine(to: CGPoint(x: minX + r, y: maxY))
        p.addQuadCurve(to: CGPoint(x: minX, y: maxY - r), control: CGPoint(x: minX, y: maxY))
        if tail == .leading {
            let midY = body.midY
            p.addLine(to: CGPoint(x: minX, y: midY + hw))
            p.addLine(to: CGPoint(x: minX - d, y: midY))
            p.addLine(to: CGPoint(x: minX, y: midY - hw))
        }
        p.addLine(to: CGPoint(x: minX, y: minY + r))
        p.addQuadCurve(to: CGPoint(x: minX + r, y: minY), control: CGPoint(x: minX, y: minY))
        p.closeSubpath()
        return p
    }
}
