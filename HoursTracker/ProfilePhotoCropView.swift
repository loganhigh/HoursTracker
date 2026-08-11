import SwiftUI

// MARK: - Profile photo crop
//
// Full-screen "move and scale" step between picking a photo and saving it as
// the profile avatar. Shows the whole picked image with a dimmed scrim
// outside a circular viewport matching how ProfileAvatarView will display it;
// drag to reposition, pinch to zoom. Confirming renders exactly what's inside
// the circle's bounding square into a single square UIImage, so
// ProfilePhotoManager and every consumer downstream still just handle "one
// square photo" — cropping is a presentation step, not a new data shape.

struct ProfilePhotoCropView: View {
    let image: UIImage
    var onCancel: () -> Void
    var onConfirm: (UIImage) -> Void

    /// The circular viewport's diameter on screen, in points.
    private let viewportSize: CGFloat = 300
    /// The rendered output's edge length, in pixels. Matches
    /// ProfilePhotoManager's own resize ceiling so confirming here never
    /// triggers a second downscale pass.
    private let outputSize: CGFloat = 512
    private let minUserScale: CGFloat = 1
    private let maxUserScale: CGFloat = 4

    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnifyDelta: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Scale that exactly covers the viewport with the image's shorter edge —
    /// the same "aspect fill" formula `.scaledToFill()` uses, computed by hand
    /// because the output render below has to reproduce this same transform
    /// off-screen.
    private var baseScale: CGFloat {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return 1 }
        return max(viewportSize / size.width, viewportSize / size.height)
    }

    private var liveScale: CGFloat { scale * magnifyDelta }

    private var liveOffset: CGSize {
        CGSize(width: offset.width + dragTranslation.width, height: offset.height + dragTranslation.height)
    }

    private var displayedImageSize: CGSize {
        CGSize(
            width: image.size.width * baseScale * liveScale,
            height: image.size.height * baseScale * liveScale
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            imageStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer(minLength: 0)

            Text("Drag to reposition · Pinch to zoom")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, AppSpacing.xl)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
    }

    private var header: some View {
        HStack {
            Button("Cancel") {
                Haptics.lightTap()
                onCancel()
            }
            .foregroundStyle(.white)

            Spacer(minLength: AppSpacing.sm)

            Text("Move and Scale")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: AppSpacing.sm)

            Button("Choose") {
                Haptics.success()
                onConfirm(renderCroppedImage())
            }
            .fontWeight(.bold)
            .foregroundStyle(AppColors.accent)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
    }

    // MARK: Interactive stage

    private var imageStage: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: displayedImageSize.width, height: displayedImageSize.height)
                .offset(liveOffset)

            CircularCropScrim(viewportSize: viewportSize)
                .allowsHitTesting(false)

            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: viewportSize, height: viewportSize)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .clipped()
        .gesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let proposed = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )
                withAnimation(reduceMotion ? nil : AppMotion.Spring.snappy) {
                    offset = clampedOffset(proposed, scale: scale)
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .updating($magnifyDelta) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let newScale = min(max(scale * value, minUserScale), maxUserScale)
                withAnimation(reduceMotion ? nil : AppMotion.Spring.snappy) {
                    scale = newScale
                    offset = clampedOffset(offset, scale: newScale)
                }
            }
    }

    /// Keeps the image covering the viewport at all times — the crop can
    /// never reveal empty space around its edges.
    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let displayed = CGSize(
            width: image.size.width * baseScale * scale,
            height: image.size.height * baseScale * scale
        )
        let maxX = max(0, (displayed.width - viewportSize) / 2)
        let maxY = max(0, (displayed.height - viewportSize) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    // MARK: Output

    /// Replays the exact on-screen composition (base fill scale + user scale
    /// + pan offset) into an off-screen square canvas at `outputSize`, so the
    /// result is pixel-for-pixel what sat inside the circle — no separate
    /// crop-rect math to keep in sync with the interactive transform above.
    private func renderCroppedImage() -> UIImage {
        let renderScaleFactor = outputSize / viewportSize
        let drawSize = CGSize(
            width: image.size.width * baseScale * scale * renderScaleFactor,
            height: image.size.height * baseScale * scale * renderScaleFactor
        )
        let drawOrigin = CGPoint(
            x: outputSize / 2 - drawSize.width / 2 + offset.width * renderScaleFactor,
            y: outputSize / 2 - drawSize.height / 2 + offset.height * renderScaleFactor
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outputSize, height: outputSize),
            format: format
        )
        return renderer.image { _ in
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }
}

// MARK: - Scrim with a circular hole

/// A dark scrim covering the whole stage except a circular hole at its
/// center, so the user sees the full photo with everything outside the crop
/// dimmed rather than hard-clipped — the surrounding context makes it obvious
/// what repositioning will bring into frame.
private struct CircularCropScrim: View {
    let viewportSize: CGFloat

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geo.size))
                path.addEllipse(in: CGRect(
                    x: geo.size.width / 2 - viewportSize / 2,
                    y: geo.size.height / 2 - viewportSize / 2,
                    width: viewportSize,
                    height: viewportSize
                ))
            }
            .fill(Color.black.opacity(0.75), style: FillStyle(eoFill: true))
        }
    }
}
