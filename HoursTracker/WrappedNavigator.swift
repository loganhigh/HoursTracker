import Foundation

/// Owns "which slide are we on" and the bounds rules around it. Extracted
/// from WrappedView so the navigation behavior (never advancing past the
/// last slide, never going below the first, clamping if the slide list is
/// smaller than expected) is unit-testable rather than trapped inside a
/// SwiftUI view's private methods.
struct WrappedNavigator: Equatable {
    let slides: [WrappedSlideType]
    private(set) var index: Int

    init(slides: [WrappedSlideType], index: Int = 0) {
        self.slides = slides
        // Clamp on the way in so an out-of-range starting index can't put
        // `currentSlide` out of bounds.
        self.index = slides.isEmpty ? 0 : min(max(index, 0), slides.count - 1)
    }

    var slideCount: Int { slides.count }

    var isFirst: Bool { index == 0 }
    var isLast: Bool { slides.isEmpty || index >= slides.count - 1 }

    /// nil only when there are no slides at all, which
    /// `WrappedSlideType.availableSlides(for:)` never produces (intro and
    /// final summary always exist) — but handled rather than force-unwrapped.
    var currentSlide: WrappedSlideType? {
        guard !slides.isEmpty else { return nil }
        return slides[min(max(index, 0), slides.count - 1)]
    }

    /// Advances one slide. Returns false (and changes nothing) when already
    /// on the last slide — the caller uses this to decide whether to
    /// dismiss instead of advancing.
    @discardableResult
    mutating func goNext() -> Bool {
        guard !isLast else { return false }
        index += 1
        return true
    }

    /// Steps back one slide. Returns false (and changes nothing) when
    /// already on the first slide.
    @discardableResult
    mutating func goPrevious() -> Bool {
        guard !isFirst else { return false }
        index -= 1
        return true
    }
}
