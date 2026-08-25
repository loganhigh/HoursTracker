import SwiftUI

/// Story-style tap/swipe navigation surface. Renders `content` and overlays
/// invisible left/right tap zones (left third = previous, right two-thirds =
/// next — matches Instagram/Snapchat's split) plus a horizontal drag
/// gesture as a secondary way to navigate. Bounds-checking (not advancing
/// past the last slide, not going below zero) is the caller's
/// responsibility via `onNext`/`onPrevious` — this view only reports intent,
/// it never owns the current index.
struct WrappedStoryContainer<Content: View>: View {
    let onNext: () -> Void
    let onPrevious: () -> Void
    @ViewBuilder let content: () -> Content

    /// Minimum horizontal drag distance before it counts as a swipe rather
    /// than a tap — keeps a slightly-off-axis tap from being misread as a
    /// swipe, which would otherwise fight with the tap zones below.
    private let swipeThreshold: CGFloat = 60

    var body: some View {
        GeometryReader { geo in
            ZStack {
                content()

                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width * 0.35)
                        .onTapGesture(perform: onPrevious)

                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onNext)
                }
            }
            .gesture(
                DragGesture(minimumDistance: swipeThreshold)
                    .onEnded { value in
                        if value.translation.width < -swipeThreshold {
                            onNext()
                        } else if value.translation.width > swipeThreshold {
                            onPrevious()
                        }
                    }
            )
        }
    }
}
