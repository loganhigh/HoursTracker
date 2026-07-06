import Foundation
import UIKit

enum DataExportScope: String, CaseIterable, Identifiable {
    case all = "All Data"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }
}

struct DataExportPayload: Codable {
    let generatedAt: Date
    let scope: String
    let selectedYear: Int?
    let selectedMonth: String?
    let entries: [WorkEntry]
    let yearArchives: [YearArchive]
    let paySettings: PaySettings
    let payHistoryEntries: [PayHistoryEntry]
    let certificates: [CertificateEntry]
    let awards: [AwardEntry]
}

final class DataExportService {
    func exportCSV(
        scope: DataExportScope,
        selectedDate: Date,
        store: HoursStore
    ) throws -> URL {
        let calendar = Calendar.current
        let allEntries = store.allEntriesIncludingArchive()

        let filteredEntries: [WorkEntry]
        let selectedYear: Int?
        let selectedMonth: String?
        let includedArchives: [YearArchive]

        switch scope {
        case .all:
            filteredEntries = allEntries
            selectedYear = nil
            selectedMonth = nil
            includedArchives = store.yearArchives
        case .month:
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                filteredEntries = []
                selectedYear = nil
                selectedMonth = nil
                includedArchives = []
                break
            }
            filteredEntries = allEntries.filter { $0.date >= monthStart && $0.date < monthEnd }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM"
            selectedMonth = f.string(from: monthStart)
            selectedYear = calendar.component(.year, from: monthStart)
            includedArchives = []
        case .year:
            let year = calendar.component(.year, from: selectedDate)
            filteredEntries = allEntries.filter { calendar.component(.year, from: $0.date) == year }
            selectedYear = year
            selectedMonth = nil
            includedArchives = []
        }

