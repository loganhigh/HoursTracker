import SwiftUI

/// Circular avatar — local photo for the signed-in user, remote URL for friends, initials fallback.
struct ProfileAvatarView: View {
    let name: String
    let size: CGFloat
    var photoURL: String? = nil
    var uid: String? = nil
    var showsAccentRing: Bool = false

    @State private var loadedImage: UIImage?
    /// Observed so saving a new avatar redraws every one of these on screen at
    /// once. Copying `localImage` into `@State` inside the task below meant the
    /// new photo only appeared after a relaunch: the task is keyed on
    /// uid + photoURL, and neither changes when you replace your own photo
    /// (Storage hands back the same download URL for the same path).
    @ObservedObject private var photoManager = ProfilePhotoManager.shared

    private var initials: String {
        BoardContentFilter.initials(from: name)
    }

    /// Matches the task's own test below, including the signed-out case where
    /// both sides are nil and the local photo is still ours to show.
    private var isCurrentUser: Bool {
        uid == AuthService.shared.user?.uid
    }

    /// Own avatar reads the manager live; friends' come from the async load.
    private var displayedImage: UIImage? {
        isCurrentUser ? photoManager.localImage : loadedImage
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.accent.opacity(0.18))

            if let displayedImage {
                Image(uiImage: displayedImage)
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
            // Our own photo is read straight off the manager, so there is
            // nothing to fetch here.
            if isCurrentUser { return }
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
