import Foundation
import UIKit
import Combine
import FirebaseAuth
import FirebaseStorage

/// Owns the local profile photo, uploads to Firebase Storage, and caches friend avatars.
@MainActor
final class ProfilePhotoManager: ObservableObject {
    static let shared = ProfilePhotoManager()

    static let localFileName = "profile_avatar.jpg"
    private static let remoteURLKey = "profile_photo_url"
    private static let remotePath = "profile/avatar.jpg"
    private static let maxEdge: CGFloat = 512
    private static let jpegQuality: CGFloat = 0.82

    @Published private(set) var localImage: UIImage?

    private let storage = Storage.storage()
    private var friendCache: [String: UIImage] = [:]
    private var inFlightFriendLoads: [String: Task<UIImage?, Never>] = [:]

    private init() {
        localImage = Self.loadLocalImage()
    }

    var remotePhotoURL: String? {
        UserDefaults.standard.string(forKey: Self.remoteURLKey)
    }

    // MARK: - Local

    private static var localFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(localFileName)
    }

    private static func loadLocalImage() -> UIImage? {
        guard let url = localFileURL,
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private func persistLocalJPEG(_ data: Data) throws {
        guard let url = Self.localFileURL else { return }
        try data.write(to: url, options: .atomic)
        localImage = UIImage(data: data)
    }

    private func preparedJPEGData(from image: UIImage) -> Data? {
        let resized = Self.resized(image, maxEdge: Self.maxEdge)
        return resized.jpegData(compressionQuality: Self.jpegQuality)
    }

    private static func resized(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxEdge / max(size.width, size.height))
        guard scale < 1 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Own photo

    /// Saves locally and uploads when signed in. Clears remote photo when `image` is nil.
    func setPhoto(_ image: UIImage?) async throws {
        if let image, let data = preparedJPEGData(from: image) {
            try persistLocalJPEG(data)
            try await uploadCurrentPhoto(data: data)
        } else {
            try removeLocalPhoto()
            try await deleteRemotePhotoIfNeeded()
        }
    }

    func reloadLocalPhoto() {
        localImage = Self.loadLocalImage()
    }

    /// Uploads an existing on-device photo after sign-in (e.g. legacy local avatars).
    func uploadLocalPhotoIfNeeded() async {
        guard Auth.auth().currentUser != nil,
              remotePhotoURL == nil,
              let url = Self.localFileURL,
              let data = try? Data(contentsOf: url) else { return }
        try? await uploadCurrentPhoto(data: data)
    }

    private func removeLocalPhoto() throws {
        if let url = Self.localFileURL, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        localImage = nil
        UserDefaults.standard.removeObject(forKey: Self.remoteURLKey)
    }

    private func uploadCurrentPhoto(data: Data) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = storage.reference().child("users/\(uid)/\(Self.remotePath)")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        UserDefaults.standard.set(url.absoluteString, forKey: Self.remoteURLKey)
    }

    private func deleteRemotePhotoIfNeeded() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = storage.reference().child("users/\(uid)/\(Self.remotePath)")
        try await ref.delete()
        UserDefaults.standard.removeObject(forKey: Self.remoteURLKey)
    }

    func deleteAllPhotoData() async {
        friendCache.removeAll()
        try? removeLocalPhoto()
        try? await deleteRemotePhotoIfNeeded()
    }

    func clearFriendCache() {
        friendCache.removeAll()
        inFlightFriendLoads.removeAll()
    }

    // MARK: - Friend photos

    func cachedFriendImage(for uid: String) -> UIImage? {
        friendCache[uid]
    }

    func loadFriendPhoto(uid: String, urlString: String?) async -> UIImage? {
        if let cached = friendCache[uid] { return cached }
        guard let urlString, let url = URL(string: urlString) else { return nil }

        if let existing = inFlightFriendLoads[uid] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { return nil }
                await MainActor.run {
                    self.friendCache[uid] = image
                    _ = self.inFlightFriendLoads.removeValue(forKey: uid)
                }
                return image
            } catch {
                await MainActor.run {
                    _ = self.inFlightFriendLoads.removeValue(forKey: uid)
                }
                return nil
            }
        }
        inFlightFriendLoads[uid] = task
        return await task.value
    }
}
