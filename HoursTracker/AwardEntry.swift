import Foundation

/// A saved award image with an optional label for finding it easily.
struct AwardEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    /// Filename of the image in the awards directory (e.g. "uuid.jpg").
    var filename: String
    /// User-defined label (e.g. "Employee of the Month", "Safety Award 2026").
    var label: String

    init(id: UUID = UUID(), filename: String, label: String = "") {
        self.id = id
        self.filename = filename
        self.label = label
    }
}
