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

/// Summary + rows for a single report date range.
private struct ExportReport {
    let title: String
    let rows: [ExportRow]
    let totalHours: Double
    let overtimeHours: Double
    let daysWorked: Int
}

/// Exports monthly/weekly reports as CSV or PDF. Runs off main thread.
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
    /// `logoImage` is drawn in the header alongside the company name when provided.
    @MainActor
    func exportPDF(
        monthDate: Date,
        entries: [WorkEntry],
        store: HoursStore,
        companyName: String? = nil,
        logoImage: UIImage? = nil
    ) async throws -> URL {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else {
            throw ExportError.invalidMonth
        }
        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "MMMM yyyy"
        let report = buildReport(
            title: monthFmt.string(from: start),
            range: DateInterval(start: start, end: end),
            entries: entries,
            store: store
        )

        let pdfData = Self.renderPDFData(report: report, companyName: companyName, logoImage: logoImage)

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM"
        let fileName = "hours_\(dateFmt.string(from: start)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try pdfData.write(to: url)
        return url
    }

    /// Export the calendar week containing `date` (Sun/Mon start per the
    /// user's `Calendar.current`) as PDF. Returns URL to temp file.
    /// `logoImage` is drawn in the header alongside the company name when provided.
    @MainActor
    func exportPDF(
        weekOf date: Date,
        entries: [WorkEntry],
        store: HoursStore,
        companyName: String? = nil,
        logoImage: UIImage? = nil
    ) async throws -> URL {
        let cal = Calendar.current
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: date)?.start,
              let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else {
            throw ExportError.invalidRange
        }
        let lastDay = cal.date(byAdding: .day, value: -1, to: weekEnd) ?? weekEnd

        let startFmt = DateFormatter()
        startFmt.dateFormat = "MMM d"
        let endFmt = DateFormatter()
        endFmt.dateFormat = "MMM d, yyyy"
        let title = "Week of \(startFmt.string(from: weekStart)) – \(endFmt.string(from: lastDay))"

        let report = buildReport(
            title: title,
            range: DateInterval(start: weekStart, end: weekEnd),
            entries: entries,
            store: store
        )

        let pdfData = Self.renderPDFData(report: report, companyName: companyName, logoImage: logoImage)

        let fileFmt = DateFormatter()
        fileFmt.dateFormat = "yyyy-MM-dd"
        let fileName = "hours_week_\(fileFmt.string(from: weekStart)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try pdfData.write(to: url)
        return url
    }

    // MARK: - PDF rendering (shared by monthly + weekly)

    private static func renderPDFData(report: ExportReport, companyName: String?, logoImage: UIImage?) -> Data {
        let company = companyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let logoSize: CGFloat = 40

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        return renderer.pdfData { ctx in
            var y: CGFloat = margin

            func drawTitle(_ text: String, size: CGFloat = 18, bold: Bool = true, x: CGFloat = margin) {
                let font = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
                let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
                let attrStr = NSAttributedString(string: text, attributes: attr)
                attrStr.draw(at: CGPoint(x: x, y: y))
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

            // Header: logo (if any) at top-left, title/company text beside it.
            let headerTop = y
            var textX = margin
            if let logoImage {
                logoImage.draw(in: CGRect(x: margin, y: headerTop, width: logoSize, height: logoSize))
                textX = margin + logoSize + 12
            }
            drawTitle(report.title, x: textX)
            if !company.isEmpty {
                drawTitle("Company: \(company)", size: 12, bold: false, x: textX)
            }
            if logoImage != nil {
                y = max(y, headerTop + logoSize + 6)
            }
            drawLine()

            drawTitle("Summary", size: 14)
            drawTitle("Total hours: \(String(format: "%.2f", report.totalHours))", size: 12, bold: false)
            drawTitle("Days worked: \(report.daysWorked)", size: 12, bold: false)
            if report.overtimeHours > 0 {
                drawTitle("Overtime hours: \(String(format: "%.2f", report.overtimeHours))", size: 12, bold: false)
            }
            y += 12
            drawLine()

            drawTitle("Entries", size: 14)
            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "MMM d, yyyy"
            let timeFmt = DateFormatter()
            timeFmt.dateFormat = "h:mm a"

            for row in report.rows {
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
    private func buildReport(title: String, range: DateInterval, entries: [WorkEntry], store: HoursStore) -> ExportReport {
        let rows = buildExportRows(range: range, entries: entries, store: store)
        let totalHours = rows.reduce(0) { $0 + $1.totalHours }
        let overtimeHours = rows.reduce(0) { $0 + $1.overtimeHours }
        let daysWorked = Set(rows.map { Calendar.current.startOfDay(for: $0.date) }).count
        return ExportReport(title: title, rows: rows, totalHours: totalHours, overtimeHours: overtimeHours, daysWorked: daysWorked)
    }

    @MainActor
    private func buildExportRows(range: DateInterval, entries: [WorkEntry], store: HoursStore) -> [ExportRow] {
        entries
            .filter { $0.date >= range.start && $0.date < range.end }
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

    @MainActor
    private func buildExportRows(monthDate: Date, entries: [WorkEntry], store: HoursStore) -> [ExportRow] {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else {
            return []
        }
        return buildExportRows(range: DateInterval(start: start, end: end), entries: entries, store: store)
    }
}

enum ExportError: LocalizedError {
    case invalidMonth
    case invalidRange
    case writeFailed
    var errorDescription: String? { "Export failed. Please try again." }
}
