import UIKit

/// A `YearEndSummary` rendered as a letter-size, multi-page PDF in the same
/// look as `PayPeriodStatement` (brand header, detail pairs, summary tiles,
/// zebra tables, page footer). Settings → Year-End Summary.
struct YearEndSummaryDocument {
    let summary: YearEndSummary
    let employee: String?
    let company: String?
    let companyLogo: UIImage?
    let currencyCode: String
    let showPay: Bool

    @MainActor
    static func make(year: Int, store: HoursStore, employee: String?, company: String?, companyLogo: UIImage?) -> YearEndSummaryDocument {
        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }
        let settings = store.paySettings
        // Pay shows when the user asked for pay figures or entered a real
        // wage for any job (a tax summary without gross pay is little use).
        let showPay = settings.showPayCalculations || store.jobs.contains { $0.settings.hourlyRateSet }
        return YearEndSummaryDocument(
            summary: YearEndSummary.make(year: year, store: store),
            employee: clean(employee), company: clean(company), companyLogo: companyLogo,
            currencyCode: settings.currencyCode, showPay: showPay
        )
    }

    func writePDF() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hour Tracker Year-End Summary \(summary.year).pdf")
        try YearEndSummaryRenderer(doc: self).render().write(to: url)
        return url
    }
}

// MARK: - Renderer

private struct YearEndSummaryRenderer {
    let doc: YearEndSummaryDocument
    private var summary: YearEndSummary { doc.summary }

    private let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    private let margin: CGFloat = 48
    private var contentWidth: CGFloat { page.width - margin * 2 }
    private let footerTop: CGFloat = 792 - 56
    private let rowHeight: CGFloat = 20
    private let tableHeaderHeight: CGFloat = 24

