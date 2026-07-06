import Foundation

/// A single promotion / pay raise record for career progression.
struct PayHistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    /// Company name (e.g. "Acme Corp").
    var companyName: String
    /// Year of the role/rate (e.g. 2023).
    var year: Int
    /// Job title (e.g. "Labourer", "Operator", "Foreman").
    var jobTitle: String
    /// Hourly rate at that time.
    var hourlyRate: Double
    /// Currency code (e.g. "USD", "CAD").
    var currencyCode: String
    /// How many years the user has worked at this company (for anniversary celebrations).
    var yearsWorkedAtCompany: Int?

    init(id: UUID = UUID(), companyName: String = "", year: Int, jobTitle: String, hourlyRate: Double, currencyCode: String, yearsWorkedAtCompany: Int? = nil) {
        self.id = id
        self.companyName = companyName
        self.year = year
        self.jobTitle = jobTitle
        self.hourlyRate = hourlyRate
        self.currencyCode = currencyCode
        self.yearsWorkedAtCompany = yearsWorkedAtCompany
    }

    enum CodingKeys: String, CodingKey {
        case id, companyName, year, jobTitle, hourlyRate, currencyCode, yearsWorkedAtCompany
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        companyName = try c.decodeIfPresent(String.self, forKey: .companyName) ?? ""
        year = try c.decode(Int.self, forKey: .year)
        jobTitle = try c.decode(String.self, forKey: .jobTitle)
        hourlyRate = try c.decode(Double.self, forKey: .hourlyRate)
        currencyCode = try c.decode(String.self, forKey: .currencyCode)
        yearsWorkedAtCompany = try c.decodeIfPresent(Int.self, forKey: .yearsWorkedAtCompany)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(companyName, forKey: .companyName)
        try c.encode(year, forKey: .year)
        try c.encode(jobTitle, forKey: .jobTitle)
        try c.encode(hourlyRate, forKey: .hourlyRate)
        try c.encode(currencyCode, forKey: .currencyCode)
        try c.encodeIfPresent(yearsWorkedAtCompany, forKey: .yearsWorkedAtCompany)
    }
}
