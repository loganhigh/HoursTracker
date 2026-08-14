import Foundation

/// A saved location / job the user works at.
///
/// Job sites are a convenience layer for the Add Shift wizard: picking one
/// writes its `name` into `WorkEntry.locationName`, exactly as typing the name
/// by hand always has. `WorkEntry` is unchanged and stores no site id, so a
/// site can be renamed or deleted without disturbing shift history.
struct JobSite: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    /// Optional subtitle — an address, unit number, crew, whatever helps tell sites apart.
    var detail: String
    /// Optional city, used to group sites in the pickers. Free text rather
    /// than a fixed list — nobody's job sites fit someone else's taxonomy —
    /// but grouped case- and whitespace-insensitively so "calgary" and
    /// "Calgary " land in the same section.
    var city: String
    /// SF Symbol from `iconOptions`.
    var iconName: String
    var createdAt: Date
    var lastUsedAt: Date?

    static let defaultIcon = "mappin.and.ellipse"

    /// The fixed icon set offered when creating or editing a site.
    static let iconOptions: [String] = [
        "mappin.and.ellipse",
        "building.2",
        "hammer",
        "wrench.and.screwdriver",
        "truck.box",
        "shippingbox",
        "cross.case",
        "leaf"
    ]

    static let nameLimit = 120
    static let detailLimit = 200
    static let cityLimit = 80

    /// Saved sites allowed without Hour Tracker Pro. Pro is unlimited.
    static let freeLimit = 2

    init(
        id: String = UUID().uuidString,
        name: String,
        detail: String = "",
        city: String = "",
        iconName: String = JobSite.defaultIcon,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = JobSite.clean(name, limit: JobSite.nameLimit)
        self.detail = JobSite.clean(detail, limit: JobSite.detailLimit)
        self.city = JobSite.clean(city, limit: JobSite.cityLimit)
        self.iconName = JobSite.iconOptions.contains(iconName) ? iconName : JobSite.defaultIcon
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawName = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        let rawDetail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        let rawCity = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        let rawIcon = try c.decodeIfPresent(String.self, forKey: .iconName) ?? JobSite.defaultIcon
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = JobSite.clean(rawName, limit: JobSite.nameLimit)
        detail = JobSite.clean(rawDetail, limit: JobSite.detailLimit)
        city = JobSite.clean(rawCity, limit: JobSite.cityLimit)
        iconName = JobSite.iconOptions.contains(rawIcon) ? rawIcon : JobSite.defaultIcon
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }

    /// Trim and clamp free text at the model boundary.
    private static func clean(_ value: String, limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    /// Row subtitle: the user's own detail when set (only sites saved before
    /// the editor dropped that field have one), then the city — which is what
    /// makes a row readable in the picker's ungrouped Recent section — then
    /// usage context.
    var displaySubtitle: String {
        if !detail.isEmpty { return detail }
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCity.isEmpty { return trimmedCity }
        guard let lastUsedAt else { return "Not used yet" }
        return "Last used \(lastUsedAt.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// Section this site groups under. Empty city sorts into its own bucket.
    var cityGroupKey: String {
        city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Heading shown for the group — the site's own casing, or a fallback.
    var cityGroupTitle: String {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No city" : trimmed
    }

    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(trimmed)
            || detail.localizedCaseInsensitiveContains(trimmed)
            || city.localizedCaseInsensitiveContains(trimmed)
    }
}