    private let ink = UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1)
    private let muted = UIColor(red: 0.42, green: 0.44, blue: 0.50, alpha: 1)
    private let hairline = UIColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1)
    private let zebra = UIColor(red: 0.972, green: 0.973, blue: 0.985, alpha: 1)
    private let brand = UIColor(red: 0.49, green: 0.36, blue: 0.96, alpha: 1)
    private var brandTint: UIColor { brand.withAlphaComponent(0.08) }

    /// A vertical slice of the page; `repeatHeader` is redrawn above it when
    /// it opens a new page (table rows carry their table's header).
    private struct Block {
        let height: CGFloat
        var repeatHeader: (() -> Block)? = nil
        let draw: (CGFloat) -> Void
    }

    private struct Column {
        let title: String
        let width: CGFloat
        let alignRight: Bool
    }

    // MARK: Render

    func render() -> Data {
        let pages = paginate(blocks())
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: {
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = [
                kCGPDFContextTitle as String: "Year-End Summary \(summary.year)",
                kCGPDFContextCreator as String: "Hour Tracker",
            ]
            return format
        }())
        return renderer.pdfData { ctx in
            for (index, placed) in pages.enumerated() {
                ctx.beginPage()
                var y = margin
                drawBrandHeader(y: &y)
                for (block, top) in placed { block.draw(top) }
                drawFooter(page: index + 1, of: pages.count)
            }
        }
    }

    private var brandHeaderBottom: CGFloat { margin + 34 + 14 + 2 }

    /// Lays blocks top to bottom, starting a page whenever one won't fit.
    private func paginate(_ blocks: [Block]) -> [[(Block, CGFloat)]] {
        var pages: [[(Block, CGFloat)]] = [[]]
        var y = brandHeaderBottom
        let bottom = footerTop - 12
        for block in blocks {
            if y + block.height > bottom, !(pages.last?.isEmpty ?? true) {
                pages.append([])
                y = brandHeaderBottom + 16
                if let header = block.repeatHeader?() {
                    pages[pages.count - 1].append((header, y))
                    y += header.height
                }
            }
            pages[pages.count - 1].append((block, y))
            y += block.height
        }
        return pages
    }

    private func blocks() -> [Block] {
        var list: [Block] = [titleBlock(), detailsBlock()]
        list += summaryTiles()
        list.append(noticeBlock())
        if !summary.jobs.isEmpty {
            list.append(sectionLabel("BY JOB"))
            list += table(columns: jobColumns, rows: summary.jobs.map { jobValues($0.name, $0.totals) },
                          total: jobValues("Total", summary.totals))
        }
        list.append(sectionLabel("BY MONTH"))
        let monthNames: [String] = DateFormatter().monthSymbols
        list += table(columns: monthColumns,
                      rows: summary.months.map { monthValues(monthNames[$0.month - 1], $0.totals) },
                      total: monthValues("Total", summary.totals))
        list.append(disclaimerBlock())
        return list
    }

    // MARK: Blocks

    private func titleBlock() -> Block {
        Block(height: 22 + 30 + 24) { top in
            drawText("Year-End Summary \(String(summary.year))", at: CGPoint(x: margin, y: top + 22),
                     font: .systemFont(ofSize: 22, weight: .bold), color: ink)
            drawText("January 1 – December 31, \(String(summary.year))", at: CGPoint(x: margin, y: top + 52),
                     font: .systemFont(ofSize: 11, weight: .medium), color: muted)
        }
    }

    private func detailsBlock() -> Block {
        var pairs: [(String, String)] = []
        if let employee = doc.employee { pairs.append(("Employee", "@\(employee)")) }
        if let company = doc.company { pairs.append(("Company", company)) }
        pairs.append(("Tax year", String(summary.year)))
        pairs.append(("Shifts logged", "\(summary.totals.shiftCount)"))
        if summary.jobs.count > 1 { pairs.append(("Jobs", "\(summary.jobs.count)")) }
        pairs.append(("Generated", Self.longDate.string(from: Date())))
        let colWidth = contentWidth / 3
        return Block(height: CGFloat((pairs.count + 2) / 3) * 30 + 8) { top in
            for (i, pair) in pairs.enumerated() {
                let x = margin + CGFloat(i % 3) * colWidth
                let rowY = top + CGFloat(i / 3) * 30
                drawText(pair.0.uppercased(), at: CGPoint(x: x, y: rowY), font: .systemFont(ofSize: 7.5, weight: .semibold), color: muted, kern: 0.8)
                drawText(pair.1, at: CGPoint(x: x, y: rowY + 11), font: .systemFont(ofSize: 10.5, weight: .medium), color: ink, maxWidth: colWidth - 12)
            }
        }
    }

    private func summaryTiles() -> [Block] {
        let t = summary.totals
        let first: [(String, String)] = [
            ("Total hours", hours(t.totalHours)),
            ("Regular", hours(t.regularHours)),
            ("Overtime", hours(t.overtimeHours)),
            ("Double time", hours(t.doubleTimeHours)),
        ]
        var second: [(String, String)] = [
            ("Days worked", "\(t.daysWorked)"),
            ("Holiday hrs", hours(t.statHolidayHours)),
            ("Stat pay hrs", hours(t.statPayHours)),
        ]
        if doc.showPay {
            second.insert(("Holiday pay", currency(t.statHolidayPay)), at: 3)
            second.append(("Gross pay", currency(t.grossPay)))
        }
        return [tileRow(first, highlightLast: false, gapAfter: 8), tileRow(second, highlightLast: doc.showPay, gapAfter: 18)]
    }

    private func tileRow(_ tiles: [(String, String)], highlightLast: Bool, gapAfter: CGFloat) -> Block {
        let tileHeight: CGFloat = 50
        return Block(height: tileHeight + gapAfter) { top in
            let gap: CGFloat = 8
            let tileWidth = (contentWidth - gap * CGFloat(tiles.count - 1)) / CGFloat(tiles.count)
            for (i, tile) in tiles.enumerated() {
                let rect = CGRect(x: margin + CGFloat(i) * (tileWidth + gap), y: top, width: tileWidth, height: tileHeight)
                let isPay = highlightLast && i == tiles.count - 1
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 7)
                (isPay ? brandTint : zebra).setFill()
                path.fill()
                (isPay ? brand.withAlphaComponent(0.35) : hairline).setStroke()
                path.lineWidth = 0.6
                path.stroke()
                drawText(tile.0.uppercased(), at: CGPoint(x: rect.minX + 10, y: rect.minY + 9), font: .systemFont(ofSize: 7.5, weight: .semibold),
                         color: isPay ? brand : muted, kern: 0.8, maxWidth: tileWidth - 16)
                drawText(tile.1, at: CGPoint(x: rect.minX + 10, y: rect.minY + 22), font: .monospacedDigitSystemFont(ofSize: 14, weight: .bold),
                         color: ink, maxWidth: tileWidth - 16)
            }
        }
    }

    private func noticeBlock() -> Block {
        let text = "Estimate only — not an official tax document. These figures are calculated from the shifts you logged in Hour Tracker"
            + (doc.showPay ? " and your pay settings (wage, overtime, holiday and vacation pay), before any deductions." : ".")
            + " Use your T4, W-2 or employer pay records when filing."
        return Block(height: 46 + 22) { top in
            let rect = CGRect(x: margin, y: top, width: contentWidth, height: 46)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 7)
            brandTint.setFill()
            path.fill()
            fill(CGRect(x: margin, y: top, width: 3, height: 46), brand)
            drawText(text, at: CGPoint(x: margin + 14, y: top + 9), font: .systemFont(ofSize: 8.5, weight: .medium), color: ink,
                     maxWidth: contentWidth - 24, lines: 3)
        }
    }

    private func sectionLabel(_ text: String) -> Block {
        Block(height: 16 + 4) { top in
            drawText(text, at: CGPoint(x: margin, y: top + 4), font: .systemFont(ofSize: 8.5, weight: .bold), color: muted, kern: 1.4)
        }
    }

    private func disclaimerBlock() -> Block {
        Block(height: 44) { top in
            drawText("Hours include every shift dated in \(String(summary.year)), archived years included. Stat holiday hours are shown on their own and are not repeated under regular, overtime or double time.",
                     at: CGPoint(x: margin, y: top + 16), font: .systemFont(ofSize: 7.5), color: muted, maxWidth: contentWidth, lines: 2)
        }
    }

    // MARK: Tables

    private var jobColumns: [Column] {
        stretch([
            Column(title: "Job", width: 120, alignRight: false),
            Column(title: "Days", width: 38, alignRight: true),
            Column(title: "Regular", width: 52, alignRight: true),
            Column(title: "Overtime", width: 56, alignRight: true),
            Column(title: "Double", width: 50, alignRight: true),
            Column(title: "Stat", width: 44, alignRight: true),
            Column(title: "Hours", width: 52, alignRight: true),
        ] + (doc.showPay ? [Column(title: "Gross", width: 76, alignRight: true)] : []))
    }

    private func jobValues(_ name: String, _ b: YearEndSummary.Bucket) -> [String] {
        [name, "\(b.daysWorked)", hours(b.regularHours), dash(b.overtimeHours), dash(b.doubleTimeHours),
         dash(b.statHolidayHours), hours(b.totalHours)] + (doc.showPay ? [currency(b.grossPay)] : [])
    }

    private var monthColumns: [Column] {
        stretch([
            Column(title: "Month", width: 110, alignRight: false),
            Column(title: "Days", width: 44, alignRight: true),
            Column(title: "Regular", width: 60, alignRight: true),
            Column(title: "Overtime", width: 60, alignRight: true),
            Column(title: "Double", width: 54, alignRight: true),
            Column(title: "Hours", width: 60, alignRight: true),
        ] + (doc.showPay ? [Column(title: "Gross", width: 84, alignRight: true)] : []))
    }

    private func monthValues(_ name: String, _ b: YearEndSummary.Bucket) -> [String] {
        [name, "\(b.daysWorked)", hours(b.regularHours), dash(b.overtimeHours), dash(b.doubleTimeHours),
         hours(b.totalHours)] + (doc.showPay ? [currency(b.grossPay)] : [])
    }

    /// Widens the first column so the table spans the content width.
    private func stretch(_ cols: [Column]) -> [Column] {
        var cols = cols
        let used = cols.reduce(0) { $0 + $1.width }
        cols[0] = Column(title: cols[0].title, width: cols[0].width + (contentWidth - used), alignRight: false)
        return cols
    }

    private func table(columns: [Column], rows: [[String]], total: [String]) -> [Block] {
        let header = {
            Block(height: tableHeaderHeight) { top in
                fill(CGRect(x: margin, y: top, width: contentWidth, height: tableHeaderHeight), brandTint)
                var x = margin
                for col in columns {
                    drawCell(col.title, x: x, width: col.width, rowY: top, rowHeight: tableHeaderHeight, alignRight: col.alignRight,
                             font: .systemFont(ofSize: 8, weight: .bold), color: brand)
                    x += col.width
                }
            }
        }
        var list = [header()]
        for (i, values) in rows.enumerated() {
            list.append(Block(height: rowHeight, repeatHeader: header) { top in
                if i % 2 == 1 { fill(CGRect(x: margin, y: top, width: contentWidth, height: rowHeight), zebra) }
                drawValues(values, columns: columns, top: top, height: rowHeight, bold: false)
                fill(CGRect(x: margin, y: top + rowHeight - 0.5, width: contentWidth, height: 0.5), hairline)
            })
        }
        list.append(Block(height: rowHeight + 2 + 1.2 + 18, repeatHeader: header) { top in
            fill(CGRect(x: margin, y: top, width: contentWidth, height: 1.2), ink)
            drawValues(total, columns: columns, top: top + 1.2, height: rowHeight + 2, bold: true)
        })
        return list
    }

    private func drawValues(_ values: [String], columns: [Column], top: CGFloat, height: CGFloat, bold: Bool) {
        var x = margin
        for (i, (value, col)) in zip(values, columns).enumerated() {
            let font: UIFont = i == 0
                ? .systemFont(ofSize: 9, weight: bold ? .bold : .medium)
                : .monospacedDigitSystemFont(ofSize: 9, weight: bold ? .bold : .regular)
            drawCell(value, x: x, width: col.width, rowY: top, rowHeight: height, alignRight: col.alignRight, font: font, color: ink)
            x += col.width
        }
    }

    // MARK: Header & footer

    private func drawBrandHeader(y: inout CGFloat) {
        drawText("Hour Tracker", at: CGPoint(x: margin, y: y + 1), font: .systemFont(ofSize: 15, weight: .bold), color: ink)
        drawText("Work & pay records", at: CGPoint(x: margin, y: y + 19), font: .systemFont(ofSize: 9, weight: .medium), color: muted)
        let right = page.width - margin
        if let logo = doc.companyLogo {
            let aspect = logo.size.width / max(logo.size.height, 1)
            let h: CGFloat = 30
            let w = min(120, h * aspect)
            logo.draw(in: CGRect(x: right - w, y: y + 2, width: w, height: h))
        } else {
            drawText("YEAR-END SUMMARY", rightAlignedTo: right, y: y + 4, font: .systemFont(ofSize: 9, weight: .bold), color: brand, kern: 1.4)
            drawText("Tax year \(String(summary.year))", rightAlignedTo: right, y: y + 19, font: .systemFont(ofSize: 9), color: muted)
        }
        y += 34 + 14
        fill(CGRect(x: margin, y: y, width: contentWidth, height: 2), brand)
        y += 2
    }

    private func drawFooter(page number: Int, of total: Int) {
        fill(CGRect(x: margin, y: footerTop, width: contentWidth, height: 0.5), hairline)
        drawText("Generated with Hour Tracker · Estimate, not a tax document", at: CGPoint(x: margin, y: footerTop + 10),
                 font: .systemFont(ofSize: 8), color: muted)
        drawText("Page \(number) of \(total)", rightAlignedTo: page.width - margin, y: footerTop + 10, font: .systemFont(ofSize: 8), color: muted)
    }

    // MARK: Drawing primitives (same as PayPeriodStatementRenderer's)

    private func fill(_ rect: CGRect, _ color: UIColor) {
        color.setFill()
        UIRectFill(rect)
    }

    private func attributes(_ font: UIFont, _ color: UIColor, kern: CGFloat = 0, wrap: Bool = false) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
        return [.font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: style]
    }

    private func drawText(_ text: String, at point: CGPoint, font: UIFont, color: UIColor, kern: CGFloat = 0,
                          maxWidth: CGFloat? = nil, lines: Int = 1) {
        let attr = NSAttributedString(string: text, attributes: attributes(font, color, kern: kern, wrap: lines > 1))
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

    private func hours(_ value: Double) -> String { String(format: "%.2f", value) }

    private func dash(_ value: Double) -> String { value > 0.0049 ? hours(value) : "—" }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = doc.currencyCode
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
}
