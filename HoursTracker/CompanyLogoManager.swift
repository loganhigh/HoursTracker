import Foundation
import UIKit
import Combine
import FirebaseAuth
import FirebaseStorage

/// Owns the local company logo (Hour Tracker Pro branding for PDF reports)
/// and uploads it to Firebase Storage. Mirrors `ProfilePhotoManager`'s
/// pattern exactly — resize/compress locally, persist to documentDirectory,
/// upload to Storage, cache the download URL in UserDefaults.
@MainActor
final class CompanyLogoManager: ObservableObject {
    static let shared = CompanyLogoManager()

    static let localFileName = "company_logo.jpg"
    private static let remoteURLKey = "company_logo_url"
    private static let remotePath = "profile/company_logo.jpg"
    private static let maxEdge: CGFloat = 512
    private static let jpegQuality: CGFloat = 0.82

    /// Loaded once at init from the local cache file — safe to read from a
    /// report export without ever touching the network.
    @Published private(set) var localImage: UIImage?

    private let storage = Storage.storage()

    private init() {
        localImage = Self.loadLocalImage()
    }

    var remoteLogoURL: String? {
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

    // MARK: - Logo

    /// Saves locally and uploads when signed in. Clears the remote logo when `image` is nil.
    func setLogo(_ image: UIImage?) async throws {
        if let image, let data = preparedJPEGData(from: image) {
            try persistLocalJPEG(data)
            try await uploadCurrentLogo(data: data)
        } else {
            try removeLocalLogo()
            try await deleteRemoteLogoIfNeeded()
        }
    }

    private func removeLocalLogo() throws {
        if let url = Self.localFileURL, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        localImage = nil
        UserDefaults.standard.removeObject(forKey: Self.remoteURLKey)
    }

    private func uploadCurrentLogo(data: Data) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = storage.reference().child("users/\(uid)/\(Self.remotePath)")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        UserDefaults.standard.set(url.absoluteString, forKey: Self.remoteURLKey)
    }

    private func deleteRemoteLogoIfNeeded() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = storage.reference().child("users/\(uid)/\(Self.remotePath)")
        try await ref.delete()
        UserDefaults.standard.removeObject(forKey: Self.remoteURLKey)
    }
}
