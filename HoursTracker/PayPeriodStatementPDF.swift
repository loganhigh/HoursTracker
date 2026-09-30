import UIKit

/// One pay period rendered as a printable, letter-size statement: app name
/// top-left, period details, summary figures, and every shift in a table.
/// Shared from a cheque's detail screen (History → cheque → Share).
struct PayPeriodStatement {
    struct Row {
        let date: Date
        let start: Date
        let end: Date
        let breakMinutes: Int
        let regularHours: Double
        let overtimeHours: Double
        let totalHours: Double
        let pay: Double
        let isOffDay: Bool
        let offDayReason: String
        let isHoliday: Bool
        /// Stat holiday rule and its stat-pay hours, when the day is one.
        let holidayRule: HolidayPayRule?
        let statPayHours: Double
        let notes: String
    }

    let periodStart: Date
    /// Last day of work included (inclusive).
    let periodEnd: Date
    let payday: Date
    let employee: String?
    let company: String?
    let companyLogo: UIImage?
    let payFrequency: String
    let hourlyRate: Double
    let currencyCode: String
    let showPay: Bool
    let rows: [Row]

    var workRows: [Row] { rows.filter { !$0.isOffDay } }
    var totalHours: Double { workRows.reduce(0) { $0 + $1.totalHours } }
    var regularHours: Double { workRows.reduce(0) { $0 + $1.regularHours } }
    var overtimeHours: Double { workRows.reduce(0) { $0 + $1.overtimeHours } }
    /// Stat pay hours across the period (paid at the regular rate, not worked).
    var statPayHours: Double { rows.reduce(0) { $0 + $1.statPayHours } }
    /// Includes stat pay on holidays that weren't worked.
    var grossPay: Double { rows.reduce(0) { $0 + $1.pay } }
    var daysWorked: Int { Set(workRows.map { Calendar.current.startOfDay(for: $0.date) }).count }

    @MainActor
    static func make(cycle: PayCycle, store: HoursStore, employee: String?, company: String?, companyLogo: UIImage?) -> PayPeriodStatement {
        let settings = store.paySettings
        let rows = PayCycleEngine.entries(store.entries, in: cycle)
            .sorted { $0.date == $1.date ? $0.start < $1.start : $0.date < $1.date }
            .map { entry -> Row in
                let b = store.payBreakdown(for: entry)
                return Row(
                    date: entry.date, start: entry.start, end: entry.end,
                    breakMinutes: entry.breakMinutes,
                    regularHours: b.regularHours, overtimeHours: b.overtimeHours,
                    totalHours: entry.paidHours, pay: b.pay,
                    isOffDay: entry.isOffDay, offDayReason: entry.offDayReason,
                    isHoliday: entry.isHoliday,
                    holidayRule: entry.holidayPayRule, statPayHours: b.statPayHours,
                    notes: entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }
        return PayPeriodStatement(
            periodStart: cycle.start, periodEnd: cycle.cutoff, payday: cycle.payday,
            employee: clean(employee), company: clean(company), companyLogo: companyLogo,
            payFrequency: settings.payPeriodType.displayName,
            hourlyRate: settings.hourlyRate, currencyCode: settings.currencyCode,
            showPay: settings.showPayCalculations, rows: rows
        )
    }

    /// Writes the PDF to a temp file named after the period and returns its URL.
    func writePDF() throws -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hour Tracker Statement \(f.string(from: periodStart)).pdf")
        try PayPeriodStatementRenderer(statement: self).render().write(to: url)
        return url
    }
}

// MARK: - Renderer

private struct PayPeriodStatementRenderer {
    let statement: PayPeriodStatement

    // Letter, points.
    private let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    private let margin: CGFloat = 48
    private var contentWidth: CGFloat { page.width - margin * 2 }
    private let footerTop: CGFloat = 792 - 56
    private let rowHeight: CGFloat = 20
    private let noteHeight: CGFloat = 13
    private let tableHeaderHeight: CGFloat = 24