        let sortedEntries = filteredEntries.sorted { $0.date > $1.date }
        let csv = buildCSV(
            scope: scope,
            selectedYear: selectedYear,
            selectedMonth: selectedMonth,
            entries: sortedEntries,
            archivesCount: includedArchives.count
        )
        guard let data = csv.data(using: .utf8) else {
            throw NSError(domain: "DataExportService", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode CSV export."
            ])
        }

        let dateKey = Self.fileDateFormatter.string(from: Date())
        let fileName: String
        switch scope {
        case .all: fileName = "hours_data_all_\(dateKey).csv"
        case .month:
            let f = DateFormatter()
            f.dateFormat = "yyyy_MM"
            fileName = "hours_data_month_\(f.string(from: selectedDate))_\(dateKey).csv"
        case .year:
            let year = calendar.component(.year, from: selectedDate)
            fileName = "hours_data_year_\(year)_\(dateKey).csv"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    func exportPDF(
        scope: DataExportScope,
        selectedDate: Date,
        store: HoursStore
    ) throws -> URL {
        let calendar = Calendar.current
        let allEntries = store.allEntriesIncludingArchive()

        let filteredEntries: [WorkEntry]
        let scopeLabel: String

        switch scope {
        case .all:
            filteredEntries = allEntries
            scopeLabel = "All Data"
        case .month:
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                filteredEntries = []
                scopeLabel = "Month"
                break
            }
            filteredEntries = allEntries.filter { $0.date >= monthStart && $0.date < monthEnd }
            let f = DateFormatter()
            f.dateFormat = "MMMM yyyy"
            scopeLabel = f.string(from: monthStart)
        case .year:
            let year = calendar.component(.year, from: selectedDate)
            filteredEntries = allEntries.filter { calendar.component(.year, from: $0.date) == year }
            scopeLabel = String(year)
        }

        let sortedEntries = filteredEntries.sorted { $0.date > $1.date }
        let data = buildPDF(scopeLabel: scopeLabel, entries: sortedEntries)

        let dateKey = Self.fileDateFormatter.string(from: Date())
        let fileName: String
        switch scope {
        case .all: fileName = "hours_data_all_\(dateKey).pdf"
        case .month:
            let f = DateFormatter()
            f.dateFormat = "yyyy_MM"
            fileName = "hours_data_month_\(f.string(from: selectedDate))_\(dateKey).pdf"
        case .year:
            let year = calendar.component(.year, from: selectedDate)
            fileName = "hours_data_year_\(year)_\(dateKey).pdf"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func buildPDF(scopeLabel: String, entries: [WorkEntry]) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "MMM d, yyyy"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"

        let totalHours = entries.reduce(0.0) { $0 + $1.paidHours }
        let daysWorked = Set(entries.map { Calendar.current.startOfDay(for: $0.date) }).count

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        return renderer.pdfData { ctx in
            var y: CGFloat = margin

            let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
            let subtitleFont = UIFont.systemFont(ofSize: 12, weight: .medium)
            let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
            let headerFont = UIFont.systemFont(ofSize: 14, weight: .semibold)

            func newPageIfNeeded(need: CGFloat = 60) {
                if y > pageHeight - margin - need {
                    ctx.beginPage()
                    y = margin
                }
            }

            func drawText(_ text: String, font: UIFont, color: UIColor = .black) {
                let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let str = NSAttributedString(string: text, attributes: attr)
                let rect = CGRect(x: margin, y: y, width: contentWidth, height: .greatestFiniteMagnitude)
                let boundingRect = str.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin], context: nil)
                str.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: boundingRect.height))
                y += boundingRect.height + 4
            }

            func drawLine() {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                UIColor.lightGray.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                y += 10
            }

            ctx.beginPage()

            drawText("Hours Tracker — \(scopeLabel)", font: titleFont)
            let genFmt = DateFormatter()
            genFmt.dateFormat = "MMM d, yyyy 'at' h:mm a"
            drawText("Generated: \(genFmt.string(from: Date()))", font: bodyFont, color: .darkGray)
            y += 4
            drawLine()

            drawText("Summary", font: headerFont)
            drawText("Total Hours: \(String(format: "%.2f", totalHours))", font: subtitleFont)
            drawText("Days Worked: \(daysWorked)", font: subtitleFont)
            drawText("Entries: \(entries.count)", font: subtitleFont)
            y += 8
            drawLine()

            drawText("Entries", font: headerFont)
            y += 4

            for entry in entries {
                newPageIfNeeded()
                let dateStr = dateFmt.string(from: entry.date)

                if entry.isOffDay {
                    let reason = entry.offDayReason.isEmpty ? "Off Day" : entry.offDayReason
                    drawText("\(dateStr) — \(reason)", font: bodyFont, color: .darkGray)
                } else {
                    let startStr = timeFmt.string(from: entry.start)
                    let endStr = timeFmt.string(from: entry.end)
                    let hrs = String(format: "%.2f", entry.paidHours)
                    var line = "\(dateStr)  |  \(startStr) – \(endStr)  |  \(hrs)h"
                    if entry.breakMinutes > 0 {
                        line += "  |  Break: \(entry.breakMinutes)m"
                    }
                    drawText(line, font: bodyFont)

                    if !entry.locationName.isEmpty {
                        drawText("  Location: \(entry.locationName)", font: bodyFont, color: .darkGray)
                    }
                    if !entry.notes.isEmpty {
                        drawText("  Notes: \(entry.notes)", font: bodyFont, color: .darkGray)
                    }
                }
                y += 2
            }
        }
    }

    private func buildCSV(
        scope: DataExportScope,
        selectedYear: Int?,
        selectedMonth: String?,
        entries: [WorkEntry],
        archivesCount: Int
    ) -> String {
        let iso = ISO8601DateFormatter()
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        let timeOnly = DateFormatter()
        timeOnly.dateFormat = "HH:mm"

        var lines: [String] = []
        lines.append("meta_key,meta_value")
        lines.append(csvRow(["generated_at", iso.string(from: Date())]))
        lines.append(csvRow(["scope", scope.rawValue]))
        lines.append(csvRow(["selected_year", selectedYear.map { String($0) } ?? ""]))
        lines.append(csvRow(["selected_month", selectedMonth ?? ""]))
        lines.append(csvRow(["entries_count", String(entries.count)]))
        lines.append(csvRow(["included_archives_count", String(archivesCount)]))
        lines.append("")

        lines.append("id,date,start_time,end_time,break_minutes,paid_hours,is_off_day,off_day_reason,is_holiday,notes,location_name,location_url,latitude,longitude")
        for entry in entries {
            lines.append(csvRow([
                entry.id.uuidString,
                dateOnly.string(from: entry.date),
                timeOnly.string(from: entry.start),
                timeOnly.string(from: entry.end),
                String(entry.breakMinutes),
                String(format: "%.2f", entry.paidHours),
                entry.isOffDay ? "true" : "false",
                entry.offDayReason,
                entry.isHoliday ? "true" : "false",
                entry.notes,
                entry.locationName,
                entry.locationURL,
                entry.latitude.map { String($0) } ?? "",
                entry.longitude.map { String($0) } ?? ""
            ]))
        }

        return lines.joined(separator: "\n")
    }

    private func csvRow(_ values: [String]) -> String {
        values.map { value in
            // Neutralize spreadsheet formula injection: a cell that a spreadsheet
            // would evaluate as a formula (starts with = + - @, or a tab/CR) is
            // prefixed with an apostrophe so it's treated as literal text.
            var sanitized = value
            if let first = sanitized.first, "=+-@\t\r".contains(first) {
                sanitized = "'" + sanitized
            }
            let escaped = sanitized.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }.joined(separator: ",")
    }

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()
}
