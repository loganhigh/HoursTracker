import Foundation
import UIKit

/// Pre-computed row for export. Built on main actor to avoid Swift concurrency issues.
private struct ExportRow {
    let date: Date
    let start: Date
    let end: Date
    let breakMinutes: Int
    let totalHours: Double
    let overtimeHours: Double
    let notes: String
    let location: String
}

/// Exports monthly reports as CSV or PDF. Runs off main thread.
final class ReportExportService {

    /// Export month data as CSV. Returns URL to temp file.
    func exportCSV(monthDate: Date, entries: [WorkEntry], store: HoursStore, companyName: String? = nil) async throws -> URL {
        let rows = buildExportRows(monthDate: monthDate, entries: entries, store: store)
        let company = companyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try await Task.detached(priority: .userInitiated) { [company] in
            let cal = Calendar.current
            guard let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)) else {
                throw ExportError.invalidMonth
            }
            var lines: [String] = []
            // Neutralize spreadsheet formula injection on free-text fields: prefix a
            // leading =, +, -, @, tab or CR with an apostrophe so a spreadsheet treats
            // the cell as literal text rather than a formula.
            let sanitize: (String) -> String = { value in
                var s = value
                if let first = s.first, "=+-@\t\r".contains(first) { s = "'" + s }
                return s.replacingOccurrences(of: "\"", with: "\"\"")
            }
            if !company.isEmpty {
                lines.append("Company,\"\(sanitize(company))\"")
            }
            let header = "Date,Start Time,End Time,Break (minutes),Total Hours,Location,Notes"
            lines.append(header)

            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd"
            let timeFmt = DateFormatter()
            timeFmt.dateFormat = "HH:mm"

            for row in rows {
                let dateStr = dateFmt.string(from: row.date)
                let startStr = timeFmt.string(from: row.start)
                let endStr = timeFmt.string(from: row.end)
                let totalHrs = String(format: "%.2f", row.totalHours)
                let loc = sanitize(row.location)
                let notes = sanitize(row.notes)
                lines.append("\(dateStr),\(startStr),\(endStr),\(row.breakMinutes),\(totalHrs),\"\(loc)\",\"\(notes)\"")
            }

            let csv = lines.joined(separator: "\n")
            let fileName = "hours_\(dateFmt.string(from: start)).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        }.value
    }

    /// Export month data as PDF. Returns URL to temp file.
    @MainActor
    func exportPDF(monthDate: Date, entries: [WorkEntry], store: HoursStore, companyName: String? = nil) async throws -> URL {
        let rows = buildExportRows(monthDate: monthDate, entries: entries, store: store)
        let totalHours = rows.reduce(0) { $0 + $1.totalHours }
        let overtimeHours = rows.reduce(0) { $0 + $1.overtimeHours }
        let daysWorked = Set(rows.map { Calendar.current.startOfDay(for: $0.date) }).count

        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)) else {
            throw ExportError.invalidMonth
        }
        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "MMMM yyyy"
        let monthTitle = monthFmt.string(from: start)
        let company = companyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let pdfData: Data = { [rows, totalHours, overtimeHours, daysWorked, monthTitle, company] in
            let pageWidth: CGFloat = 612
            let pageHeight: CGFloat = 792
            let margin: CGFloat = 50

            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            let data = renderer.pdfData { (ctx) in
                var y: CGFloat = margin

                func drawTitle(_ text: String, size: CGFloat = 18, bold: Bool = true) {
                    let font = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
                    let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
                    let attrStr = NSAttributedString(string: text, attributes: attr)
                    attrStr.draw(at: CGPoint(x: margin, y: y))
                    y += attrStr.size().height + 6
                }

                func drawLine() {
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: margin, y: y))
                    path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                    UIColor.lightGray.setStroke()
                    path.lineWidth = 0.5
                    path.stroke()
                    y += 12
                }

                ctx.beginPage()
                drawTitle(monthTitle)
                if !company.isEmpty {
                    drawTitle("Company: \(company)", size: 12, bold: false)
                }
                drawLine()

                drawTitle("Summary", size: 14)
                drawTitle("Total hours: \(String(format: "%.2f", totalHours))", size: 12, bold: false)
                drawTitle("Days worked: \(daysWorked)", size: 12, bold: false)
                if overtimeHours > 0 {
                    drawTitle("Overtime hours: \(String(format: "%.2f", overtimeHours))", size: 12, bold: false)
                }
                y += 12
                drawLine()

                drawTitle("Entries", size: 14)
                let dateFmt = DateFormatter()
                dateFmt.dateFormat = "MMM d, yyyy"
                let timeFmt = DateFormatter()
                timeFmt.dateFormat = "h:mm a"

                for row in rows {
                    if y > pageHeight - margin - 60 {
                        ctx.beginPage()
                        y = margin
                    }
                    let line1 = "\(dateFmt.string(from: row.date)) - \(timeFmt.string(from: row.start))/\(timeFmt.string(from: row.end)) (\(String(format: "%.2f", row.totalHours))h)" + (row.location.isEmpty ? "" : " - Location: (\(row.location))")
                    let font = UIFont.systemFont(ofSize: 10, weight: .regular)
                    let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
                    NSAttributedString(string: line1, attributes: attr).draw(at: CGPoint(x: margin, y: y))
                    y += 14
                    if !row.notes.isEmpty {
                        NSAttributedString(string: "  Notes: \(row.notes)", attributes: attr).draw(at: CGPoint(x: margin, y: y))
                        y += 14
                    }
                    y += 2
                }
            }
            return data
        }()

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM"
        let fileName = "hours_\(dateFmt.string(from: start)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try pdfData.write(to: url)
        return url
    }

    @MainActor
    private func formatLocation(entry: WorkEntry) -> String {
        if !entry.locationName.isEmpty, let lat = entry.latitude, let lon = entry.longitude {
            return "\(entry.locationName) (\(String(format: "%.5f", lat)), \(String(format: "%.5f", lon)))"
        }
        if !entry.locationName.isEmpty { return entry.locationName }
        if let lat = entry.latitude, let lon = entry.longitude {
            return "\(String(format: "%.5f", lat)), \(String(format: "%.5f", lon))"
        }
        if !entry.locationURL.isEmpty { return entry.locationURL }
        return ""
    }

    @MainActor
    private func buildExportRows(monthDate: Date, entries: [WorkEntry], store: HoursStore) -> [ExportRow] {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else {
            return []
        }
        return entries
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }
            .map { entry in
                let b = store.payBreakdown(for: entry)
                let loc = formatLocation(entry: entry)
                return ExportRow(
                    date: entry.date,
                    start: entry.start,
                    end: entry.end,
                    breakMinutes: entry.breakMinutes,
                    totalHours: entry.paidHours,
                    overtimeHours: b.overtimeHours,
                    notes: entry.notes,
                    location: loc
                )
            }
    }
}

enum ExportError: LocalizedError {
    case invalidMonth
    case writeFailed
    var errorDescription: String? { "Export failed. Please try again." }
}
