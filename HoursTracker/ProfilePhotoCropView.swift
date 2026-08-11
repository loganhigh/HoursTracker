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
        HStack(spacing: AppSpacing.sm) {
            Button {
                Haptics.lightTap()
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Text("Move and Scale")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                Haptics.success()
                onConfirm(renderCroppedImage())
            } label: {
                // Filled pill: the confirm action shouldn't read as a passive
                // label on a black screen.
                Text("Choose")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textOnAccent)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule(style: .continuous).fill(AppColors.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xs)
    }

    // MARK: Interactive stage

    private var imageStage: some View {
        // Color.black is the size-setting layer here, with the photo layered
        // over it. An overlay never grows its parent, whereas putting the
        // photo directly in a ZStack made the stack take the photo's full
        // scaled size — which for any real photo is far wider than the
        // screen. `.clipped()` only clips drawing, not layout, so that width
        // propagated up the VStack and pushed Cancel/Choose off both edges.
        Color.black
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: displayedImageSize.width, height: displayedImageSize.height)
                    .offset(liveOffset)
            }
            .overlay {
                CircularCropScrim(viewportSize: viewportSize)
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    .frame(width: viewportSize, height: viewportSize)
            }
            .clipped()
            .contentShape(Rectangle())
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
