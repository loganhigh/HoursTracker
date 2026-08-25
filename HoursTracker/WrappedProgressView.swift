import SwiftUI

/// Instagram/Snapchat-style segmented progress bar: one capsule per slide,
/// filled for slides already seen, highlighted for the current slide, dim
/// for slides not yet reached. Purely presentational — takes the slide
/// count and current index, no knowledge of WrappedSlideType or stats.
struct WrappedProgressView: View {
    let slideCount: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(slideCount, 1), id: \.self) { index in
                Capsule()
                    .fill(index <= currentIndex ? Color.white : Color.white.opacity(0.28))
                    .frame(height: 3)
            }
        }
        .animation(.easeOut(duration: 0.2), value: currentIndex)
    }
}
