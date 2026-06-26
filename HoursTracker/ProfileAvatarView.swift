import SwiftUI

/// Circular avatar — local photo for the signed-in user, remote URL for friends, initials fallback.
struct ProfileAvatarView: View {
    let name: String
    let size: CGFloat
    var photoURL: String? = nil
    var uid: String? = nil
    var showsAccentRing: Bool = false

    @State private var loadedImage: UIImage?

    private var initials: String {
        BoardContentFilter.initials(from: name)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.accent.opacity(0.18))

            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.accent)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if showsAccentRing {
                Circle()
                    .stroke(AppTheme.Colors.accent.opacity(0.45), lineWidth: max(1, size * 0.02))
            }
        }
        .task(id: loadKey) {
            let manager = ProfilePhotoManager.shared
            if uid == AuthService.shared.user?.uid {
                loadedImage = manager.localImage
                return
            }
            guard let uid, photoURL != nil else {
                loadedImage = nil
                return
            }
            if let cached = manager.cachedFriendImage(for: uid) {
                loadedImage = cached
                return
            }
            loadedImage = await manager.loadFriendPhoto(uid: uid, urlString: photoURL)
        }
    }

    private var loadKey: String {
        "\(uid ?? "local")|\(photoURL ?? "")"
    }
}