    private let ink = UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1)
    private let muted = UIColor(red: 0.42, green: 0.44, blue: 0.50, alpha: 1)
    private let hairline = UIColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1)
    private let zebra = UIColor(red: 0.972, green: 0.973, blue: 0.985, alpha: 1)
    private let brand = UIColor(red: 0.49, green: 0.36, blue: 0.96, alpha: 1)
    private var brandTint: UIColor { brand.withAlphaComponent(0.08) }

    private struct Column {
        let title: String
        let width: CGFloat
        let alignRight: Bool
    }

    private var columns: [Column] {
        var cols = [
            Column(title: "Date", width: 118, alignRight: false),
            Column(title: "Start", width: 62, alignRight: false),
            Column(title: "End", width: 62, alignRight: false),
            Column(title: "Break", width: 44, alignRight: true),
            Column(title: "Regular", width: 54, alignRight: true),
            Column(title: "Overtime", width: 58, alignRight: true),
            Column(title: "Hours", width: 50, alignRight: true),
        ]
        if statement.showPay { cols.append(Column(title: "Pay", width: 68, alignRight: true)) }
        // Stretch the date column so the table always spans the content width.
        let used = cols.reduce(0) { $0 + $1.width }
        cols[0] = Column(title: "Date", width: cols[0].width + (contentWidth - used), alignRight: false)
        return cols
    }

    func render() -> Data {
        let pages = paginate()
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: {
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = [
                kCGPDFContextTitle as String: "Hours Statement",
                kCGPDFContextCreator as String: "Hour Tracker",
            ]
            return format
        }())
        return renderer.pdfData { ctx in
            for (index, rowRange) in pages.enumerated() {
                ctx.beginPage()
                var y = margin
                drawBrandHeader(y: &y)
                if index == 0 {
                    drawTitleBlock(y: &y)
                    drawDetails(y: &y)
                    drawSummary(y: &y)
                    drawSectionLabel("SHIFTS", y: &y)
                }
                if statement.rows.isEmpty {
                    drawText("No shifts were logged in this pay period.", at: CGPoint(x: margin, y: y + 6), font: .systemFont(ofSize: 10), color: muted)
                    y += 30
                } else {
                    drawTableHeader(y: &y)
                    for i in rowRange { drawRow(statement.rows[i], index: i, y: &y) }
                    if index == pages.count - 1 { drawTotalsRow(y: &y) }
                }
                if index == pages.count - 1 { drawDisclaimer(y: y) }
                drawFooter(page: index + 1, of: pages.count)
            }
        }
    }

    // MARK: Pagination

    private func height(of row: PayPeriodStatement.Row) -> CGFloat {
        rowHeight + (row.notes.isEmpty ? 0 : noteHeight)
    }

    /// Splits rows across pages, reserving room for the totals row and the
    /// disclaimer on the last page. Mirrors the vertical layout in render().
    private func paginate() -> [Range<Int>] {
        let firstPageTableTop = brandHeaderBottom + titleBlockHeight + detailsHeight + summaryHeight + sectionLabelHeight
        let laterPageTableTop = brandHeaderBottom
        let lastPageReserve: CGFloat = rowHeight + 8 + 40
        guard !statement.rows.isEmpty else { return [0..<0] }

        var pages: [Range<Int>] = []
        var start = 0
        var y = firstPageTableTop + tableHeaderHeight
        for i in statement.rows.indices {
            let h = height(of: statement.rows[i])
            if y + h > footerTop - 12, i > start {
                pages.append(start..<i)
                start = i
                y = laterPageTableTop + tableHeaderHeight
            }
            y += h
        }
        if y + lastPageReserve > footerTop - 12, statement.rows.count - start > 1 {
            // Totals + disclaimer won't fit: carry the last row over so the
            // totals never sit alone on a page.
            pages.append(start..<(statement.rows.count - 1))
            start = statement.rows.count - 1
        }
        pages.append(start..<statement.rows.count)
        return pages
    }

    // MARK: Header

    // Vertical extents of the page-one blocks; the draw functions advance y
    // by exactly these, and paginate() relies on them matching.
    private let brandHeaderHeight: CGFloat = 34
    private var brandHeaderBottom: CGFloat { margin + brandHeaderHeight + 14 + 2 }
    private let titleBlockHeight: CGFloat = 22 + 30 + 24
    private var detailsHeight: CGFloat { CGFloat((detailPairs.count + 2) / 3) * 30 + 8 }
    private let summaryHeight: CGFloat = 50 + 22
    private let sectionLabelHeight: CGFloat = 16

    private var detailPairs: [(String, String)] {
        var pairs: [(String, String)] = []
        if let employee = statement.employee { pairs.append(("Employee", "@\(employee)")) }
        if let company = statement.company { pairs.append(("Company", company)) }
        pairs.append(("Pay date", Self.longDate.string(from: statement.payday)))
        pairs.append(("Pay frequency", statement.payFrequency))
        if statement.showPay, statement.hourlyRate > 0 {
            pairs.append(("Base rate", "\(currency(statement.hourlyRate)) / hour"))
        }
        return pairs
    }

    private func drawBrandHeader(y: inout CGFloat) {
        let textX = margin
        drawText("Hour Tracker", at: CGPoint(x: textX, y: y + 1), font: .systemFont(ofSize: 15, weight: .bold), color: ink)
        drawText("Work & pay records", at: CGPoint(x: textX, y: y + 19), font: .systemFont(ofSize: 9, weight: .medium), color: muted)

        let right = page.width - margin
        if let companyLogo = statement.companyLogo {
            let aspect = companyLogo.size.width / max(companyLogo.size.height, 1)
            let h: CGFloat = 30
            let w = min(120, h * aspect)
            companyLogo.draw(in: CGRect(x: right - w, y: y + 2, width: w, height: h))
        } else {
            drawText("HOURS STATEMENT", rightAlignedTo: right, y: y + 4, font: .systemFont(ofSize: 9, weight: .bold), color: brand, kern: 1.4)
            drawText("Generated \(Self.longDate.string(from: Date()))", rightAlignedTo: right, y: y + 19, font: .systemFont(ofSize: 9), color: muted)
        }
        y += brandHeaderHeight + 14
        fill(CGRect(x: margin, y: y, width: contentWidth, height: 2), brand)
        y += 2
    }

    private func drawTitleBlock(y: inout CGFloat) {
        y += 22
        drawText("Hours Statement", at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 22, weight: .bold), color: ink)
        y += 30
        let range = "\(Self.shortDate.string(from: statement.periodStart)) – \(Self.longDate.string(from: statement.periodEnd))"
        drawText(range, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 11, weight: .medium), color: muted)
        y += 24
    }

    private func drawDetails(y: inout CGFloat) {
        let pairs = detailPairs
        let colWidth = contentWidth / 3
        for (i, pair) in pairs.enumerated() {
            let x = margin + CGFloat(i % 3) * colWidth
            let rowY = y + CGFloat(i / 3) * 30
            drawText(pair.0.uppercased(), at: CGPoint(x: x, y: rowY), font: .systemFont(ofSize: 7.5, weight: .semibold), color: muted, kern: 0.8)
            drawText(pair.1, at: CGPoint(x: x, y: rowY + 11), font: .systemFont(ofSize: 10.5, weight: .medium), color: ink, maxWidth: colWidth - 12)
        }
        y += detailsHeight
    }

    private func drawSummary(y: inout CGFloat) {
        var tiles: [(String, String)] = [
            ("Total hours", hours(statement.totalHours)),
            ("Regular", hours(statement.regularHours)),
            ("Overtime", hours(statement.overtimeHours)),
            ("Days worked", "\(statement.daysWorked)"),
        ]
        if statement.statPayHours > 0 { tiles.append(("Stat pay", hours(statement.statPayHours))) }
        if statement.showPay { tiles.append(("Gross pay", currency(statement.grossPay))) }
        let gap: CGFloat = 8
        let tileWidth = (contentWidth - gap * CGFloat(tiles.count - 1)) / CGFloat(tiles.count)
        let tileHeight: CGFloat = 50
        for (i, tile) in tiles.enumerated() {
            let rect = CGRect(x: margin + CGFloat(i) * (tileWidth + gap), y: y, width: tileWidth, height: tileHeight)
            let isPay = statement.showPay && i == tiles.count - 1
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 7)
            (isPay ? brandTint : zebra).setFill()
            path.fill()
            (isPay ? brand.withAlphaComponent(0.35) : hairline).setStroke()
            path.lineWidth = 0.6
            path.stroke()
            drawText(tile.0.uppercased(), at: CGPoint(x: rect.minX + 10, y: rect.minY + 9), font: .systemFont(ofSize: 7.5, weight: .semibold), color: isPay ? brand : muted, kern: 0.8)
            drawText(tile.1, at: CGPoint(x: rect.minX + 10, y: rect.minY + 22), font: .monospacedDigitSystemFont(ofSize: 15, weight: .bold), color: ink, maxWidth: tileWidth - 16)
        }
        y += tileHeight + 22
    }

    private func drawSectionLabel(_ text: String, y: inout CGFloat) {
        drawText(text, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 8.5, weight: .bold), color: muted, kern: 1.4)
        y += 16
    }

    // MARK: Table

    private func drawTableHeader(y: inout CGFloat) {
        fill(CGRect(x: margin, y: y, width: contentWidth, height: tableHeaderHeight), brandTint)
        var x = margin
        for col in columns {
            drawCell(col.title, x: x, width: col.width, rowY: y, rowHeight: tableHeaderHeight, alignRight: col.alignRight,
                     font: .systemFont(ofSize: 8, weight: .bold), color: brand)
            x += col.width
        }
        y += tableHeaderHeight
    }

    private func drawRow(_ row: PayPeriodStatement.Row, index: Int, y: inout CGFloat) {
        let h = height(of: row)
        if index % 2 == 1 { fill(CGRect(x: margin, y: y, width: contentWidth, height: h), zebra) }
        let font = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        var dateText = Self.rowDate.string(from: row.date)
        if let rule = row.holidayRule { dateText += " · \(rule.shortTitle)" }
        else if row.isHoliday { dateText += " · Holiday" }

        var x = margin
        let cols = columns
        drawCell(dateText, x: x, width: cols[0].width, rowY: y, rowHeight: rowHeight, alignRight: false, font: .systemFont(ofSize: 9, weight: .medium), color: ink)
        x += cols[0].width
        if row.isOffDay && row.statPayHours > 0 {
            // Stat holiday not worked: paid hours at the regular rate.
            let payWidth = statement.showPay ? cols.last!.width : 0
            drawCell("Stat holiday · \(hours(row.statPayHours)) stat pay", x: x, width: contentWidth - cols[0].width - payWidth, rowY: y, rowHeight: rowHeight,
                     alignRight: false, font: .italicSystemFont(ofSize: 9), color: muted)
            if statement.showPay {
                drawCell(currency(row.pay), x: margin + contentWidth - payWidth, width: payWidth, rowY: y, rowHeight: rowHeight, alignRight: true, font: font, color: ink)
            }
        } else if row.isOffDay {
            let reason = row.offDayReason.trimmingCharacters(in: .whitespacesAndNewlines)
            drawCell(reason.isEmpty ? "Day off" : "Day off · \(reason)", x: x, width: contentWidth - cols[0].width, rowY: y, rowHeight: rowHeight,
                     alignRight: false, font: .italicSystemFont(ofSize: 9), color: muted)
        } else {
            var values = [
                Self.time.string(from: row.start),
                Self.time.string(from: row.end),
                row.breakMinutes > 0 ? duration(minutes: row.breakMinutes) : "—",
                hours(row.regularHours),
                row.overtimeHours > 0 ? hours(row.overtimeHours) : "—",
                hours(row.totalHours),
            ]
            if statement.showPay { values.append(currency(row.pay)) }
            for (value, col) in zip(values, cols.dropFirst()) {
                drawCell(value, x: x, width: col.width, rowY: y, rowHeight: rowHeight, alignRight: col.alignRight, font: font, color: ink)
                x += col.width
            }
        }
        if !row.notes.isEmpty {
            drawText(row.notes, at: CGPoint(x: margin + 8, y: y + rowHeight - 5), font: .systemFont(ofSize: 7.5), color: muted, maxWidth: contentWidth - 16)
        }
        y += h
        fill(CGRect(x: margin, y: y - 0.5, width: contentWidth, height: 0.5), hairline)
    }

    private func drawTotalsRow(y: inout CGFloat) {
        fill(CGRect(x: margin, y: y, width: contentWidth, height: 1.2), ink)
        y += 1.2
        let bold = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        let cols = columns
        var x = margin
        drawCell("Total", x: x, width: cols[0].width, rowY: y, rowHeight: rowHeight + 2, alignRight: false, font: .systemFont(ofSize: 9, weight: .bold), color: ink)
        x += cols[0].width
        let breakTotal = statement.workRows.reduce(0) { $0 + $1.breakMinutes }
        var values = ["", "", breakTotal > 0 ? duration(minutes: breakTotal) : "—", hours(statement.regularHours),
                      statement.overtimeHours > 0 ? hours(statement.overtimeHours) : "—", hours(statement.totalHours)]
        if statement.showPay { values.append(currency(statement.grossPay)) }
        for (value, col) in zip(values, cols.dropFirst()) {
            drawCell(value, x: x, width: col.width, rowY: y, rowHeight: rowHeight + 2, alignRight: col.alignRight, font: bold, color: ink)
            x += col.width
        }
        y += rowHeight + 2
    }

    private func drawDisclaimer(y: CGFloat) {
        let text = statement.showPay
            ? "Pay figures are estimates calculated from your pay settings (rate, overtime and holiday rules) before deductions. They may differ from your official pay stub."
            : "Hours are as logged in Hour Tracker."
        drawText(text, at: CGPoint(x: margin, y: min(y + 16, footerTop - 34)), font: .systemFont(ofSize: 7.5), color: muted, maxWidth: contentWidth, lines: 2)
    }

    private func drawFooter(page number: Int, of total: Int) {
        fill(CGRect(x: margin, y: footerTop, width: contentWidth, height: 0.5), hairline)
        drawText("Generated with Hour Tracker", at: CGPoint(x: margin, y: footerTop + 10), font: .systemFont(ofSize: 8), color: muted)
        drawText("Page \(number) of \(total)", rightAlignedTo: page.width - margin, y: footerTop + 10, font: .systemFont(ofSize: 8), color: muted)
    }

    // MARK: Drawing primitives

    private func fill(_ rect: CGRect, _ color: UIColor) {
        color.setFill()
        UIRectFill(rect)
    }

    private func attributes(_ font: UIFont, _ color: UIColor, kern: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return [.font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: style]
    }

    private func drawText(_ text: String, at point: CGPoint, font: UIFont, color: UIColor, kern: CGFloat = 0,
                          maxWidth: CGFloat? = nil, lines: Int = 1) {
        var attrs = attributes(font, color, kern: kern)
        if lines > 1, let style = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            style.lineBreakMode = .byWordWrapping
            attrs[.paragraphStyle] = style
        }
        let attr = NSAttributedString(string: text, attributes: attrs)
        let width = maxWidth ?? attr.size().width + 1
        attr.draw(with: CGRect(x: point.x, y: point.y, width: width, height: font.lineHeight * CGFloat(lines) + 2),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    private func drawText(_ text: String, rightAlignedTo right: CGFloat, y: CGFloat, font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let width = NSAttributedString(string: text, attributes: attributes(font, color, kern: kern)).size().width
        drawText(text, at: CGPoint(x: right - width, y: y), font: font, color: color, kern: kern)
    }

    private func drawCell(_ text: String, x: CGFloat, width: CGFloat, rowY: CGFloat, rowHeight: CGFloat,
                          alignRight: Bool, font: UIFont, color: UIColor) {
        let padding: CGFloat = 8
        let textY = rowY + (rowHeight - font.lineHeight) / 2
        if alignRight {
            drawText(text, rightAlignedTo: x + width - padding, y: textY, font: font, color: color)
        } else {
            drawText(text, at: CGPoint(x: x + padding, y: textY), font: font, color: color, maxWidth: width - padding * 2)
        }
    }

    // MARK: Formatting

    /// "30m", "1h 30m", "6h".
    private func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func hours(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = statement.currencyCode
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private static let rowDate: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    private static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}
