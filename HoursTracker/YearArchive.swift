import Foundation

/// Archived work entries for a completed calendar year.
struct YearArchive: Identifiable, Codable, Equatable {
    var id: Int { year }
    let year: Int
    var entries: [WorkEntry]
}
