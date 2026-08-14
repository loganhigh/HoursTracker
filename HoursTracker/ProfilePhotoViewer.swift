import SwiftUI

/// Full-screen look at your own avatar, reached from the You tab's photo menu.
///
/// Deliberately plain: the avatar is already a 512px square, so there is
/// nothing to zoom into and no gallery to page through — this exists so
/// "view" is a real option beside "change", not a second editor.
struct ProfilePhotoViewer: View {
    let image: UIImage?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(AppSpacing.lg)
            } else {
                // Only reachable if the photo is cleared while this is open.
                Text("No photo")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.lightTap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Circle().fill(.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .padding(AppSpacing.md)
        }
    }
}
