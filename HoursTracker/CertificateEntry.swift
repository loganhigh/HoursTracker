import Foundation

/// A saved certificate image with an optional label for finding it easily.
struct CertificateEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    /// Filename of the image in the certificates directory (e.g. "uuid.jpg").
    var filename: String
    /// User-defined label (e.g. "Forklift cert", "Safety 2024").
    var label: String

    init(id: UUID = UUID(), filename: String, label: String = "") {
        self.id = id
        self.filename = filename
        self.label = label
    }
}
